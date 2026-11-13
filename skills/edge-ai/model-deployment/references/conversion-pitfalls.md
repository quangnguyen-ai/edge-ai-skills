# Conversion pitfalls

Each is a known way a converted model silently differs from, or refuses to build like, the original. Check the relevant ones when parity fails.

## Preprocessing (check these first)

- RGB vs BGR (OpenCV decodes BGR; most training pipelines are RGB).
- Normalization applied twice, or not at all, because it moved into/out of the model.
- `/255` vs mean/std vs both.
- Resize interpolation differs (PIL bilinear with antialias ≠ OpenCV `INTER_LINEAR`), letterbox vs stretch, padding value, rounding of the scaled size.
- NCHW vs NHWC, or a contiguous-copy missing so the engine reads strided memory.
- uint8 → float conversion done after resize vs before.

## Export

- Model not in eval mode: dropout active, BatchNorm using batch statistics.
- Data-dependent Python control flow is traced for one path only; the exported graph ignores the other branch.
- `Resize`/`Upsample` with `align_corners` or `coordinate_transformation_mode` mismatched between framework and exporter.
- Dynamic shapes exported where not needed: `Shape → Gather → Concat` chains that engines handle badly. Fix shapes, or run `onnxsim`.
- int64 tensors: TensorRT casts to int32; huge index values overflow.
- In-place ops and Python-side tensor indexing producing `ScatterND` that some engines don't support or run slowly.
- Opset too new for the target engine version, or too old for an op (e.g. `GridSample` only from opset 16).

## Engine

- Engine built on one GPU/TensorRT version and run on another — undefined, often a load failure, sometimes wrong results.
- FP16 overflow: unnormalized inputs, large activations, softmax/LayerNorm/attention with big logits. Keep those layers FP32.
- Layers silently falling back from DLA to GPU, inserting reformat layers that cost more than they save. Check the layer info (`trtexec --exportLayerInfo` with `--profilingVerbosity=detailed`).
- Output binding order assumed instead of looked up by name.
- TFLite: ops not supported by the delegate split the graph into partitions with a CPU round trip between each.

## Post-processing

- Decode written for one output layout (e.g. anchors-last) but the exported model uses another.
- NMS thresholds or class-agnostic setting differ between the training repo's eval and the app.
- Sigmoid applied twice (once in the model, once in post-processing).
