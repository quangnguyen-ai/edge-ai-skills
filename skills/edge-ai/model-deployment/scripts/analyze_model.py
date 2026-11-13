#!/usr/bin/env python3
"""Resource analysis of an ONNX model before conversion.

Reports: op histogram, parameter count/bytes, MACs per op type (Conv, ConvTranspose,
Gemm, MatMul), activation tensor sizes and an estimate of peak live activation memory,
the largest single tensors, and (with --profile) measured per-op-type time from
ONNX Runtime on this machine's CPU.

  analyze_model.py model.onnx [--input name=1,3,640,640 ...] [--profile N] [--threads T]

Numbers are for the graph as exported (batch and dynamic dims resolved by --input).
MACs cover the heavy linear ops only; elementwise ops are not counted.
"""
import argparse
import collections
import json
import os
import tempfile
import time

import numpy as np
import onnx
from onnx import numpy_helper, shape_inference

DT = {1: 4, 2: 1, 3: 1, 5: 2, 6: 4, 7: 8, 9: 1, 10: 2, 11: 8, 16: 2}  # elem_type -> bytes


def dims(vi):
    t = vi.type.tensor_type
    return [d.dim_value if d.dim_value > 0 else None for d in t.shape.dim], t.elem_type


def fix_inputs(model, overrides):
    for inp in model.graph.input:
        if inp.name in overrides:
            shape = overrides[inp.name]
            dl = inp.type.tensor_type.shape.dim
            for i, v in enumerate(shape):
                dl[i].ClearField("dim_param")
                dl[i].dim_value = v
    return model


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("--input", action="append", default=[], help="name=d0,d1,... to fix dynamic dims")
    ap.add_argument("--profile", type=int, default=0, help="run N timed inferences with ORT CPU and break time down per op type")
    ap.add_argument("--threads", type=int, default=0)
    a = ap.parse_args()

    overrides = {k: [int(x) for x in v.split(",")] for k, v in (s.split("=", 1) for s in a.input)}
    m = onnx.load(a.model)
    m = fix_inputs(m, overrides)
    inits = {t.name: t for t in m.graph.initializer}
    m = shape_inference.infer_shapes(m, data_prop=True)
    g = m.graph

    shapes = {}
    for vi in list(g.input) + list(g.value_info) + list(g.output):
        shapes[vi.name] = dims(vi)
    for name, t in inits.items():
        shapes[name] = (list(t.dims), t.data_type)

    # parameters
    n_params = sum(int(np.prod(t.dims)) for t in inits.values())
    p_bytes = sum(int(np.prod(t.dims)) * DT.get(t.data_type, 4) for t in inits.values())

    # MACs
    macs = collections.Counter()
    for n in g.node:
        if n.op_type in ("Conv", "ConvTranspose"):
            w = shapes.get(n.input[1], (None,))[0]
            out = shapes.get(n.output[0], (None,))[0]
            if w and out and None not in w and None not in out:
                k = int(np.prod(w[1:]))  # Cin/groups * kh * kw
                macs[n.op_type] += int(np.prod(out)) * k
        elif n.op_type in ("Gemm", "MatMul"):
            A = shapes.get(n.input[0], (None,))[0]
            out = shapes.get(n.output[0], (None,))[0]
            if A and out and None not in A and None not in out:
                macs[n.op_type] += int(np.prod(out)) * A[-1]

    # activation memory: tensor sizes + simple liveness over node order
    def nbytes(name):
        s, et = shapes.get(name, (None, 1))
        if not s or None in s:
            return None
        return int(np.prod(s)) * DT.get(et, 4)

    last_use = {}
    for i, n in enumerate(g.node):
        for x in n.input:
            last_use[x] = i
    for o in g.output:
        last_use[o.name] = len(g.node)
    live, cur, peak, unknown = {}, 0, 0, 0
    for x in g.input:
        if x.name not in inits:
            b = nbytes(x.name) or 0
            live[x.name] = b
            cur += b
    sizes = []
    for i, n in enumerate(g.node):
        for o in n.output:
            b = nbytes(o)
            if b is None:
                unknown += 1
                continue
            live[o] = b
            cur += b
            sizes.append((b, o, n.op_type))
        peak = max(peak, cur)
        for x in list(live):
            if last_use.get(x, -1) <= i and x not in [o.name for o in g.output]:
                cur -= live.pop(x)

    ops = collections.Counter(n.op_type for n in g.node)
    print(f"model: {os.path.basename(a.model)}  opset: {[o.version for o in m.opset_import]}")
    print("inputs: " + ", ".join(f"{x.name}{shapes[x.name][0]}" for x in g.input if x.name not in inits))
    print("outputs: " + ", ".join(f"{x.name}{shapes[x.name][0]}" for x in g.output))
    print(f"nodes: {len(g.node)}  params: {n_params/1e6:.2f} M ({p_bytes/1e6:.1f} MB as stored)")
    tot = sum(macs.values())
    print(f"MACs (linear ops): {tot/1e9:.2f} G  = " + ", ".join(f"{k} {v/1e9:.2f}G" for k, v in macs.most_common()))
    print(f"activations: peak live ≈ {peak/1e6:.1f} MB (fp32 sizes, node order), "
          f"sum of all = {sum(s for s, _, _ in sizes)/1e6:.1f} MB, unknown-shape tensors: {unknown}")
    print("largest tensors: " + "; ".join(f"{o} ({op}) {b/1e6:.1f} MB" for b, o, op in sorted(sizes, reverse=True)[:5]))
    print("op histogram: " + ", ".join(f"{k}×{v}" for k, v in ops.most_common()))

    if a.profile:
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.enable_profiling = True
        so.profile_file_prefix = os.path.join(tempfile.mkdtemp(), "prof")
        if a.threads:
            so.intra_op_num_threads = a.threads
        sess = ort.InferenceSession(a.model, so, providers=["CPUExecutionProvider"])
        feeds = {}
        for i in sess.get_inputs():
            shp = overrides.get(i.name) or [d if isinstance(d, int) else 1 for d in i.shape]
            dt = np.float32 if "float" in i.type else np.uint8
            feeds[i.name] = np.random.rand(*shp).astype(dt)
        for _ in range(3):
            sess.run(None, feeds)  # warm-up
        t = []
        for _ in range(a.profile):
            t0 = time.perf_counter()
            sess.run(None, feeds)
            t.append((time.perf_counter() - t0) * 1e3)
        prof = sess.end_profiling()
        per_op = collections.Counter()
        for ev in json.load(open(prof)):
            if ev.get("cat") == "Node" and ev["name"].endswith("_kernel_time"):
                per_op[ev["args"].get("op_name", "?")] += ev["dur"]
        total = sum(per_op.values()) or 1
        t = np.array(t)
        print(f"ORT CPU ({a.threads or 'default'} threads), {a.profile} runs: "
              f"p50 {np.percentile(t,50):.1f} ms, p99 {np.percentile(t,99):.1f} ms")
        print("time by op type: " + ", ".join(f"{k} {100*v/total:.0f}%" for k, v in per_op.most_common(8)))


if __name__ == "__main__":
    main()
