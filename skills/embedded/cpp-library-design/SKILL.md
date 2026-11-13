---
name: cpp-library-design
description: Design, extend, or review a C++ library for embedded/edge work — AI inference, GPU image processing, any multi-backend engine — so it stays general, extensible, navigable, and debuggable. Use when the user starts or restructures such a library, adds a backend, stage, task, or model, or writes or reviews its architecture doc.
---

# C++ library design for embedded/edge

Four properties, in this order: **general** (one API over many tasks and backends), **extensible** (adding a backend, stage, or model touches one place), **navigable** (you can guess where code lives), **debuggable** (you can isolate any stage on recorded input). Performance comes from the backends and kernels, not from the API shape — never trade the four away for it at the API level.

Two shapes this covers, as running examples:
- **Inference library** — task (detection, SR, pose) → stages pre / infer / post → backend TensorRT, QNN, SNPE, TFLite, ORT.
- **GPU processing library** — pipeline mode (e.g. full-frame vs crop) → stages (denoise, registration, fusion, tone mapping, colour output) → backend CUDA, OpenCL.

Specifics for each are in [references/inference-backends.md](references/inference-backends.md) and [references/gpu-image-pipelines.md](references/gpu-image-pipelines.md) — read the one that matches before designing.

## 1. Scope — goals and non-goals

One instance = **one unit of work** (one model, or one processing pipeline). Composition of several instances, coordinate transforms, capture, transport, and business logic belong to the application. Write goals, non-goals, and target platforms down first.

Done when the design doc has all three lists.

## 2. Layers

```
Application       composes instances; business logic
Public API        facade: init(config) → [warmup] → process(input) → result; run-time setters
Pipeline / Task   owns stage order and per-frame state; one class per task or mode, registered
Stages            one responsibility each, one interface per kind
Backends          CUDA | OpenCL | TensorRT | QNN | CPU … — SDK/driver types only here
Kernels / glue    .cu / .cl files, SDK wrappers
```

- Dependencies point **down only**. A stage never calls up into the pipeline; a backend never knows the task.
- **Public headers** expose no SDK, CUDA, or OpenCL types; use pImpl so backend changes don't break the ABI. A handful of headers: engine/pipeline, types, config, version.
- Virtual dispatch at init and per-call boundaries only, never per pixel or per element.
- Shared operations (resize, normalize, histograms, reductions, NMS…) live in utils that every stage reuses. A GPU variant implements the same interface as the CPU one.
- **Registration through factories**, so a new task, stage, or backend doesn't edit a central switch. Static-library pitfall: self-registering globals get dropped by the linker unless linked whole-archive or registered by an explicit call.
- **Backend chosen explicitly** in config or at build time; auto-detection (file extension, platform probe) only as a fallback, and logged.

## 3. Navigable — finding files

- **The directory tree mirrors the layers**: public headers (`include/`), internal headers, implementation, kernels, config, tests/tools, docs.
- **Same path shape per backend**: `backends/<backend>/<stage>_<backend>.{cpp,cu}`, `backends/<backend>/kernels/<stage>.{cu,cl}`. Knowing a stage and a backend tells you the file.
- **One token per concept, everywhere**: the stage called `denoise` is `denoise` in the config key, class name, file name, kernel name, log tag, and timing label. One `grep` finds every piece of it.
- One responsibility per file; split files that grow past one concept (rough alarm: >1000 lines).
- The architecture doc lists each layer **with its path**, plus a "to change X, edit Y" table.
- `tests/` or `tools/` gets a table: program → purpose → build flag → still used?
- A `CLAUDE.md`/`AGENTS.md` at the root: build commands per target, layout, naming conventions, verification rules. Agents and new engineers read it first.

Done when a newcomer can find a stage's config key, class, kernel, and test from its name alone.

## 4. Debuggable — finding bugs

- **Every stage runs in isolation on recorded input**: an offline batch tool over a directory of captured frames/inputs, no camera or live source needed.
- **Per-stage dumps** switched by config or env var, one format, named `<frame>_<stage>` — so you can bisect a pipeline by looking.
- **Per-stage timing** with the same labels as the stages; a profiling switch; a stage bench (see the `edge-benchmark` skill).
- **A reference to compare against**: golden outputs, per-frame output hashes for bit-exact refactors, and a measured run-to-run noise band for non-deterministic GPU paths.
- **Backend parity tool**: run the same stage on two backends and diff.
- **Errors carry context**: which stage, which config field, which input; readable via `last_error()` or the result.
- **State is explicit**: what is carried between calls, what resets it, and a way to log it.
- **One build command per target**, and a list of the options that are silently wrong when omitted.

Done when any reported bug can be reproduced offline from a capture plus a config, and narrowed to one stage by dumps or parity.

## 5. Extensible — adding things

Each addition ends with the same gate: **every existing profile and test gives unchanged output** (bit-exact, or inside the measured noise band), and the new path has a test, a benchmark row, and a doc row.

- **Backend**: implements the backend interface; its own build option; same path shape as existing backends; parity against an existing backend on recorded input.
- **Stage**: implements the stage interface; registered; config block with defaults; dump and timing label with its token; isolated test.
- **Task / mode**: class + registration; built from existing stages where possible; result type; reference application.
- **Config key**: default in the one defaults struct; validation; documented with its effect.
- **Profile**: copy the closest one, list only differing keys, run it offline on a known capture, check output size and state behaviour.

## 6. Config contract

- Behaviour selected by config (JSON), not code; the same binary runs every valid profile.
- **Defaults live in one struct; profiles list only the keys that differ.** So changing a default changes every profile that omitted it — treat it as a behaviour change and verify it.
- Relative paths resolve against the config file's directory.
- **Validate at load, before any accelerator work**; reject invalid combinations with a message naming the field and allowed values. A standalone validator runs the same checks.
- Old keys keep loading (or migrate with a warning).
- Profile names follow a fixed pattern (e.g. `<algo>_<backend>_<device>_<mode>.json`); `config/` organised by task/mode and backend.
- Embedded default configs drift from signed-off profiles unless a release check compares them.

## 7. Runtime contract

- **Never throw or crash across the API boundary**: return a result or `bool` plus error code and message. Embedded vision is usually auxiliary — the host must survive it.
- **Fail loudly at load, degrade quietly at run time**: a run-time failure keeps the last good state.
- **"Not ready" is not an error** (warm-up, temporal history filling) — signal it distinctly and document it.
- Thread-safety contract in the header: one instance per thread is the simple default.
- `warmup()` absorbs lazy init (engine setup, JIT compile); never time the first call.
- Results carry per-stage timing; heavier metrics are off by default. Logging via a host callback.
- Process-local settings (CPU affinity) need no restore; **board-wide settings (clock pins, power policy) are restored on shutdown**, and root-only ones degrade gracefully.
- One CMake option per backend; never default a backend ON where its toolchain can't exist. If an auto-switch depends on a parent build's variables, a standalone configure must detect the platform itself or fail with the option to pass.
- Semantic versioning plus a version query.

## 8. Design doc

Write or review it against [references/design-doc-template.md](references/design-doc-template.md). Code-level rules (RAII, checked calls, threads, CMake) are the `cpp-engineering` skill.
