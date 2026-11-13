---
name: edge-benchmark
description: Benchmark models and vision pipelines on edge devices with trustworthy, reproducible numbers — timing protocol, accuracy metrics, device/SDK records, comparisons, report layout — and guard them with accuracy/latency regression tests in CI. Use when the user wants to benchmark, compare backends, devices, or models, set up regression or accuracy tests, or write or review a benchmark report.
---

# Edge benchmarking

A number without its conditions is noise: device, power mode and clocks, SDK versions, input, precision, and **what was inside the timer**. Every result this skill produces carries all of them and can be regenerated from one command plus one config.

If a target is remote-only (`docs/agents/execution-environment.md`), write the commands for the user and work from pasted output.

## 1. Name the question

Each needs a different protocol — pick one per run:

- **Latency** for a realtime loop → single stream, batch 1, p99 and max matter.
- **Throughput** → pipelined, sustained; measured frames/s, not 1000 / latency.
- **Accuracy vs speed** across variants (size, precision, input resolution).
- **Before/after** a code change → paired A/B (see the `gpu-kernel-engineering` skill's measuring rules).
- **Backend vs backend** or **device vs device** → identical model, input size, and eval settings.

Done when the question and the decision it feeds are written at the top of the report.

## 2. Define the timer

- Per stage: preprocess, inference, postprocess, plus total. State whether host↔device copies are inside "inference".
- End-to-end (frame in → result out) for budgets; a **stage bench** (one stage, recorded input in memory, back-to-back, one drain) for optimisation work. Never compare one with the other.
- FPS = 1000 / latency is only true for a serial single stream — label it as such, or measure throughput directly.

## 3. Protocol

- Warm-up iterations excluded (lazy engine init, JIT kernel compile, caches).
- Enough timed iterations for stable tails; report mean, std, min, median, p95, p99, max.
- **Fixed power state**: power mode and clocks pinned and recorded, restored afterwards. A default governor alone can move stage times well over 1.5×.
- CPU affinity recorded if set (it reduces jitter on big.LITTLE SoCs). On CPU inference, report the thread count and the exact core set; never benchmark with threads spread over little cores (see `model-deployment` → `references/arm-cpu.md`).
- **No other clients on the accelerator**: stop services that hold the camera or GPU; for comparisons, run from recorded input, not a live camera.
- Thermals: short runs for A/B; sustained runs (minutes) when reporting throughput or power, with temperature logged.
- Power: say how it was measured — wall meter vs on-board rail sensors are not comparable.
- **Shared devices**: if production services keep running (with the user's OK), label numbers as shared-load and repeat runs — single runs pick up transient contention. A run with an outlier gets re-run before it is reported.
- Long runs write outputs to tmpfs (`/dev/shm`) to spare flash; measure I/O time separately either way.

**Jetson GPU utilization**: use `tegrastats` (`GR3D_FREQ`), not `nvidia-smi`. Its log has 1-second timestamps even at 20 ms sampling — interpolate each sample's position within its second by order, rather than assuming the nominal interval (it drifts). To get GPU % for the processing phase only, log per-frame wall-clock timestamps and bucket samples into processing vs I/O windows; a whole-run average is diluted by I/O dead time. Write timestamps as **integer milliseconds** — a `double` epoch printed with default stream precision keeps 6 significant digits (hours of resolution).

## 4. Accuracy

- Same eval set and settings across every row: input size, letterbox vs stretch, confidence threshold, NMS IoU, max detections.
- Detection: mAP@0.50, mAP@0.50:0.95 (and @0.75 if useful), precision, recall. SR/enhancement: PSNR and SSIM, stating the colour channel and border crop.
- Image pipelines without ground truth: compare to a reference output. Measure the **run-to-run noise band first** (GPU reductions with float atomics are not deterministic); a change inside that band is neutral. Structural refactors should be bit-exact — compare output hashes frame by frame.

## 5. Record with every result

Device and SoC, OS/BSP version, SDK versions (TensorRT/JetPack, QNN/SNPE, TFLite, ORT), backend and accelerator (GPU/DLA/HTP/DSP/CPU), model variant, input size, precision, config file, commit hash, exact command, date.

## 6. Report layout

- `benchmarks/README.md`: the tool, how to run it, metric definitions, a backend × platform support matrix, an index.
- One file per **task × device** holding all models for it, with the device/SDK header at the top; a `models.md` per task with variants, eval settings, and export commands.
- Before/after tables with a Note column saying what changed.
- A "not verified" line: devices, scenes, modes, or durations not covered.
- The benchmark tool itself is config-driven (model config, warm-up count, iterations, optional accuracy dataset), so a row is regenerated by re-running a committed config.

## 7. Regression tests in CI

Catches silent accuracy or latency drops caused by code, model, converter/SDK, config, or preprocessing changes. Exact CI system and hardware runners depend on the project — fit these pieces into whatever it uses.

1. **Versioned eval data, two tiers.** A *fast* tier (tens to a few hundred samples, chosen to include the hard cases) runs on every merge request; the *full* set runs nightly or before release. Pin each by a manifest (file list + content hashes, a version id) — never "whatever is in the folder".
2. **Golden outputs per model × backend × precision**, produced by a pinned reference run and stored with the commit, SDK version, config, and preprocessing that made them.
3. **Two independent checks, both must pass:**
   - *Output parity* against the golden outputs, with a tolerance per precision (FP32 tight, FP16 and INT8 looser).
   - *Task metric* (mAP, top-1, PSNR…) against the baseline, with an agreed maximum drop.
4. **Set tolerances from measurement**: run the same build several times first and set each tolerance from the measured run-to-run spread plus a margin, not from a guess. Fix seeds, preprocessing, thresholds, and input order.
5. **Where each check runs.** Host-side checks (ONNX Runtime / CPU reference) are cheap enough for every merge request. Engine-, precision-, and accelerator-specific checks need the real target — a board runner or `target.sh` (the `target-workflow` skill). Report which tier and which device actually ran.
6. **Latency in the same job**: p50/p99 from the protocol in section 3, compared as a ratio to a baseline measured on the same runner in the same job — absolute numbers from shared CI runners are not comparable across runs.
7. **Golden outputs change only on purpose.** A failing check is never fixed by regenerating the golden data automatically: a refresh goes in its own merge request with a before/after metric table and an explicit approval.
8. **Failure report**: metric, baseline, delta, tolerance, and links to the worst samples (inputs, outputs, diffs) so the cause can be seen without rerunning.

Done when both tiers exist and are pinned, each check's tolerance is backed by a recorded run-to-run measurement, a deliberate small regression makes the job fail (prove it once), and the golden-update path requires approval.

## Completion

Done when every reported number has its conditions (section 5) attached, the protocol in section 3 was followed or the deviation is stated, accuracy rows share identical eval settings, and the report says what was not verified.
