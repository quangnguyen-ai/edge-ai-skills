---
name: embedded-debugging
description: Diagnose memory leaks, crashes, data races, deadlocks, and latency spikes in C++ software on Embedded Linux targets (Jetson, ARM SoCs) — sanitizers, heaptrack/valgrind, gdbserver and core dumps, perf/ftrace/Nsight Systems, clocks and scheduling. Use when the user reports a leak, segfault, hang, race, jitter or latency spike, or memory growth on a device, or asks for system-level profiling on an embedded board.
---

# Embedded debugging

The discipline is the `diagnosing-bugs` skill's: **build a tight feedback loop that goes red on this bug before hypothesising.** Follow its phases if it is available. This skill supplies what changes on an embedded target: where the loop runs, and which tool fits which symptom.

## 0. Where does it run?

Read `docs/agents/execution-environment.md` (if it exists). Then decide, per bug:

- **Can it reproduce in a host (x86) build?** Pure logic, leaks, and most races do — a host build gives faster iterations, full sanitizer support, a real debugger. Host builds are not the default workflow: propose it and let the user decide. Bugs tied to hardware, drivers, timing, or the SoC's memory model don't.
- **On target:** make the loop a single command — the project's `target.sh` (`./target.sh up`, `./target.sh run "…"`; set it up with the `target-workflow` skill if it's missing). If you can't run it yourself, write that command for the user and say exactly what output to paste back.
- Use `RelWithDebInfo` (optimised + symbols). Debug builds change timing and can hide races and spikes.

Done when one named command reproduces the symptom (or reproduces it at a known rate), and you have run it or the user has pasted its output.

## 1. Pick the tool by symptom

**Crash / segfault / abort**
- Enable core dumps (`ulimit -c unlimited`, check `/proc/sys/kernel/core_pattern` — systemd may route to `coredumpctl`). Analyse on the host with `gdb-multiarch` plus the target sysroot and the unstripped binary, or debug live with `gdbserver`.
- ASan build (`-fsanitize=address -fno-omit-frame-pointer`). Expect ~2–3× memory. With CUDA in the process, run with `ASAN_OPTIONS=protect_shadow_gap=0`.

**Memory growth** — first decide which kind:
- Track RSS over time (`/proc/<pid>/status` VmRSS, `smaps_rollup`). On Jetson, CPU and GPU share DRAM: `tegrastats` RAM includes GPU allocations; check `cudaMemGetInfo` too.
- On Jetson the desktop and swap compete for the same DRAM the GPU uses — measure on the production setup (`multi-user.target`, no swap), not a dev desktop.
- Real leak → `heaptrack` (low overhead, works on ARM), LSan, or valgrind memcheck (20–50× slower; only if the workload tolerates it).
- Unbounded queue/cache → memory grows with load and queue depth; it's a design bug, not a leak. **Signature: RSS flat for minutes, then a burst of GBs in seconds** (a consumer stalled, the producer kept pushing) ending in the kernel OOM killer — read `dmesg`/`journalctl -k` for the OOM line. Typical cause: a consumer thread that polls with `usleep` instead of blocking with back-pressure, hit by a transient I/O stall (SD/eMMC flash garbage collection). Fix: bound the queue with a drop policy, make the consumer blocking, and move the slow sink off the stalling medium.
- Intermittent bursts: script a watcher that captures state **at the moment** RSS crosses a threshold (`gdb -p` thread backtraces, queue levels) — the culprit thread is visible only then.
- Allocator fragmentation with many threads → RSS grows while live allocations don't; try `MALLOC_ARENA_MAX`, pooling, or a different allocator.
- GStreamer objects → `GST_TRACERS=leaks` (see `gstreamer-pipeline`).

**Data race / wrong result under load**
- TSan build (`-fsanitize=thread`; not combinable with ASan). Fix every report on the code path, not just the one you were chasing.
- Look for: shared state without a lock, `condition_variable` waits without a predicate (lost or spurious wake-ups), relaxed atomics used for publication, callbacks from a library's thread touching your state.

**Hang / deadlock**
- Attach `gdb -p <pid>` → `thread apply all bt`. Look for a lock-order cycle, a wait on a condition nobody will signal, or a blocked streaming/callback thread.
- Fix with a single lock order, or by not calling out (callbacks, logging that takes locks) while holding a lock.

**Latency spikes / jitter**
- Measure the distribution — p50, p99, p99.9, max — with per-stage timestamps on a monotonic clock. Means hide spikes.
- Usual causes, cheapest to check first: DVFS/thermal throttling (pin and record `nvpmodel`/`jetson_clocks` or the governor; watch temperature), allocations or page faults in the hot path (preallocate; `mlockall`), synchronous logging/file I/O, lock contention, thread migration (CPU affinity), scheduling (`SCHED_FIFO` via `chrt` — beware priority inversion), another process contending for the GPU or memory bandwidth.
- Gaps between kernels on the GPU timeline = CPU launch-bound; a CUDA Graph removes most launch overhead and jitter (recipe in the `model-deployment` skill's runtime-optimization reference).
- Tools: Nsight Systems (`nsys`) for a CPU+GPU timeline on Jetson; `perf sched`, `perf trace`, `trace-cmd`/ftrace for scheduler and kernel events; `cyclictest` for the board's baseline scheduling latency.

**CPU hotspot**
- `perf record -g` (needs frame pointers, or `--call-graph dwarf`) → flame graph. Make sure the board's kernel has perf support.

## 2. Fix and prove it

- The fix comes with the loop from step 0 going green, plus a regression check where one is practical: a sanitizer job in CI on the host build, or a stress/soak test that asserts thresholds (RSS slope, p99 latency, zero TSan reports).
- For leaks and spikes, show before/after numbers from the same board, same power mode, measured back to back.

Done when the original command is green, the before/after numbers are recorded in the notes, and what was not verified (other boards, other power modes, shorter soak than production) is stated.
