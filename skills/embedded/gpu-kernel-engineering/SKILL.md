---
name: gpu-kernel-engineering
description: Everything CUDA/OpenCL (desktop NVIDIA, Jetson, mobile Adreno/Mali) — kernels and the host code around them: bring-up, honest measurement, optimization ladder, safe kernel changes, numerics, CUDA/OpenCL parity, RAII buffers/streams, error checks, CUDA CMake. Use when writing, porting, reviewing, or speeding up GPU code, or a frame is over its GPU budget.
---

# GPU kernel engineering playbook

Rules distilled from real-time image pipelines shipped on mobile and
embedded GPUs. Hardware differs: every "usually" below is a starting
hypothesis, **measured on the target before it is believed**. The numbers
quoted are orders of magnitude, not targets.

Before optimizing anything, read `references/optimization-catalog.md`: every
technique with its typical effect, the dead ends, and the measurement traps.

Host-side code (device buffers, streams, events, error-check macros, transfers,
build flags, CMake for CUDA, GPU review checklist) follows
`references/host-code.md` -- read it before writing or reviewing any code that
calls the CUDA or OpenCL API.

## 1. Bringing up a GPU project -- set up before optimizing

Do these first, in order. Every later decision depends on them.

1. **Inventory the target.** GPU/SoC, driver, API version, wavefront/warp
   width (`CL_KERNEL_PREFERRED_WORK_GROUP_SIZE_MULTIPLE`; warp 32 on NVIDIA),
   local/shared memory per group, unified vs discrete memory, clock governor
   and thermal limits. Where does code build and run -- locally, or only on a
   remote board you reach over ssh?
2. **Find the cost metric the owner actually cares about** (GPU busy %, ms
   per frame, fps, power) and how to read it (sysfs counter, profiler, events).
   Write down its resolution and noise.
3. **Build a stage bench**: one stage on recorded input held in memory, many
   repetitions, median/percentiles, nothing written to disk. It must report
   both per-stage GPU time (events/queue timestamps) and back-to-back
   throughput with a single drain.
4. **Build a diff harness**: run the pipeline offline on fixed datasets and
   compare two output dirs (mean, max, pixels over a threshold, where).
   Measure the **noise floor** by running the same binary twice -- GPU
   pipelines with float atomics are not bit-identical run to run.
5. **Collect datasets that stress it**: typical input, both signal extremes
   (brightest/darkest, saturated), high contrast, motion, plus the reference
   product's own output for the same input when one exists.
6. **Start a notes file** in the repo: what was measured, what was tried and
   failed, with numbers. Consider a project-specific companion skill for the
   board, datasets, commands, and config plumbing.

## 2. Measuring -- most wrong conclusions start here

- **Only paired A/B, interleaved, within minutes.** DVFS and thermal
  throttling make absolute numbers from different runs incomparable (the same
  build can measure >1.5x apart in GPU busy on different days). Run A, B, A, B;
  9-12 samples per arm; report ranges and require them not to overlap.
- Pin the clock floor when the platform allows it and restore it afterwards;
  record the clock. Board-wide settings (GPU clock, power policy) must be
  restored on exit; process-local CPU affinity to one cluster cuts jitter
  and needs no restore. Let the board cool. Discard warm-up samples.
- **Wall time around a full drain** (`clFinish`, `cudaStreamSynchronize`)
  has a large floor (near a millisecond on mobile GPUs) -- it cannot resolve a
  0.15 ms win. Use event profiling or a back-to-back batch.
- A sub-profiler must drain the queue *before* starting its clock, or it
  bills earlier stages' backlog to its first kernel.
- Check a paced run is actually paced (achieved fps by wall clock).
- Measure the path production actually runs (output format, kernel variant
  selected by the shipped parameters), not a convenient neighbour.
- When a perf number depends on a config flag, **grep the committed
  production config** for it. A win measured with a scratch config can
  silently never ship.
- Convert to the owner's unit: at 60 fps, 1 ms = 6% of a frame.
- Don't convert a wall-clock stage delta into a GPU-busy delta by dividing by the
  frame period -- that only holds for pure shader work.
- Point-sampled utilization counters: log the clock next to the load; spikes
  without a clock drop are sampling artifacts. Never quote the max.
