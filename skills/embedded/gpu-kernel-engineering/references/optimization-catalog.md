# GPU optimization catalog -- techniques and typical effect

From real-time image pipelines (patch-based denoise, block-matching motion
estimation, multi-frame reconstruction, histogram tone mapping, multi-scale
sharpening) on two classes of target:

- **Mobile GPU**: OpenCL, wavefront 64, unified memory.
- **Embedded NVIDIA GPU**: CUDA, a handful of SMs, unified memory.

Effects are relative and indicative -- they say which order of magnitude to
expect, not what your target will do. Re-measure every one on your hardware.
"Bit-exact" = same arithmetic and accumulation order, verified by output diff
against a same-binary-twice control.

## A. Host ↔ device: remove stalls before touching kernels

| # | Technique | Typical effect |
|---|---|---|
| A1 | **Compute per-frame statistics on the GPU; read back only a tiny result** -- a histogram, not the frame. | Milliseconds → a fraction of a millisecond. |
| A2 | **Build curves/LUTs/thresholds on the device** -- a tone curve in one work-group (each thread owns a few bins; work-group scans), an EMA in one work-item. | Stage cost roughly halved; each removed readback saves a sizeable fraction of a ms. |
| A3 | **Chain kernels through device buffers, not host scalars** -- kernel B reads A's min/max from A's output buffer. | One full-queue drain per frame removed. |
| A4 | **Don't defer a readback to hide it** when the value drives a global mapping -- one frame of lag shifts every pixel visibly. Move the computation to the device instead. Same for running statistics on a side queue (faster, but lagged). | -- |
| A5 | **Zero-copy hand-off**: the producer writes into the consumer's input slot on a shared context/queue/stream. | One H2D + D2H bounce removed. |
| A6 | **Convert on the device, download the smaller result** (float → u16 on GPU, half the bytes). | Copy time cut ~3x. |
| A7 | **No CPU pixel loops** (colour conversion, LUT mapping, nth_element over the frame). | Can be the whole bottleneck: GPU busy and fps both jump once a CPU per-pixel loop becomes a kernel. |
| A8 | **Gate debug-only work**: syncs, D2H copies, atomics feeding debug prints. | Per-frame stalls and per-pixel atomics removed. |
| A9 | **Refresh slow statistics every N frames**, per group interval with fixed phases so refreshes don't bunch; keep the value in a persistent device buffer and don't enqueue the kernel on other frames. | -- |
| A10 | CUDA: **never the legacy default stream** in a library -- it synchronizes with every stream in the process. | Large slowdown inside an integrating app. |
| A11 | **Process-local CPU affinity** to the big cores (leave the prime core free). Never write board-wide governors from a library. | Less jitter. |
| A12 | **Raise the GPU clock floor for the process and restore it** -- a paced pipeline idles and the governor settles low. Touch min_freq only. | The same kernel can run ~1.5-2x slower at a low governor clock. |

## B. Memory traffic between kernels

| # | Technique | Typical effect |
|---|---|---|
| B1 | **Fuse a same-index producer/consumer pair**; keep the intermediate in registers. Look for any full-res buffer with exactly one writer and one reader at the same index. | Usually the largest single wins: tens of percent on a stage when full-res buffers disappear. |
| B2 | **Delete dead outputs and dead computations** -- grep every reader; a feature port may compute results whose consumer is disabled. | ~10% on affected stages; megabytes per frame of writes gone. |
| B3 | **Read the previous frame's value where it still lives** instead of copying it, when queue order guarantees it isn't overwritten yet. Write the invariant into the kernel. | ~10%. |
| B4 | **Multi-output kernels over shared windows**: boxing w·a, w·b and w together reads w once; two normalizations sharing a denominator sum it once. A bitmask argument handles mixed weighted/unweighted sources. | A few percent. |
| B5 | **Write into the final slot** (plane-offset argument) instead of copying into place afterwards. | Full-res copies removed. |
| B6 | **Fold an elementwise step into the preceding pass** (vertical blur writes `x − blur` directly; apply a LUT in a register inside the next mix). | A few percent, less memory. |
| B7 | **Conditional fusion**: fuse on frames where the intermediate has no other reader (e.g. only histogrammed on refresh frames). | A few percent. |
| B8 | **Tile-fuse a short chain with a halo** (blur → gradient → combine) into one local-memory pass when each step was a full-res round trip of trivial math. Keep the blur separable inside local memory. | Several passes → 2, ~25-30%, bit-exact. |
| B9 | **A fusion that removes no full-res buffer doesn't pay** (it only saves a launch or a re-read of a small, cache-resident buffer). | Inside noise. |

