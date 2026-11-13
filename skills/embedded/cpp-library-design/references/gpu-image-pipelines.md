# GPU image-processing library specifics

Applies when the library is a chain of GPU stages over a video stream (enhancement, super-resolution, denoise, tone mapping, colour output) with CUDA and/or OpenCL backends.

- **Modes as pipelines**: a config key (e.g. `mode`) selects a stage chain; modes share stages and end in common ones (e.g. tone mapping → colour output). Each mode is a class or a declared stage list, not `if` branches scattered through stages.
- **Backend owns per-frame state**: frame ring, temporal history (carried estimates, motion fields, damped histograms/curves). Document the state inventory in the design doc.
- **Warm-up**: temporal modes produce nothing for the first `N − 1` frames — return "not ready" (e.g. `false` with an empty error), distinct from failure. Modes without warm-up say so.
- **State resets**: list every event that resets temporal state (toggling a stage, changing crop/size, re-init) and what the caller sees next (warm-up again, a few frames of settling).
- **Output size** may be known only after the first frame (it depends on mode and input) — document when buffers can be allocated, or expose sizes after init.
- **Device-side statistics**: histograms, percentiles, reductions stay on the GPU; the host reads back only the scalars it needs, only on frames that refresh them. A readback is a pipeline barrier.
- **Stage processors** are one class + one kernel file per stage per backend, named by the stage token; the backend class only orders them and owns buffers.
- **Kernel compilation**: OpenCL kernels JIT-compile at first use (warm-up), and cached binaries go stale after a signature change — version or clear the cache. CUDA: watch the compute cache likewise.
- **Verification**: structural refactors bit-exact by per-frame output hashes; GPU paths with float atomics get a measured run-to-run noise band; cost measured with a stage bench, camera-free, with no other GPU clients.
- **Write carried state last.** A temporal memory (EMA, trust gate, damped curve) must be written after every stage that can still change the current value; written earlier, a correction made later in the frame is never remembered and the defect comes back in a cycle.
- **Camera/sensor specifics** (vendor raw-format decoding and conversion, flips, per-camera calibration files) live in their own module (`camera/`, `<sensor>/`), so the pipeline sees one canonical input format.
- **Optional vendor SDKs** (a camera SDK not in the repo): found by a CMake search path with an explicit `-D…_ROOT` override; only the targets that need it depend on it, so everything else builds without it.
- Kernel-level work (optimization ladder, numerics, CUDA/OpenCL parity): the `gpu-kernel-engineering` skill.
