# GPU/Embedded Target Debugging

Supplement to the main [reverse-engineer-closed-source](../SKILL.md) skill. These
techniques are specific to CUDA kernels and embedded ARM targets (e.g. Jetson-class
devices). A typical order of escalation on a GPU target: `nsys` to find *which*
kernels run and in what order → a custom CUPTI/LD_PRELOAD hook to capture the *real
buffers* that feed the main skill's black-box curve-fitting technique → cuda-gdb for
live register-level confirmation once a hypothesis needs settling → Ghidra when
tracing hits a wall that needs static decompilation instead. In practice the CUPTI
hook section below is the one you'll reach for most: on a GPU target it's usually
*how* you get the real input/output buffers that curve-fitting needs in the first
place, not a fallback for when curve-fitting has already stalled.

## Nsight Systems (`nsys`) Tracing — Reach for This Before Hand-Rolled Hooking

If you're building custom `LD_PRELOAD`/CUPTI-callback hooks to discover *which*
kernels run and in what order, try `nsys` first — it's usually faster to a first
answer and, crucially, works in cases where hand-rolled interception doesn't.

- **`nsys` captures every launched kernel at the CUPTI/driver level, which is immune
  to tricks that defeat userspace symbol interposition.** A target that resolves CUDA
  entry points dynamically (`cuGetProcAddress`/`cudaGetDriverEntryPoint`) or loads
  libraries with flags like `RTLD_DEEPBIND` can make `LD_PRELOAD`-based hooks on
  `cuLaunchKernel`/`cudaLaunchKernel`/`dlsym` catch *zero* calls, even when those
  hooks are definitely wired in correctly — this is a real, observed failure mode, not
  a hook-authoring bug to keep debugging. When several independent LD_PRELOAD hooking
  strategies against the same target all report zero hits, stop trying variations on
  that approach and switch to `nsys` instead of continuing to fight it.
- **Minimal workflow**: `nsys profile --trace=cuda,osrt --output=/tmp/trace
  ./target_binary <args>`, then `nsys export --type sqlite --output=/tmp/trace.sqlite
  /tmp/trace.nsys-rep` to get a queryable SQLite database. The
  `CUPTI_ACTIVITY_KIND_KERNEL` table gives you the demangled name, start/end
  timestamp, grid/block dims, and stream ID for every kernel actually launched on the
  GPU — regardless of how its address was internally resolved. Query it with plain
  `sqlite3` ad-hoc queries once exported.
- **`nsys stats --report cuda_gpu_kern_sum`** gives a fast per-kernel-name summary
  (total time, call count) without needing the sqlite export — good for an initial
  "which kernel dominates the pipeline's runtime" pass, and for counting launch
  instances. A kernel launching exactly once per output frame/iteration (1:1 ratio)
  points at a single-shot kernel with internal loops; a kernel launching N times per
  frame points at a genuine multi-pass/iterative scheme — this distinction is
  otherwise easy to get backwards from disassembly alone (a kernel full of backward
  branches can look like an iterative multi-launch search when it's actually one
  launch with internal tile-loading/boundary loops).
- **Wall-clock adjacency in an `nsys` timeline does NOT imply pipeline-stage
  adjacency once more than one frame or stream is in flight concurrently.** Two
  kernels that look like "step N, then step N+1" in timestamp order can actually
  belong to *different* logical stages that happen to overlap in real time (e.g. one
  stage finishing frame K while another stage starts frame K+1 on a different
  stream). Before trusting "kernel X happens right after kernel Y" as a pipeline-order
  claim, group/filter by CUDA stream ID (present in the kernel table) and confirm the
  kernels you're comparing are actually on the same stream.
- **The same kernel name can appear at multiple distinct grid/block sizes for
  genuinely different purposes** (e.g. the same quantization kernel used once at
  native resolution for one stage and again at an upscaled resolution for another
  stage entirely). A kernel that looks out of place in the pipeline order is worth
  double-checking by grid dimensions before concluding it's shared/reused logic — it
  may be two unrelated call sites that happen to share a name.
- **When a setter/getter/factory symbol you want to breakpoint isn't dynamically
  exported** (inlined away in the actual shipped build, common for small
  config-setter methods), live timing/grid-dims from an `nsys` trace across several
  different configurations is a reasonable fallback cross-check for a value recovered
  by static decompilation — e.g. confirming a decoded "frame count" parameter by
  matching the number of distinct kernel launches per output across configurations,
  even though you can never breakpoint the exact setter call that assigned it.
