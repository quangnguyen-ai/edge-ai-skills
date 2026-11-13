---
name: quantization
description: Make a model smaller and faster for edge inference with FP16/INT8 quantization or pruning while holding accuracy — PTQ calibration, QAT, mixed precision, layer sensitivity analysis, accuracy gating. Use when the user wants to quantize, calibrate, go INT8/FP16, prune, or sparsify a model, or asks why a quantized model lost accuracy or didn't get faster.
---

# Quantization and pruning

Two numbers decide everything: the **task metric** on a held-out eval set and the **end-to-end latency** on the target. Output MSE is a debugging aid, not a verdict. A precision change that doesn't move both numbers in the right direction is reverted.

## 0. Preconditions

- A working FP32 deployment with passing parity — if there isn't one, run the `model-deployment` skill first. Quantizing a model whose export is already wrong makes both bugs impossible to separate.
- The eval set and task metric, and the **allowed accuracy drop**, agreed with the model owner (e.g. ≤1 point mAP absolute).
- FP32 baseline latency on target, measured the way `model-deployment` step 7 describes.

Done when all three are written in the notes file.

## 1. FP16 first

On GPUs and most NPUs, FP16 is close to free in accuracy and often most of the speedup. Build FP16, run parity and the task metric.

- If it overflows (inf/NaN, or a collapse in one output): find the layers (unnormalized inputs, large activations, softmax/LayerNorm/attention) and pin them to FP32.

Done when FP16 latency and metric are in the table. **If FP16 meets the budget, stop here** — INT8 adds calibration data, a maintenance burden, and accuracy risk.

## 2. Post-training quantization (INT8)

- Prefer **explicit quantization**: Q/DQ nodes in the ONNX (e.g. NVIDIA TensorRT Model Optimizer, or `pytorch-quantization` on older stacks). Recent TensorRT versions deprecate implicit, calibrator-based INT8. TFLite: full-integer conversion with a `representative_dataset`. Qualcomm: `qairt-quantizer` with calibration raws produced by the *exact* deployment preprocessing and layout, per-channel weights on; it calibrates on the CPU at roughly 0.5 s/image, so 1000 images takes minutes — slow, not hung (measured on a QAIRT 2.36 host). Options there are W8A8 (fastest) or W8A16 (activations kept 16-bit when W8A8 loses too much). Device specifics: `model-deployment` → `references/qualcomm.md`.
- **Calibration set**: a few hundred to ~1000 inputs sampled from the **deployment distribution** (cameras, times of day, scenes), passed through the **production preprocessing**. Not the eval set. Not augmented training images.
- Weights per-channel, activations per-tensor (the usual default). Try both entropy/percentile and max calibration if the first is poor.

Done when the INT8 build's metric and latency are in the table next to FP32 and FP16.

## 3. Check it actually got faster

INT8 that isn't faster usually means layers still run in higher precision, or reformat layers were inserted between INT8 and FP16/FP32 regions. Export per-layer info (`trtexec --profilingVerbosity=detailed --exportLayerInfo=… --exportProfile=…`), find the layers not running INT8 and the reformats, and fix the boundaries (move Q/DQ placement, keep whole blocks in one precision).

Done when the per-layer profile explains the end-to-end number.

## 4. Recover accuracy

If the drop is over the allowed drop, in this order:

1. **Sensitivity analysis** — quantize one layer/block at a time (or un-quantize one at a time) and rank by metric impact. The usual suspects are the first conv, the detection/regression heads, and attention/softmax.
2. **Mixed precision** — keep the top few sensitive layers in FP16. Re-check latency: each precision boundary costs a reformat.
3. Better calibration — more diverse data, a percentile method.
4. **QAT** — fine-tune with fake quantization from the PTQ starting point, low learning rate, a few epochs; export with Q/DQ. Needs the training pipeline and owner's buy-in.

Done when the metric is within the allowed drop, or the table shows the best achievable trade-offs for the user to choose from.

## 5. Pruning (only if quantization isn't enough)

- **Structured** (channel/filter) pruning shrinks real tensor shapes and speeds up any backend. Fine-tune after.
- Unstructured sparsity gives no speedup on GPUs, with one exception: **2:4 structured sparsity** on Ampere-class and newer (including Jetson Orin) via TensorRT's sparsity flag — and only on layers large enough to benefit.
- Prune → fine-tune → re-quantize → re-measure. No measured gain, no pruning.

## 6. Gate and record

- Final table: precision/config × latency (p50/p99) × task metric × model size × memory.
- Add a regression check that fails if the deployed configuration's metric drops below the agreed threshold.
- Store the calibration set (or its manifest) and the exact build commands, so the INT8 engine can be rebuilt bit-for-bit when the engine version changes.

Notes on accelerators: DLA (Jetson) runs only FP16/INT8 and a subset of layers; unsupported layers fall back to GPU at a reformat cost. NPUs on other SoCs usually need vendor tooling and often support only INT8 — the same calibration-set and gating rules apply.
