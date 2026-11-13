#!/usr/bin/env python3
"""ARM CPU inference bench: first-run (cold) time and steady-state p50/p99.
  bench.py ort <model.onnx> <threads> <runs>
  bench.py tfl <model.tflite> <threads> <runs>
"""
import sys, time
import numpy as np

kind, path, threads, runs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
if kind == "ort":
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.intra_op_num_threads = threads
    so.inter_op_num_threads = 1
    t0 = time.perf_counter()
    s = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"])
    load = (time.perf_counter() - t0) * 1e3
    i = s.get_inputs()[0]
    x = np.random.rand(*[d if isinstance(d, int) else 1 for d in i.shape]).astype(np.float32)
    run = lambda: s.run(None, {i.name: x})
else:
    from ai_edge_litert.interpreter import Interpreter
    t0 = time.perf_counter()
    it = Interpreter(model_path=path, num_threads=threads)
    it.allocate_tensors()
    load = (time.perf_counter() - t0) * 1e3
    d = it.get_input_details()[0]
    if d["dtype"] == np.uint8:
        x = np.random.randint(0, 256, d["shape"], dtype=np.uint8)
    else:
        x = np.random.rand(*d["shape"]).astype(d["dtype"])
    def run():
        it.set_tensor(d["index"], x)
        it.invoke()

t0 = time.perf_counter(); run(); first = (time.perf_counter() - t0) * 1e3
for _ in range(3):
    run()
t = []
for _ in range(runs):
    t0 = time.perf_counter(); run(); t.append((time.perf_counter() - t0) * 1e3)
t = np.array(t)
print(f"{kind} {path.split('/')[-1]} threads={threads} load={load:.0f}ms first={first:.1f}ms p50={np.percentile(t,50):.2f}ms p99={np.percentile(t,99):.2f}ms max={t.max():.2f}ms n={runs}")
