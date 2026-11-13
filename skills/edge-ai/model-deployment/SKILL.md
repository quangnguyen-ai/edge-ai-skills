---
name: model-deployment
description: Take a trained PyTorch/TensorFlow model to an inference engine on an edge target — ONNX export, TensorRT / Qualcomm QAIRT (SNPE, QNN) / ONNX Runtime conversion, unsupported-op triage, parity testing, on-target benchmarking. Use when the user wants to export, convert, deploy, or port a model to Jetson/ARM/an edge device, a conversion or export fails, or the deployed model's output differs from the original or misses its latency budget.
---

# Model deployment

Every step ends on a check against the **golden reference** from step 2. A conversion that "builds" proves nothing; a conversion whose outputs match the framework on real inputs, within a tolerance agreed up front, does.

Read `docs/agents/execution-environment.md` (if it exists) first. If the target is remote-only, every "run on target" below becomes: write the exact command, ask the user to run it, wait for the pasted output. Keep a notes file in the repo (`docs/deploy-notes.md` or the project's equivalent) and log every number and dead end there.

## 1. Intake — the model card

Before touching an exporter, fill in:

- Framework + version, checkpoint, how to load it in eval mode.
- **Input contract**: shape, layout (NCHW/NHWC), dtype, color order (RGB/BGR), value range, normalization (mean/std), resize method (stretch / letterbox / crop) and interpolation. Which of these happen inside the model and which in application code.
- Which dims must be dynamic (batch? resolution?). Default to fixed shapes — they build faster engines and fail less.
- **Output contract**: tensors, meaning, and the post-processing (decode, NMS, softmax, thresholds).
- Target: SoC, accelerator (GPU / DLA / NPU / DSP / CPU), engine and version (e.g. JetPack + TensorRT, QAIRT + SNPE/QNN backend, ONNX Runtime + EP). **Qualcomm targets: read [references/qualcomm.md](references/qualcomm.md) first** — accelerator per SoC, op limits, layout, zero-copy. **ARM CPU targets: [references/arm-cpu.md](references/arm-cpu.md)** — threads, pinning, float vs int8.
- License of the model and weights (AGPL vs Apache/MIT) — a commercial product may not accept copyleft obligations.
- Budget: end-to-end latency (p50 and p99), throughput, memory, power; accuracy metric and the **allowed drop**.

- **Resource analysis**: `scripts/analyze_model.py model.onnx [--input name=1,3,H,W] [--profile 20]` — parameters, MACs by op type, peak live activation memory, largest tensors, op histogram, and measured per-op-type time on the CPU. Compare against the target's memory and compute budget before converting; ops that dominate time or that the target doesn't support are the first questions for the research team.

Done when every field is filled or explicitly marked unknown and asked about. The input contract is the #1 source of "the engine is wrong" bugs that are actually preprocessing bugs.

## 2. Golden reference

- Pick 20–100 **real** inputs (not random noise — random inputs hide range and numerics problems), including the edge cases the product sees (dark, overexposed, empty scene, crowded scene).
- Run them through the framework model in eval mode with the production preprocessing. Save inputs and every output tensor (`.npy`).
- Compute the task metric (mAP, top-1, IoU…) on a held-out validation subset with the framework model.

Done when the inputs, outputs, and metric are saved in the repo or a referenced path, with the script that produced them. Every later step compares against this.

## 3. Export to ONNX (or the engine's input format)

- PyTorch: `model.eval()`, then `torch.onnx.export` (or the `dynamo=True` exporter on recent PyTorch). Choose an opset the target engine supports; mark dynamic axes only where step 1 requires them.
- TensorFlow/Keras: `tf2onnx`, or the TFLite converter directly when TFLite is the target.
- Clean up: `onnx.checker.check_model`, then `onnxsim` (onnx-simplifier) to fold constants and shape-computation chains. Inspect with Netron or `polygraphy inspect model`.
- **Parity:** run the ONNX model in ONNX Runtime (CPU EP) on the golden inputs; compare against the golden outputs.

Done when ONNX Runtime matches golden to near-FP32 precision (max abs diff ≲ 1e-4 relative to output scale). If it doesn't, the bug is in the export, not the engine — fix it here. See [references/conversion-pitfalls.md](references/conversion-pitfalls.md).

## 4. Unsupported-op triage

Parse the model with the target engine and list every layer it can't run or runs off the accelerator (TensorRT parser errors / plugin requirements; TFLite ops not delegated, delegate partition count; DLA layers falling back to GPU).

Fix in this order — earlier options are cheaper to maintain:

1. Rewrite in the model source with an export-friendly equivalent, re-export.
2. Move it out of the model into pre/post-processing (typical: NMS, decode, argmax over large maps).
3. Graph surgery on the ONNX (`onnx-graphsurgeon`).
4. Use a built-in plugin (e.g. TensorRT `EfficientNMS`).
5. Custom plugin — last resort; it becomes code you own on every platform.

Done when every op runs on the intended accelerator, or each fallback is listed with its measured cost and accepted by the user.

## 5. Build the engine

- TensorRT: `trtexec --onnx=… --saveEngine=…` (add `--fp16` here if the budget needs it; INT8 is the `quantization` skill). Dynamic shapes need `--minShapes/--optShapes/--maxShapes` — set the opt shape to the shape production actually runs. Workspace via `--memPoolSize`. Keep a timing cache.
- **Build on the target, with the target's TensorRT version.** Engines are not portable across GPU architectures or TensorRT versions.
- TFLite: converter options + the delegate the product will use.
- Record the exact build command in a script in the repo.

Done when the engine is reproducible from the script alone.

## 6. Engine parity

Run the engine on the golden inputs **through the production preprocessing code**, not the Python preprocessing from step 2.

- Per output: max abs, mean abs, cosine similarity. Tolerance decided up front — FP32 ≈ ONNX Runtime; FP16 typically 1e-3–1e-2 relative.
- Task metric on the validation subset vs step 2.
- When it diverges: first diff the preprocessed input tensors (app vs golden) — most mismatches are there. Then localize inside the network with `polygraphy run model.onnx --trt --onnxrt --trt-outputs mark all --onnx-outputs mark all`.

Done when per-output diffs are inside tolerance **and** the task metric drop is within the allowed drop.

## 7. Benchmark on target

- `trtexec` / `benchmark_model` numbers are the engine alone. The budget is **end-to-end**: capture/decode → preprocess → copy → infer → post-process → result. Measure that in the app.
- Fix the power state and record it (Jetson: `nvpmodel` mode, `jetson_clocks`). Warm up, then report p50/p99/max over enough frames; record memory and power (`tegrastats`).
- Paired A/B only — run variants interleaved within minutes; DVFS and thermals make cross-session numbers incomparable.

Find the bottleneck before optimizing: an Nsight Systems (`nsys`) timeline for the whole loop, `trtexec --dumpProfile --separateProfileRun` for per-layer time. Gaps between kernels on the GPU row mean the GPU is waiting on CPU launches.

If over budget, in rough order of payoff: FP16/INT8 (`quantization` skill) → smaller input resolution (accuracy check!) → zero-copy input, fused GPU preprocessing, post-processing on device → detect-sparse/track-dense and ROI inference → CUDA Graph, pipelining, DLA offload, sparsity → kernel work (`gpu-kernel-engineering` skill). Details, the CUDA Graph recipe and its constraints, and the Jetson system settings are in [references/runtime-optimization.md](references/runtime-optimization.md) — read it before proposing optimizations.

Follow the `edge-benchmark` skill for the protocol and what to record with each number.

Done when a table of stage latencies (p50/p99), memory, and power exists in the notes, compared to the budget.

## 8. Hand-off

Deliver: the engine-build script, the parity script with tolerances, the benchmark command, pinned versions (framework, opset, engine, JetPack/BSP), and a short note on what was **not** verified (scenes not covered, live vs offline, other targets). Follow the repo's commit rules.