- Profiling code must cover the production output path too -- accounting that
  lives only in the test path prints nothing for the path that ships.

## 3. Cost model -- what actually costs time

Most image/vision kernels are **memory-bound**: cost ≈ bytes moved, not
FLOPs. Estimate loads and stores per output before touching arithmetic.

- A full-resolution float buffer written by one kernel and read by the next
  is a real round trip (on the order of 0.1-1 ms per full-frame float pass on
  a mobile GPU, depending on resolution).
- Launch overhead (tens of µs per kernel on mobile GPUs, a few µs on desktop
  CUDA) only matters in bulk.
- A host readback on an in-order queue is a **barrier on everything queued
  before it**, and the GPU idles while the host computes on the result.
- Global atomics contend; atomics that add 0 still cost.
- Serial work inside a group (one lane scanning while the rest idle) and
  outputs nobody reads are pure waste and easy to miss.
- Inside a kernel, a mobile GPU can be bound by the **number of local-memory
  reads**, not by ALU or global bandwidth. Probe: keep the math, cut the
  loads, see if time moves.

## 4. Optimization ladder -- try in this order

0. **Host-side stalls and CPU pixel loops**: blocking readbacks, syncs that
   only feed debug output, CPU conversions, the CUDA legacy default stream.
   Low GPU busy with low fps means CPU- or sync-bound; kernel work won't help.
1. **Work proportional to nothing**: serial reductions → tree/parallel
   reductions; dead outputs; per-frame scalars recomputed per pixel; atomics
   adding zero; optional inputs computed when no consumer is enabled.
2. **Full-resolution round trips**: fuse a same-index producer/consumer;
   compute small terms inline in the pass that already touches the pixel;
   write results straight into their final slot. Fusion pays when it removes
   a full-res buffer, not merely a launch.
3. **Resolution of low-frequency work**: large blurs (sigma ≳ 3) at half
   resolution; statistics on a stride grid (scale absolute thresholds by
   1/stride²); reuse downsampled copies another stage already made.
4. **Skip by weight**: branch out before neighbour reads where a term's
   weight is 0.
5. **Keep scalars on the device** (curves, percentiles, thresholds); chain
   kernels through device buffers, not host arguments; refresh slow
   statistics every N frames with staggered phases.
6. **Only then in-kernel work**, measured. The question is "how many loads
   does each output cost?", not "how sophisticated is the code?".
   - Local-memory tiling and vector loads pay when they **cut loads**
     (tile-fusing a chain with a halo, scattered gathers, row-sweep reuse in
     block matching) and lose when the cache already serves the reuse or
     they only replace scalar math.
   - Usually no gain on mobile GPUs: fast-math intrinsics on memory-bound
     kernels (and they shift outputs), bank-conflict padding, small
     fusions, CUDA graphs for a handful of launches.
   - Always fatal: private arrays indexed by a computed index (spill to
     memory -- many times slower).
   - On NVIDIA: coalescing (adjacent lanes = adjacent x), occupancy, and a
     launch config per kernel matter more; read `ncu` stall reasons (Long
     Scoreboard = global latency, Barrier/MIO = shared memory) to choose.

After each big win, re-probe what bounds the kernel: once the limiter moves
(e.g. from local-memory reads to fixed overhead), techniques aimed at the old
limiter stop paying.

## 5. Writing a kernel change safely

- **New behaviour behind a flag whose default is bit-exact** with the old
  output. Prove it (max diff 0), then measure the on-path change separately.
- Plumb every config key through **every layer** (struct, parser, backend,
  bench, profiles, docs). A missed layer = the key silently does nothing.
  Find an existing sibling key and mirror all its sites; benches that copy
  fields by hand are the usual miss.
- Host argument order must match the kernel signature; inserting an argument
  shifts every later index. Bind fixed arguments once at init.
- Kernel binary caches (cached `.bin`, embedded sources, CUDA's compute
  cache) can be stale after a signature change -- some drivers segfault in
  set-arg instead of erroring. Rebuild, delete caches.
- Reuse what exists: buffers another stage computed, kernels from another
  module via a second program/compile unit instead of copy-paste.
