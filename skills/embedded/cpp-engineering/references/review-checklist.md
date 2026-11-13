# C++ review checklist

Use for every review; copy into a repo's `docs/CODING_STANDARDS.md` when it has none, so `/code-review` has a documented standard to check against. Changes touching CUDA/OpenCL also go through the GPU checklist in `gpu-kernel-engineering` → `references/host-code.md`. Each item is a yes/no question about the diff.

## Ownership and errors
- [ ] Every new TensorRT/GStreamer/SDK/file handle is owned by an RAII type — no naked create/release pair in business code.
- [ ] Every new TensorRT/SDK call that returns a status is checked.
- [ ] Nothing can throw across the public API (vendor code and parsing are caught at the boundary).
- [ ] Errors name the resource, field, or call that failed.

## Concurrency
- [ ] New threads are owned and joined; no `detach()`.
- [ ] New queues are bounded with a stated full policy.
- [ ] Every `condition_variable::wait` has a predicate; shutdown order is stop → notify → join.
- [ ] Shared state is guarded or atomic with a stated memory order; no callback from another library's thread touches unguarded state.

## Performance
- [ ] No allocation, logging at info level, or blocking sync in the per-frame path.
- [ ] A claimed speedup comes with a paired A/B measurement on the target (the `edge-benchmark` skill).

## Correctness and numerics
- [ ] A refactor meant to be neutral is verified bit-exact (or within the measured noise band).
- [ ] New config keys are plumbed through every layer (struct, parser, backend, benches) and validated at load.
- [ ] Divisions, logs, and index lookups are guarded at the extremes.

## Build and portability
- [ ] CMake changes are target-scoped; no new global flags or definitions.
- [ ] Builds on every supported target, including Windows if supported; no new POSIX-only call outside the platform layer.
- [ ] No new ad-hoc env var; diagnostics go through the library's debug registry.

## Tests and docs
- [ ] New behaviour has a test or a reproducible check (offline tool + capture).
- [ ] Docs, config reference, and CLAUDE.md updated where behaviour or commands changed.
