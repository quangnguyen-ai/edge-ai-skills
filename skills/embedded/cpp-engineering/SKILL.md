---
name: cpp-engineering
description: Write and review production C++ for edge targets — RAII for every handle (TensorRT, GStreamer, SDKs), checked calls and a no-throw API boundary, owned threads and bounded queues, debug switches, modern target-based CMake (Linux + Windows), new-project bootstrap, review checklist. Use when writing or reviewing C++, setting up or fixing CMake, starting a C++ project, or porting to Windows.
---

# C++ engineering for edge

Rules that keep embedded C++ correct under load and cheap to change. Each comes from defects found in real edge codebases: unchecked API calls by the hundred, hand-paired create/release calls that drift apart, vendor code throwing through a "never throws" API, detached threads outliving their captures, a dozen ad-hoc debug env vars, and monolithic CMake with global flags.

Library structure (layers, backends, config contract) is the `cpp-library-design` skill. **Anything CUDA or OpenCL** — kernels, and the host code around them (device buffers, streams, events, error checks, transfers, CUDA build flags and CMake) — is the `gpu-kernel-engineering` skill and its `references/host-code.md`. This skill is the C++ underneath.

## 1. Ownership — RAII for every handle

- **No naked resource calls outside a wrapper**: TensorRT objects, `gst_*_unref`, vendor SDK open/close, file and socket handles — and GPU handles (wrappers in `gpu-kernel-engineering` → `host-code.md`). One small owning type per handle kind, move-only, released in the destructor.
- Resources are allocated once at init and reused per frame. No allocation in the per-frame path.
- TensorRT objects in `std::unique_ptr` (TRT 10: plain `delete`); destroy in reverse creation order (context → engine → runtime).
- GStreamer: `g_autoptr(...)` / RAII wrappers for elements, samples, caps, maps; every `map` paired with `unmap` in the same scope.

Snippets: [references/raii-and-checks.md](references/raii-and-checks.md).

## 2. Every call checked

- Wrap every TensorRT and SDK call that returns a status in a check that records the call text, file:line, and error string (CUDA/OpenCL checks: `host-code.md` in `gpu-kernel-engineering`).
- Errors become the library's error code + message at the API boundary. **Code that may throw** (vendor SDK utilities, `std::` containers, JSON parsing) is caught at that boundary — a "never throws" API must actually not throw.
- Fail loudly at init (missing file, bad config, unsupported device) with the field or resource named; degrade quietly per frame.

## 3. Threads and queues

- Threads are **owned and joined**: a member `std::thread` joined in the destructor (or `std::jthread` with C++20). Never `detach()` a thread that captures `this`, references, or locals.
- Every hand-off between threads is a **bounded queue with an explicit full policy** (drop oldest / drop newest / block), sized in the constructor. Unbounded queues are a memory bug waiting for a slow consumer.
- `condition_variable::wait` always with a predicate; shutdown sets a stop flag under the mutex, notifies, then joins.
- Consumers block on data; never `usleep`-poll.
- Run the host build under TSan in CI.

## 4. Debug and profiling switches

One registry, read once at init, off by default, documented in one table:

- One prefix per library: `<LIB>_DEBUG=<stage,…>`, `<LIB>_PROFILE=1`, `<LIB>_DUMP_DIR=<path>`. Not a new ad-hoc variable per investigation.
- Env vars only for diagnostics (logs, dumps, timing). Anything that changes output is a config key, validated with the rest.
- Remove one-off investigation switches when the investigation ends.

## 5. Performance hygiene

- Profiling builds: `RelWithDebInfo` (GPU transfer, stream, and build-flag rules: `host-code.md` in `gpu-kernel-engineering`).
- Hot loops: no `std::function`, virtual calls, or heap allocation per element; no `std::endl`/logging per frame at info level.

## 6. Build — modern CMake

Target-based CMake only: properties on targets, not global flags. Template and the pitfalls (`option()` caching, vendor SDK and TensorRT discovery, Windows exports, old CMake on boards) in [references/cmake.md](references/cmake.md). The CUDA block (language, architectures, old-CMake fallback) is in `gpu-kernel-engineering` → `host-code.md`.

## 7. Linux and Windows

- Core code uses `std::filesystem`, `<chrono>`, `<thread>` — no POSIX calls outside a small `platform/` layer.
- Shared-library exports through `GenerateExportHeader` (`MYLIB_EXPORT`), not hand-written `__declspec`.
- MSVC: `/W4 /permissive- /utf-8`; GCC/Clang: `-Wall -Wextra`. Treat new warnings as errors in CI.
- `.gitattributes` fixes line endings; paths built with `std::filesystem::path`, never string concatenation.
- CI builds both platforms, or the Windows build rots within weeks.

## 7b. New project

Bootstrapping a new C++ repo: the layout and files in [references/cmake.md](references/cmake.md) → "New project", plus a `CLAUDE.md` (the `onboard-codebase` skill's template) and `target.sh` (the `target-workflow` skill). Done when configure, build, and one test pass on the target from a clean clone.

## 8. Review

Review C++ changes against [references/review-checklist.md](references/review-checklist.md). It doubles as the documented standard the `/code-review` skill checks against — copy it into a repo's docs when the repo has none. GPU code also goes through the checklist at the end of `gpu-kernel-engineering` → `host-code.md`.

## Completion

Done when: no new naked resource call or unchecked API call; every new thread is joined and every new queue bounded; no new ad-hoc env var; CMake changes are target-scoped; the change builds on every supported target (including Windows if supported); and the review checklist passes.
