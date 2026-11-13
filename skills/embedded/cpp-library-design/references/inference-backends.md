# Inference-library specifics

Applies when the backends are inference engines (TensorRT, QNN, SNPE, TFLite, ONNX Runtime).

- **Stages per task**: preprocess → infer → postprocess. Preprocessors and postprocessors are per model family (YOLO-style detection, SR, pose…), composed from shared utils (letterbox, normalize, decode, NMS).
- **Backend interface**: load model, bind I/O **by tensor name**, infer, and query shapes, layouts, dtypes, and **quantization params** (scale/zero-point on INT8 NPUs) — pre/post adapt to these instead of hard-coding them per backend.
- **GPU pre/post** (CUDA kernels for a TensorRT backend) implements the same pre/post interfaces as the CPU versions; the task picks by backend or config.
- **Model file per backend** (`.plan`/`.engine`, `.dlc`, QNN `.so`/context binary, `.tflite`, `.onnx`) — one config per model × backend, with the export/convert command recorded next to it.
- File-extension auto-detection is ambiguous (`.so`, `.engine` vs `.plan` vs `.trt`); config `backend` field wins.
- `warmup()` matters most here: engine deserialization, graph finalization, and first-run allocations land on the first inference.
- Result type: a variant over task data (detections, SR image, tracks, keypoints) plus error code, message, and per-stage timing.
- Parity of a new backend: the `model-deployment` skill (golden inputs, tolerances). Benchmark rows: the `edge-benchmark` skill (timing + mAP / PSNR/SSIM with identical eval settings).
- Scope trap: multi-model chains (SR → detection, detection → pose, detect + track) feel like library features; keep them in the application or a separate thin "pipeline" layer above the engine, so the engine stays one-model.