- **`nsys`'s memcpy/memset event tables don't always expose per-event source/
  destination virtual addresses** (the address column may only populate for
  unified-memory page-migration events, not plain device-to-device copies) — useful
  for confirming *that* operations of a given size/count exist in the pipeline, but
  don't expect it to pin down *which specific buffer* those operations touch without
  corroborating evidence from another tool (a CUPTI callback hook that does have the
  pointer, or a live gdb/cuda-gdb read).
- **Nsight Compute (`ncu`)** is the complementary per-kernel profiler (register/shared-
  memory usage, occupancy, detailed instruction mix) when you need to go deeper than
  `nsys`'s timeline-level view into one specific kernel's execution characteristics —
  reach for it once `nsys` has told you *which* kernel to focus on, as a cheaper
  alternative to full SASS reading for questions about resource usage and stalls (not
  yet exercised in depth for this skill's write-up — treat the above `nsys` guidance as
  the battle-tested path, and `ncu` as the logical next tool to try for occupancy/
  resource-usage questions it doesn't answer).

## CUPTI-Based LD_PRELOAD Capture Hooks — the Workhorse Tool for Real Buffer Capture

`nsys` tells you *which* kernels run and in what order; it does not give you the
actual bytes in a kernel's input/output buffers. For that — feeding the black-box
curve-fitting technique in the main skill with real captured data instead of
simulated guesses — build a small custom shared library that intercepts CUDA kernel
launches via CUPTI's callback API, loaded with `LD_PRELOAD`. This was, by volume, the
single most-used technique across this kind of project: expect to build many small,
single-purpose hook variants (one per buffer/kernel/question) rather than one
general-purpose tool — each is cheap to write once you have the boilerplate.

- **Shape of the tool**: a small C file, cross-compiled for the target
  (`aarch64-linux-gnu-gcc -shared -fPIC -o hook_name.so hook_name.c -lcupti ...` for an
  ARM/Jetson target), that calls `cuptiSubscribe` on load (via a constructor /
  `cuInit` interception) and registers a callback on the CUDA Runtime or Driver API
  domain for the launch functions you care about (`cudaLaunchKernel`,
  `cudaLaunchKernel_ptsz`, `cuLaunchKernel`, …). The callback receives the kernel's
  arguments and fires at two points per launch: `CUPTI_API_ENTER` (before the call)
  and `CUPTI_API_EXIT` (after it returns to the caller) — load it into the target
  process with `LD_PRELOAD=./hook_name.so ./target_binary <args>`.
- **Permissions**: on a locked-down target (e.g. Jetson with
  `RmProfilingAdminOnly=1`), `cuptiSubscribe` returns `CUPTI_ERROR_INSUFFICIENT_PRIVILEGES`
  for a non-root user — you need root. Use `sudo env VAR1=val1 VAR2=val2
  LD_PRELOAD=./hook_name.so ./target_binary <args>`, **not** `sudo -E` — on some
  systems `sudo -E` still strips security-sensitive variables like `LD_PRELOAD`/
  `LD_LIBRARY_PATH` even though it's meant to preserve the environment. Passing the
  variables explicitly as `sudo env VAR=val ...` sidesteps that.
- **The ENTER-callback timing trap (this one cost real, reproducible-looking bugs):**
  `CUPTI_API_ENTER` for a launch fires *before* that kernel has actually been
  submitted to the GPU stream. A `cuCtxSynchronize()` call made inside an ENTER
  callback therefore only waits for *prior* work already in the stream — not the
  kernel you just detected — so a dump taken "at this kernel's own ENTER, after a
  sync" silently reads a stale, effectively previous-cycle buffer value. This is the
  root of a general dump-timing rule worth encoding directly into your hook's design:
  for a pipeline that reuses fixed-address buffers across iterations (very common —
  check this first), **dump an input operand at its own consuming kernel's ENTER**
  (its value must already be finalized by whatever wrote it, since that write already
  happened in an earlier launch), but **dump an output buffer at the ENTER of the
  *next* launch after the kernel that produces it** (exactly one callback later — not
  at the producing kernel's own ENTER *or* EXIT, both of which can still be
  mid-flight/stale on this kind of pipeline). Validate empirically if unsure: sweep
  the defer margin (0, 1, a few launches further) and confirm the captured value
  stops changing once you've deferred far enough — a result that keeps changing as
  you defer further than 1 extra launch suggests a different synchronization issue
  entirely (see the coherency caveat below), not just an ENTER/EXIT timing choice.
- **Never dereference `args[i]` of a kernel signature you haven't verified.** A launch
  callback typically hands you a raw argument array; treating `args[2]` as a pointer
  when the real signature has a scalar float there (common with overloaded/templated
  kernel entry points) segfaults the target process. Get the real signature first —
  demangle the kernel's mangled name with `c++filt` (strip any compiler-internal
  wrapper prefix first, e.g. `__nv_static_...__`, then feed the `_Z`-prefixed part
  onward to `c++filt`) — before writing code that reads specific argument slots.