## C. Work that is proportional to nothing

| # | Technique | Typical effect |
|---|---|---|
| C1 | **Serial argmin → parallel**: per-thread running min over strided candidates + log2 tree in local memory, comparing (cost, index) to keep first-occurrence ties. | ~10% on a hot kernel. |
| C2 | Serial threshold-crossing scan over bins → parallel `atomicMin`. | ~10x. |
| C3 | Percentile walk by 1-2 lanes over thousands of bins → one group: chunk sums, prefix over chunks, only the owning thread walks its chunk. | Becomes negligible. |
| C4 | **Flush a local histogram only for touched bins** (most groups touch a small fraction of bins). | ~35%. |
| C5 | **Histogram on a stride grid**; dispatch the *smaller* grid (skipping inside a full dispatch gave nothing); scale absolute clip counts by 1/stride². | ~40% of histogram cost. |
| C6 | **Per-group local histogram** (exact ints), one global atomic per nonzero bin, instead of global atomics per pixel. | Large, contention-dependent. |
| C7 | **Grid-stride reductions**: fixed group count, accumulate in registers, one local tree + one atomic per group. Not bit-exact (float reorder) -- check against the noise floor. | Reduction cost collapses. |
| C8 | **Skip neighbour reads where the term's weight is 0.** | Cost of an optional term cut several-fold. |
| C9 | **Compute only what the consumer samples** (a blur feeding a 2x decimation only needs every other column). | Part of a larger fusion win. |
| C10 | **Don't compute an optional input when no consumer is on.** | A "fast" filter can be slower than the plain one until this. |

## D. Resolution and algorithmic cost

| # | Technique | Typical effect |
|---|---|---|
| D1 | **Half-resolution large blurs**: sigma ≳ 3 has ~1.5e-5 response at the 2x-decimated Nyquist. 2x2 mean, blur at sqrt(s² − 0.25)/2, bilinear read in the consumer, no upsample pass. | ~25% on the stage; mean output diff a small fraction of a grey level. |
| D2 | **Fast guided filter**: statistics at 1/2 resolution, only the combine full-res. 1/4 tends to hurt edge quality. The effective window doubles. | ~20%. |
| D3 | **Reuse a downsampled copy another stage already made.** | One pass removed. |
| D4 | **Compose instead of re-searching**: multi-hop motion from cached single hops. | ~30%. |
| D5 | **Skip stages a mode doesn't need**; watch cost cliffs (a cost ∝ 1/scale² can make a small scale more expensive than a large one). | Stage cost → ~0 when skipped. |
| D6 | **Specialize the production parameters** (compile-time radius/stride/tile) and keep a generic fallback. | Enabler for most in-kernel wins. |
| D7 | **One launch looping all offsets** instead of one launch per offset; load the offset-independent reference tile once. | ~20%; launch count cut by orders of magnitude. |

## E. Inside the kernel (measure each)

