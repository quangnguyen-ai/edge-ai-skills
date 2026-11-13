# ARM CPU inference (Linux aarch64) — field notes

**Last reviewed**: 2026-10-14 · **Context**: ONNX Runtime CPU EP and LiteRT (TFLite) on an 8-core aarch64 SoC with three clusters (little / mid / one prime core), Ubuntu, background load present.

Only non-obvious lessons are kept here; measurements stay with the project that produced them. Labels: **[measured]** observed on a real device; **[assumption]** not verified.

- **Thread count = cores in the fastest homogeneous cluster, not `nproc`.** Using every core was slower than using only the fast cluster — for a detector, as slow as a single thread. **[measured]**
- **Little cores are several times slower**; an inference thread pinned or scheduled there dominates the frame time. **[measured]**
- **Don't mix core types in one thread pool.** Adding the single fastest core to the mid-cluster pool made it slower, not faster — the pool waits for its slowest worker. **[measured]**
- **Pinning to the fast cluster mostly tightens the tail (p99)**; the median barely moves. Worth it for real-time loops. **[measured]**
- **Quantized is not automatically faster on a CPU.** An old asymmetric-uint8 TFLite model ran slower than its float version at every thread count. **[measured]** Cause **[assumption]**: it misses the runtime's fast int8 kernels; per-channel symmetric int8 is expected to behave differently — measure it.
- **A 640-px detector on the CPU is far from real time**, while the same model on the SoC's DSP/NPU is real time — the CPU is a fallback, not a target, for such models. **[measured]**
- **Under background load, results drift between runs minutes apart** — compare configurations only inside one interleaved run. **[measured]**

## Not yet verified

- Per-channel int8 TFLite / ORT QDQ models on this CPU.
- TFLite GPU or NPU delegates on this SoC.
- PyTorch → TFLite conversion paths (`ai-edge-torch`, ONNX → TF).
- Behaviour with background services stopped.