- **"Writer search" pattern — finding which kernel writes a buffer without already
  knowing any kernel's signature**: log every launch's first few argument values
  (treated as candidate addresses) across the whole run, and flag any launch whose
  argument matches an address of interest (a buffer you obtained some other way, e.g.
  from a `cudaMalloc` interception or a previous dump). This finds the *producer* of a
  given buffer from scratch, which you can then dig into properly once identified.
- **Make hooks configurable via environment variables**, not recompiles — a target
  launch index, cycle number, or output directory read from `getenv()` at hook
  startup lets you retarget the same compiled `.so` at a different point in a run (or
  a different run entirely) without rebuilding, which matters because builds against
  an ARM/embedded target are usually slower than on your own machine.
- **On a unified-memory SoC (e.g. Tegra-class embedded GPUs, where the CPU and GPU
  share physical DRAM through a shared cache hierarchy), a plain
  `cuCtxSynchronize()` + `cuMemcpyDtoH()` pair issued from inside an LD_PRELOAD
  callback at an unusual point in the CUPTI callback lifecycle is not automatically
  guaranteed to be fully coherent the way it would be on a discrete GPU.** If you've
  already fixed the ENTER/EXIT timing trap above and a small, reproducible residual
  discrepancy still won't close (same direction and rough magnitude regardless of
  which specific capture variant you try), consider that the diagnostic tooling
  itself — not the pipeline under study — may be the source, and that closing it
  fully would need a different class of tool (driver/coherency-level debugging)
  entirely. Flag this explicitly as a known limit of this technique rather than
  spending unbounded time chasing a small gap that doesn't move with any pipeline-side
  hypothesis you test.

- **A `cudaMemcpy` capture hook must only dereference host pointers it knows are host.**
  `cudaMemcpyDefault` infers direction from pointer attributes and may carry a device
  source; logging it with a naive host read segfaults the target. Hook explicit
  `cudaMemcpyHostToDevice` (or query `cudaPointerGetAttributes` first).

## gdb Live-Debugging on Multi-Threaded ARM Binaries

- **Never "warm up" a breakpoint** (set it, continue once, delete it, then set the real
  one) **on a multi-threaded target.** This pattern is sometimes recommended to dodge
  stack-address volatility, but on a multi-threaded process it can silently break
  breakpoint delivery to *other* threads afterward — producing the exact symptom of "I
  can prove via a working watchpoint that this address definitely executes, but a plain
  breakpoint there gets zero hits." Fix: set every breakpoint you need immediately
  after `break main; run`, with no delete-then-reset cycle in between.
- **`frame.read_register("sN")` can raise `gdb.error: Cannot convert value to float`**
  on some aarch64 targets (NEON register union ambiguity). Use
  `gdb.execute("print $sN")` and parse the `f = ...,` field from the text output
  instead — far more robust across contexts.
- **A static disassembly search for a register by name can silently miss aliased
  forms.** A 32-bit float write like `movi v8.2s, #0x0` won't match a naive regex for
  `\bs8\b` even though it clobbers the same physical register as `s8` (aarch64 widths
  alias `s`/`d`/`v` for the same register number). Search for all width-aliases
  together (`s8|v8|d8`), or you'll misdiagnose a register as "never reassigned" when it
  actually is.
- **When a value appears to survive a call unchanged (proper callee-saved
  register handling in the disassembly) but empirically changes anyway**, don't trust a
  static read of "which branch executes." Verify the real runtime control flow instead
  — a `stepi`-based tracer that treats every `bl`/`blr` as "step into, then `finish`"
  (i.e. steps *over* calls while still descending into each one) and prints the
  register only when its value changes pinpoints the exact instruction where a value
  changes across many intervening call layers, far faster than reading disassembly by
  hand — and catches cases where a branch target you assumed would execute (e.g. a
  "reset to zero") is actually skipped in favor of a different branch you hadn't
  traced.