| # | Technique | When | Typical effect |
|---|---|---|---|
| E1 | **Cut local-memory read count** -- often the limiter on mobile GPUs for patch/search kernels. | Heavy local reuse. | Up to ~3-4x. |
| E2 | **Row-sweep reuse**: shifts (dx, dx+1) read the same row one column apart; one wide row load serves all shifts; or pair shifts (one vector load + one scalar instead of two vector loads). | Block matching, non-local means. | Local reads per site cut ~5x. |
| E3 | **Vector loads over contiguous rows**, keeping the scalar accumulation order for bit-exactness. | When it reduces loads. | 2-4x on searches (with tiling). |
| E4 | **Branch-and-bound** in argmin searches (non-negative terms: stop once above the best). | SSD searches. | ~20% (A/B against a no-prune build). |
| E5 | **Tile scattered gathers** (bicubic: 16 unaligned global reads per pixel): load the footprint once, clamp at load, separable taps from local. | Poor-locality gathers. | ~20%. |
| E6 | **Reuse local arrays across disjoint lifetimes**, barrier between. | Local-memory-limited occupancy. | Smaller footprint per group → more groups resident. |
| E7 | **Drop self round trips through local memory** (store, barrier, read back own index). | Always. | Part of E1. |
| E8 | **Several independent items per group** so stalls have neighbours (CUDA: 2 per block via threadIdx.z). Sweep the count -- there is a sweet spot. | Barrier/shared-latency bound at max occupancy. | A few percent; too many is worse. |
| E9 | **Launch config per kernel**: per-block fixed cost (big shared histogram) wants big blocks; bandwidth-bound elementwise kernels want smaller blocks. | CUDA. | ~2x either way when wrong. |
| E10 | **Warp-shuffle reductions**; the cross-warp combine must respect the tie order. | CUDA. | Correctness trap: a combine that favours one warp. |
| E11 | **Coalesce the fast dimension** (adjacent lanes = adjacent x) and keep enough blocks to fill the SMs. | CUDA, column passes. | Wrong orientation several times slower. |

## F. Usually not worth it (retry only with new evidence)

- Local-memory tiling where the cache already serves the reuse (plain separable blur): null.
- A "more optimized" tiled kernel vs a simple one: often slower, on both mobile and NVIDIA.
- Vectorizing a loop without cutting loads: slower.
- Removing branch-and-bound to avoid divergence: slower.
- `native_exp/native_powr`, `-cl-fast-relaxed-math`: no gain on memory-bound kernels, outputs shifted visibly through gates and knees.
- Bank-conflict padding on mobile GPUs: no gain.
- Merging phases with local float atomics: CAS contention, orders of magnitude slower.
- Private arrays with computed indices: spilled, many times slower.
- Folding more pixels per work-item after empty-bin skipping: inside noise.
- Fused multi-blur dispatch: faster only under forced-sync profiling; identical in production (an in-order queue already pipelines).
- Sliding-window rewrite of passes that already used the fast dimension: a few percent, not worth the complexity.
- One thread per offset (tens of thousands of tiny blocks) on a small GPU: ~2x slower.
- CUDA graphs for a handful of launches per frame: within noise, plus the baked-argument hazard.
- Running statistics on a side queue: faster but a frame of lag shifts the whole mapping.

## G. Measurement traps

- Wall time around a drain has a floor near a millisecond on mobile GPUs; a real ~30% win can vanish under it. Use event profiling or a single-drain batch.
- Sub-profilers must drain before starting the clock, or they bill earlier stages' backlog (can read several times too high).
- Output file writes and per-stage drains distort GPU busy -- the same pipeline can read anywhere from 20% to over 50%.
- First runs on a cold board read high; discard them.
- A tool can silently ignore its fps cap on one path and run flat out.
- Thermal throttling (clock halved) can make a real 20% win look like a regression.
- A big "regression" can be a stale binary; rebuild from a clean baseline before believing a large swing.
- Same binary twice is not always bit-identical (float atomics) -- judge "bit-exact" against that control.
- The benchmarked output path can differ from the shipped one (e.g. 8-bit grey vs the real colour output format).
- A shipped config can lack the flag its perf number was measured with -- grep the production config.
- Benches copying config fields by hand silently ignore new keys.