- Group sizes in multiples of the wavefront; every thread must reach every
  barrier; a kernel must not write a buffer that neighbouring threads still
  read (stencils), so ping-pong buffers when fusing.
- Guard divisions, `log`, `pow` of possibly-zero inputs; clamp LUT and
  histogram indices.
- Write the ordering invariant into the kernel when correctness depends on
  queue order (e.g. "reads last frame's value before stage X overwrites it").

## 6. Numerics and determinism

- Host code ported from double to float drifts slightly; decide the
  tolerance up front and compare against the noise floor.
- Float accumulation order changes results; float atomics are
  non-deterministic. Integer atomics (histograms) are exact. To stay
  bit-exact while vectorizing, keep the scalar accumulation order.
- fp16 can flip argmin ties (49² → 2400, 53² → 2808) and overflow on large
  raw values; keep costs in fp32 unless the reference intentionally doesn't.
- Local variance as E[x²] − m² in fp32 loses small variances on large raw
  values (16-bit sensor data around 30000): subtract a local value (the
  centre pixel or the window mean) first, then square.
- Border modes differ (clamp vs reflect101); match the reference or document it.
- Truncation vs rounding, `floor` of negatives, LUT index at the top end --
  check the extremes.
- Tie-breaks in parallel argmin: compare (cost, index) lexicographically so
  "first occurrence wins" survives the reduction, including across warps.

## 7. CUDA ↔ OpenCL parity

- One written spec of the math per stage; both backends implement it.
- Diff both backends on the same input; expected differences are listed,
  everything else is a bug. Usual suspects: fp16 vs fp32, borders,
  rounding, reduction order, edge-site handling, a feature ported without
  its enable gate.
- A feature that lands in one backend only says so in the commit and docs.
- Parity goes stale: re-diff the current sources and configs of both backends
  before claiming parity, not a note from an earlier parity pass.
- Porting a fix: don't copy the source backend's own bugs (e.g. a
  non-coalesced pass).
- CUDA graphs bake kernel arguments by value: a rotating ring-buffer pointer
  freezes. Pass a stable device address whose contents are refreshed. (Capturing
  a TensorRT engine plus pre/post kernels into one graph: see the
  `model-deployment` skill's runtime-optimization reference.)

## 8. Image-processing pitfalls (tone mapping, sharpening, denoise)

- **Order matters**: detail added after a compressive tone curve is
  compressed with it. Add detail before the curve, in the linear/raw domain,
  scaled by the local gain (as a base/detail decomposition does).
- Near saturation, positive detail only widens the clipped area; correct
  asymmetrically (darken-only) there.
- Weighting by a pixel's own histogram bin draws outlines at edges (edge
  pixels sit in empty bins); weight by the steeper of pixel and surround.
- Edge-preserving base filters (guided, bilateral) keep small strong
  structures in the base, so where the curve is flat they lose contrast. A
  box computed at half resolution has twice the window it appears to.
- Detail-weighted histograms can starve large low-detail regions (foliage,
  sky) and darken the frame; normalise and blend with the plain count.
- Check halos around **both** a bright and a dark object, noise in flat
  regions, and compare with the reference image (percentiles, a detail
  metric such as mean |x − G1.5(x)|, 4-5x crops).
- Statistical/learned predictors inside a pipeline (regressions mapping frame
  statistics to targets) extrapolate without bound on out-of-distribution
  input (a very hot or saturated source) and can collapse the whole output.
  Bound the input features, tie predictions to the output range they must
  fit, and choose guard strength from a measured table (gain on the extreme
  case vs drift on normal frames). Weights fitted on one sensor may be
  permanently out of distribution on another -- re-measure the envelope.
- A stage can be doing invisible work for another (denoise suppressing
  fixed-pattern noise that motion estimation relies on); check consumers
  before disabling or replacing it.

## 9. Working with the owner

- Propose options with a recommendation, expected cost and risk; code after
  a yes. A budget the owner sets is a ceiling, not a target.
- Report what changed, the off-switch proof, the on-path diff, the paired
  cost, and what was **not** verified (offline vs live, scenes not tried).
- Hand over a command they can run on the target; follow the project's
  commit rules.
- Log dead ends with numbers in the notes file so nobody retries them blind.
