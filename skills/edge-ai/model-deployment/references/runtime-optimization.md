# Runtime optimization — when the engine works but misses the budget

Measure first (section 5), then work top-down: the model layer usually pays most, CUDA Graph and friends are fine-tuning once the big wins are in.

## 1. Model layer

- **Precision**: FP16 → INT8 (the `quantization` skill). Keep sensitive layers (first conv, heads) in FP16 with per-layer precision constraints.
- **Input resolution** is often the cheapest lever: 640 → 512 cuts ~36% of conv FLOPs. Re-check the task metric.
- **2:4 structured sparsity** (Ampere/Orin tensor cores): prune to the 2-of-4 pattern, fine-tune, build with `--sparsity=enable`. Pays on large conv/GEMM layers only.
- Distillation or a lighter architecture; avoid ops the engine handles poorly (custom ops, Reshape/Transpose chains).
- Clean the ONNX: `onnxsim`, `onnx-graphsurgeon`; replace hand-rolled NMS with `EfficientNMS_TRT`.

## 2. Engine build

- Static shapes where possible. With dynamic shapes, set the **opt shape to the shape production actually runs** — tactics are tuned for it.
- `--builderOptimizationLevel` (0–5; default 3): higher builds slower and may find faster tactics.
- `--timingCacheFile`: faster rebuilds and more stable tactic choice between builds.
- Give the builder enough workspace (`--memPoolSize=workspace:…`) or fast tactics get skipped.
- **DLA** (Jetson Xavier/Orin): `--useDLACore=0 --allowGPUFallback`. Power-efficient for INT8/FP16 conv nets and frees the GPU for other work. **Read the build log** for how many layers actually landed on DLA — every DLA↔GPU switch costs a reformat, and a mostly-fallback model is slower than GPU-only.

## 3. Runtime pipeline

- **Preallocate everything**; no allocation per frame. For small outputs on Jetson, mapped pinned memory (`cudaHostAlloc(..., cudaHostAllocMapped)`) lets the CPU read without a memcpy.
- **Fuse preprocessing** into one kernel (resize + color convert + normalize + HWC→CHW): each pixel read once. Feed it from zero-copy decoder buffers (NVMM) when the source is a video pipeline (the `gstreamer-pipeline` skill).
- **Post-processing on the GPU**: decode + NMS on device, copy back only the final boxes.
- **Streams and events** for independent work (two cameras, two models): `cudaEventRecord` / `cudaStreamWaitEvent`, never `cudaDeviceSynchronize` in the loop.
- **Pipelining** stages (capture / pre / infer / post) on threads raises throughput but can **raise capture-to-result latency**. For closed control loops (robotics, actuators, tracking) latency wins: queue depth 1–2, drop old frames instead of queueing.
- **Detect sparse, track dense**: run the detector every N frames and a light tracker (KCF, optical flow, Kalman) in between; optionally run the model only on an ROI crop around the target. Often beats any kernel-level work.
- **Batch** multiple cameras or crops into one inference call.
- **CUDA Graph** — section 4.

## 4. CUDA Graph with TensorRT

Two different "graphs":

| | Computation graph | CUDA Graph |
|---|---|---|
| Layer | Model / TensorRT builder | CUDA runtime / driver |
| Nodes | Network ops (Conv, ReLU…) | Kernel launches, memcpys |
| When | Engine build (offline) | Capture once, replay each frame |
| Optimizes | GPU work (fusion, tactics, precision) | CPU launch overhead |
| TensorRT does it? | Yes, always | **No — you capture it yourself** |

`enqueueV3` still launches every kernel of the engine one by one from the CPU (hundreds, a few µs each). A CUDA Graph records the sequence once and replays it with one `cudaGraphLaunch`.

```cpp
context->setTensorAddress("input",  d_input);   // fixed addresses
context->setTensorAddress("output", d_output);

context->enqueueV3(stream);                     // one run first: flushes TRT's deferred setup
cudaStreamSynchronize(stream);

cudaGraph_t graph; cudaGraphExec_t exec;
cudaStreamBeginCapture(stream, cudaStreamCaptureModeGlobal);
preprocess<<<…, stream>>>(…);                    // own kernels can join the graph
context->enqueueV3(stream);
postprocess<<<…, stream>>>(…);
cudaStreamEndCapture(stream, &graph);
cudaGraphInstantiate(&exec, graph, 0);

// per frame: write new data into d_input, then
cudaGraphLaunch(exec, stream);
```

Constraints:
- **Buffer addresses are frozen** (kernel arguments are baked by value). Write each frame into the same buffer; a rotating ring-buffer pointer silently freezes on the first slot.
- **Shapes are frozen.** A new input shape needs a re-capture (or one graph per profile/shape), and one `enqueueV3` before capturing.
- Some engines can't be captured: data-dependent output shapes (NonZero, some NMS plugins), loops/conditionals. Capture fails with an error — fall back to plain `enqueueV3`.

Try before coding: `trtexec --loadEngine=model.engine --useCudaGraph` vs without. ONNX Runtime TensorRT EP: `trt_cuda_graph_enable`.

Worth it when: batch 1, small/many-short-kernel models (light detectors, trackers), per-frame realtime, weak CPU (Jetson) — lower latency **and** lower jitter. Little gain when kernels are long (GPU-bound). Signature in Nsight Systems: **gaps between kernels on the GPU row** = GPU waiting for CPU launches.

## 5. Jetson system

- `nvpmodel` (MAXN or the product's real mode — record it) + `jetson_clocks` to pin CPU/GPU/EMC clocks while measuring.
- Thermals: throttling silently drops FPS after minutes; watch `tegrastats` through a long run.
- Pin heavy threads to cores; give a control thread `SCHED_FIFO` so inference doesn't preempt it.
- RAM is shared with the GPU: drop the desktop (`systemctl set-default multi-user.target`), avoid swap.

## 6. Measure (before any of the above)

- **Nsight Systems** (`nsys`): CPU+GPU timeline — waits, redundant copies, launch gaps.
- `trtexec --dumpProfile --separateProfileRun`: per-layer time inside the engine.
- `tegrastats`: GPU load, EMC (memory bandwidth), temperature.
- Report **p99**, not just the mean — for realtime control, jitter matters as much as speed.

Suggested order: Release build + pinned clocks + Nsight to find the bottleneck → INT8 (QAT if PTQ loses accuracy), lower resolution → zero-copy, fused preprocessing, GPU post-processing → detect-sparse/track-dense, ROI → CUDA Graph, pipelining, DLA, sparsity.