- **A value can be many call-levels removed from where it's "used."** A register
  consumed deep in a fused computation can originate from a virtual-method call on a
  completely different sub-object, several levels away in a different subsystem than
  the one you started investigating. Know when to stop: once tracing a single scalar's
  provenance would require starting a new investigation of a whole separate subsystem,
  a well-validated empirical fit (with proper held-out cross-validation — e.g.
  leave-one-case-out) is often the pragmatic stopping point.

## cuda-gdb Device-Kernel Live Register Tracing

Reach for this once static SASS-only reasoning about a kernel's exact semantics has
gone through two or more rounds of hypothesis-and-retraction — live register values
settle disputes that repeated static reading can't.

- **A bare `cuda-gdb <binary>` run that SIGSEGVs inside `libcudadebugger.so` on the
  first CUDA event is a permissions problem, not a broken-tool problem.** Re-run the
  identical command under `sudo`, preserving environment variables explicitly (`sudo
  VAR1=x VAR2=y cuda-gdb ...`, since `sudo` resets the environment by default) before
  trying anything more involved like `ptrace_scope`/capability tuning.
- **`break <short_demangled_name>` and `rbreak <regex>` can both silently fail to ever
  trigger a device breakpoint**, even with `set breakpoint pending on`, even after
  confirming the target kernel has already launched (via a host-side breakpoint on
  `cudaLaunchKernel`). Fix: let the host breakpoint on `cudaLaunchKernel` fire first
  (conditioned on the specific launch you want — see below), then run `info functions
  <short_name_regex>` to reveal cuda-gdb's actual internal name for the symbol — the
  full double-prefixed mangled form (the same one `cuobjdump -symbols` uses), not the
  bare demangled-looking name. `break` with that exact full name then resolves
  immediately to a real file:line.
- **`set language c++` before touching device functions** avoids a "type printing not
  implemented for language 'Auto'" internal gdb error that otherwise aborts whatever
  command you run after `info functions`/`info address` on a C++ device symbol.
- **Condition a `cudaLaunchKernel` breakpoint on raw ARM64 argument registers** to
  isolate one specific launch out of thousands without needing a symbol name yet.
  `cudaLaunchKernel(func, gridDim, blockDim, args, ...)` packs each `dim3` (12 bytes)
  into two consecutive registers under AAPCS64 (first register = `x | (y<<32)`, second
  = `z`) — e.g. `x1`/`x2` carry gridDim and `x3`/`x4` carry blockDim for a typical call,
  so a condition on the packed literal values of a known grid/block shape reliably
  isolates one launch among many near-identical ones.
- **Once stopped at a device breakpoint, `break *($pc + OFFSET)` jumps straight to a
  specific SASS address** already identified by static `cuobjdump -sass` reading —
  confirm it landed correctly by disassembling at the new breakpoint (`x/Ni $pc`) and
  checking it matches the expected instruction.
- **`print $R4` on an aarch64/CUDA target prints the register's raw bit pattern as a
  plain integer, not a float**, even when the surrounding SASS clearly operates on it
  with float ops (`FADD`/`FSET`). Decode manually (e.g. in Python:
  `struct.unpack('<f', struct.pack('<I', raw_int))[0]`). Skipping this and eyeballing
  the raw integer looks like nonsense and can lead to wrongly concluding the value is
  garbage.
- **A small number of live samples of one register at one instruction (6-8, across
  different threads/blocks via repeated `continue`) can reveal a decisive pattern that
  immediately falsifies prior SASS-only hypotheses** — e.g. a value that's always
  exactly `0.0` or a clean large value with nothing in between, pointing at a boundary
  check rather than a computed similarity/confidence score. When static SASS-only
  reasoning about "why compare against this specific constant" is on its second or
  later revision, that's the trigger to switch to live sampling rather than keep
  refining the static reading.

## Ghidra / PyGhidra Static Analysis

Complements the live gdb/cuda-gdb techniques above — when live-tracing hits a wall
("would require starting a new investigation of a whole separate subsystem"), a
decompiler can answer in minutes what tracing would take hours to reach.

- **Portable install needs no sudo.** Download a portable JDK tarball (check Ghidra's
  `Ghidra/application.properties` for its `application.java.min` field — newer Ghidra
  releases need a newer JDK than you might expect) plus the Ghidra release zip, extract
  both under a plain user directory. `analyzeHeadless <project_dir> <project_name>
  -import <binary> -analysisTimeoutPerFile <secs>` builds a full auto-analyzed project
  non-interactively.
