# ARM CPU targets (Linux aarch64) — checklist

Lessons and caveats behind these rules: [../../../../docs/knowledge/arm-cpu-inference.md](../../../../docs/knowledge/arm-cpu-inference.md).

1. **Map the clusters first**: `cat /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq` — group cores by max frequency. Note what else runs on the device (`ps -eo pcpu,comm --sort=-pcpu | head`).
2. **Threads = cores in the fastest homogeneous cluster** (e.g. 4), not `nproc`. Never let a thread pool span little cores or mix core types; test N and N±1 to confirm.
3. **Pin the inference process to that cluster** (`taskset -c <cores>` or `sched_setaffinity` in the app) — it mainly tightens p99, which is what a real-time loop feels.
4. **Measure float and quantized side by side** before choosing: a quantized model can be slower on CPU if its scheme doesn't hit the runtime's fast int8 kernels. Prefer per-channel symmetric int8 (TFLite full-integer, ORT QDQ) and verify the speedup.
5. **Runtimes to compare**: LiteRT/TFLite (default CPU path) and ONNX Runtime CPU EP, same model, same input, same threads and pinning — `scripts/bench_cpu.py <ort|tfl> <model> <threads> <runs>` reports load time, first-run and steady-state p50/p99.
6. **Budget check early**: if a CPU run is an order of magnitude over the frame budget, stop tuning threads — move to the SoC accelerator (GPU/NPU/DSP) or shrink the input.
7. **Record** only a new non-obvious lesson in the knowledge file (date + evidence label, no numbers); the measurements themselves go in the project's own report.