- **PyGhidra over Jython for scripting**, on Ghidra versions that ship both: `pip
  install pyghidra` gives a real CPython3 bridge — `import pyghidra; pyghidra.start()`
  then `GhidraProject.openProject(path, name, True)` + `.openProgram(...)` reopens an
  already-analyzed project instantly (no re-analysis) for scripted queries. Needs
  `GHIDRA_INSTALL_DIR` and `JAVA_HOME` set before `pyghidra.start()`.
- **Ghidra's default image base for a PIE shared object is typically `0x100000`.** If
  you've already established "static offsets" via `objdump`/gdb-base-subtraction, those
  map directly: `ghidra_addr = 0x100000 + static_offset`. Verify once via a known
  function before trusting it project-wide.
- **The decompiler often resolves in one call what took an hour of manual
  disassembly/gdb stepping.** `DecompInterface().decompileFunction(fn, timeout,
  monitor)` gives readable pseudo-C directly, including making memcpy/virtual-call
  arguments and conditional logic immediately legible, versus manually reading
  `bl`/`blr` disassembly.
- **RTTI class names are recoverable even in stripped binaries.** `__dynamic_cast(src,
  src_type, dst_type, 0)` calls reference `type_info` object addresses directly as
  arguments; a `type_info` object's layout is `[own-vtable-ptr][name-ptr][...]`, so
  reading the pointer at `type_info_addr + 8` and then the C-string there gives the raw
  mangled class name (feed it to a demangler). Ghidra may label these operands with
  generic auto-names (`PTR_PTR_<addr>`) when it can't fully resolve GOT-style
  indirection — read the actual bytes/relocation at that address rather than trusting
  the auto-label.
- **CUDA kernel names survive stripping and are a high-value static-analysis find.**
  The CUDA runtime's registration mechanism (`__cudaRegisterFunction(host_stub_addr,
  "_ZmangledKernelName", ...)`) embeds every kernel's mangled name as a literal string,
  required at load time regardless of `strip`. Grep Ghidra's extracted ASCII strings
  for `_Z`-prefixed strings and pipe through `c++filt` — this recovers full kernel
  signatures (and often the surrounding class/namespace structure) for an entire GPU
  pipeline in one pass, something live tracing alone cannot do (it only sees whichever
  kernels actually execute for your traced input, not the full roster).
- **Do not identify a kernel's host-stub by argument count/order alone — cross-check
  via the registration call.** A launcher wrapper's argument shape can coincidentally
  match more than one kernel's signature. Instead: find callers of the registration
  thunk, decompile each, grep for the target name string to get its *exact* stub
  address, and compare that against the function under investigation. The
  registration-call cross-check is exact; signature matching alone is only a hint and
  can give a confidently wrong answer.

## Inverting an Unmeasurable Parameter Through a Measurable Downstream Value

When a parameter's own computation site can't be found (e.g. buried in an unreachable
or purely-virtual call graph), but a value it feeds into downstream *can* be measured
live and the downstream formula is otherwise exactly known, invert the formula
numerically instead of continuing to hunt for the source: binary-search over candidate
values of the unknown parameter, run the known downstream formula, and match against
the live-measured target.

- **Verify the direction of monotonicity empirically before binary-searching — don't
  assume it.** An intuitive guess about which way a parameter should push an output can
  be backwards (e.g. "more headroom → less clipping → higher output" when the real
  relationship is flat until a cap kicks in, then decreasing). A binary search with the
  wrong comparison direction doesn't error — it silently converges to a boundary value
  for every input, which looks like "no valid answer" or "same answer regardless of
  input" and can be mistaken for a data problem rather than a search-direction bug.
  Diagnose by manually scanning a handful of coarse candidate values first and checking
  which way the output actually moves.
- **A cleanly-converging, monotonic inversion can still surface a genuine physical
  anomaly, not a bug.** A value that comes out well outside its theoretical bound even
  after confirming monotonicity and fixing the search direction is real signal that the
  assumed formula/regime breaks down under that specific input's extreme conditions —
  don't discard it as noise; flag it as a distinct regime needing its own
  investigation.
- **A more accurate fit for an intermediate value does not guarantee better end-to-end
  accuracy.** An intermediate quantity can matter far less to the final result than its
  position in a pipeline diagram suggests, especially if it's only active in a narrow
  regime. Always validate an intermediate-value improvement against the actual
  end-to-end metric before adopting it.
