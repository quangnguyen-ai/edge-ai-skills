---
name: reverse-engineer-closed-source
description: Reproduce a closed-source algorithm, library, or binary from its observable input/output behavior — hypothesis-driven parameter sweeps, black-box curve-fitting, debugger tracing, disassembly. Use when the user wants to clone or match a closed binary/vendor SDK's output without source, or a reimplementation doesn't match the original bit-for-bit.
---

# Reverse-Engineering Closed-Source Algorithms

A discipline for recovering an algorithm's exact behavior when you have the compiled
artifact (and maybe a debugger) but not the source — learned from reproducing
closed-source signal/image-processing pipelines to within fractions of a percent of
the reference output, pixel-by-pixel, with no access to the implementation.

**Core idea:** treat this as an empirical science problem, not a code-reading problem.
You have a black box, you can feed it inputs and observe outputs, and you can
sometimes instrument it live. Build a tight feedback loop between hypothesis and
measurement, and let the data — not guessing from variable names or plausible-sounding
classical algorithms — drive every conclusion.

## Phase 1 — Understand the Problem Space

1. **Collect input/output pairs** — get as many `(input, reference_output)` pairs as
   possible, across as many different conditions/configurations as you can. Breadth
   here pays off later: a formula that looks solid on one input often breaks on
   another.
2. **Read every scrap of available documentation** — CLI help text, header files,
   doxygen comments, config schemas, even terse one-line descriptions. A phrase like
   "limit relative to the cumulative total" is a real algorithmic hint, not
   filler.
3. **Map the parameter space** — list every tunable parameter, its type, and its
   plausible range. Note which ones are exposed to the caller vs. hardcoded somewhere
   in a wrapper.
4. **Check for adjacent source** — even when the core is compiled, nearby `.cpp`/`.hpp`
   files, test programs, or calling code that aren't themselves obfuscated often reveal
   default parameter values and which knobs actually get exercised in practice.
5. **Don't trust a bundled "reference" library as the exact shipped build.** A static
   library or sample implementation sitting next to the target binary, even one that
   shares class names (confirmed via RTTI strings), may be a generic third-party
   reference copy rather than the actual customized code that got linked in. Before
   spending real effort decompiling it, grep the *actual target binary* for a handful
   of that file's internal, non-public symbol names (anonymous-namespace helpers,
   profiler strings naming specific methods) — if those don't show up in the target,
   you're looking at the wrong code. Class-level RTTI name matches are weak evidence
   (RTTI strings often survive regardless of which build you have); internal
   implementation-detail symbol names surviving is much stronger evidence, because
   they're usually the first thing stripped or renamed if the build differs.
6. **Public API documentation on a class the binary actually contains is more
   trustworthy than decompiling an unverified reference build of that same class.**
   Doxygen/header comments describing a confirmed-present class's contract (what a
   parameter does, what stage happens before/after) tend to hold up even when a
   same-named reference implementation turns out to be a different build. Use
   documented *interface* claims with confidence; reserve decompilation for *how*, and
   only once you've verified you're decompiling the real shipped code (see above).

7. **Shipped diagrams, source comments, and config-call order are not evidence of
   runtime order.** A vendor's pipeline diagram and header comments can describe the
   stages in the wrong order. Establish the real order by tracing what actually runs
   (kernel launch trace, call trace) on the real binary.
8. **Label every finding by evidence level** — "confirmed live on the real
   device/binary" vs "consistent with a reference library or docs, not independently
   verified". Don't let the two blur in how confidently a result is stated, including
   in delegated sub-agent reports.

## Phase 2 — Establish Ground Truth

1. **Pin down exactly how your reference data was generated** — which binary, which
   version, which flags. Two call sites into the "same" library can hardcode different
   parameters; confirm you're comparing against the actual configuration you care
   about, not a sibling one.
2. **Use a per-sample error metric as your primary signal** — e.g. per-pixel MAE for
   images, or the equivalent for your domain. It's far more diagnostic than an
   aggregate similarity score, because it shows you *where* the mismatch is, not just
   that one exists.
3. **Start with the simplest case that still exercises the real code path** — one where
   few edge cases activate (no clipping, no outlier handling, no outliers). Get that
   case matching before tackling harder ones; it isolates the core formula from the
   edge-case logic layered on top of it.

## Phase 3 — Hypothesis-Driven Parameter Sweeps

**Core loop:**
```
hypothesis → run the real binary varying one parameter → compare error → accept/reject
```

1. **Vary one axis at a time.** Batch experiments that sweep a single parameter
   (a gain, a threshold, a smoothing factor) so a change in error is attributable.
2. **Prefer running the real target over simulating parameters you're unsure about.**
   If you can execute the actual binary with different inputs/configs, do that instead
   of guessing what a parameter does and modeling it from assumptions.
3. **Compare the shape of the response, not just the aggregate error.** Plot
   input→output (a "transfer curve") for your model vs. the reference. Crossing curves
   tell you *where* the model is wrong — only in the high range, only near a
   discontinuity, etc. — in a way a single error number can't.
4. **Look at distributional/statistical properties of the input**, not just the
   output — histogram shape, active range, how much of the data is clipped or
   saturated. This is often what explains why two inputs that "should" behave the same
   don't.

## Phase 4 — Multi-Case Generalization

1. **Test a second, meaningfully different case immediately** after getting the first
   one working. A formula fit to a single case is not yet a formula — it's a
   coincidence until proven otherwise.
2. **When different cases need different parameter values, suspect an adaptive,
   data-driven formula** rather than a fixed constant:
   - Ask: what measurable property of the input changes between the cases?
   - Try `param = base_value × (some_input_metric)^exponent` and sweep the exponent
     (0, 2, 4, 6, 8…) against the real target.
3. **Watch for inputs that activate different code paths**: heavy clipping/saturation,
   very narrow dynamic range, near-degenerate (uniform/constant) inputs. These often
   reveal branches a "normal" input never exercises.

## Phase 5 — Ruling Out Wrong Hypotheses

Keep an explicit "ruled out" list as you go — it prevents re-litigating the same dead
end weeks later (see also "search before re-deriving" below). Categories of
hypothesis that are tempting but frequently wrong:

- A classical, textbook algorithm name matching the parameter's *name*, when the real
  implementation is a bespoke multi-stage blend that only superficially resembles it.
  (e.g. an "edge-preserving" parameter doesn't automatically mean a bilateral filter —
  verify the actual math, don't let a plausible classical algorithm substitute for
  tracing it.)
- Smoothing/normalization applied in the wrong *space* (e.g. smoothing a histogram
  when the real smoothing happens in output space as an unsharp mask).
- A static parameter where the real formula is adaptive (see Phase 4).
- Redistribution/iterative schemes (CLAHE-style excess redistribution, water-filling)
  that look right in aggregate but are wrong per-element — see the "aggregate ≠
  per-element" lesson below.

## Accuracy Targets for Closed-Source Reproduction

| Target | Error (as % of full range) | Feasibility |
|---|---|---|
| Bit/pixel-exact | 0% | Usually impossible — float/platform rounding differences |
| Excellent | < 0.5% | Very hard — requires knowing exact rounding/border handling |
| Good | < 1% | Achievable once the algorithm itself is correct |
| Acceptable | < 1.5% | Reasonable target for most practical reuse |
| Incomplete | > 2% | Usually signals a *missing formula or branch*, not precision noise |

**Key insight:** an error well above the "good" band almost always means a missing
algorithmic piece (a branch you haven't found, an adaptive term you're modeling as
static), not accumulated floating-point imprecision. Precision differences alone
typically contribute a small fraction of the total error.

## Tools & Techniques

- **Batch experiment runner** — script that drives the real target across a parameter
  sweep and collects outputs for comparison; this is the single highest-leverage tool
  in the whole process.
- **Transfer-curve plot** (input vs. output scatter) — visualize where and how your
  model diverges.
- **Per-step error table** — for anything with temporal/iterative state, error that
  grows over steps/frames is a tell for a damping or recursion bug (see below).
- **Disassembly** (`objdump -d`, Ghidra), **profiler-level tracing** (Nsight Systems/
  `nsys`, or an equivalent kernel/call timeline tool for your platform), and **live
  tracing** (gdb/cuda-gdb) — reach for these once black-box curve-fitting stalls; see
  the technique below for when it's worth skipping straight to tracing, and
  `references/gpu-embedded-debugging.md` for GPU/embedded-specific tooling, including
  when a profiler like `nsys` succeeds at identifying call order where hand-rolled
  symbol-interception hooks fail outright.
- **Parameter-description mining** — short CLI help strings and doxygen comments often
  encode real algorithmic structure; don't skip reading them just because they're
  terse.

## Black-Box I/O Curve-Fitting: Often Faster Than Reading Disassembly

For a single-stage, stateless computation (a filter, a cast, a quantizer, a simple
arithmetic combine — most of the "leaf" steps in a longer pipeline), fitting a formula
directly from real captured input/output pairs is frequently faster and more reliable
than finding and reading the disassembly, and can reach bit-exact (floating-point
noise floor) results in a handful of iterations:

1. **Capture the actual input and output buffers for one step** — not simulated data,
   the real bytes the target binary produced/consumed. Get the shape/dtype right
   (dimensions, element size, signed/unsigned) by inference from context — neighboring
   steps' known sizes, or an argument struct if one is visible. On a GPU target, this
   usually means building a small custom capture hook (see "CUPTI-Based LD_PRELOAD
   Capture Hooks" in `references/gpu-embedded-debugging.md` — the single most-used
   tool for this across prior sessions, including its dump-timing trap and permission
   requirements); on other targets, the equivalent is whatever call/IPC interception
   mechanism exposes the real argument buffers (a syscall tracer, a library-call
   interposer, a network capture).
2. **Guess candidate formulas from the step's name and position in the pipeline.**
   A name suggesting "filter" + a kernel size strongly suggests a small local-window
   operation; try the obvious candidates first (identity, plain blur, unsharp mask: `src
   + amount*(src - blur(src))`).
3. **Sweep coarse-to-fine.** A broad grid across the *candidate families* first narrows
   down which family is even close (a correct family typically beats the wrong ones by
   several times, not a small margin); then a fine grid on the winning family's own
   parameters (e.g. blur sigma and unsharp amount) until the error bottoms out at the
   noise floor for your numeric precision. Don't forget to sweep boundary-handling mode
   (replicate / reflect / wrap) once the name hints at it — a border-only error spike
   that disappears once you pick the right mode is the tell.

**When this works well:** one clear input buffer, one clear output buffer, a
deterministic/stateless function of that input.

**When it doesn't, and you need tracing/disassembly instead:**
- Hidden cross-cycle/cross-frame state (need several consecutive samples, not one
  input/output pair).
- Several inputs whose respective roles aren't obvious from names alone (trace each
  input's provenance separately before trying to fit anything).
- A step that's one intermediate stage of a longer reduction/aggregation chain, not a
  standalone formula.
- Branching behavior where a handful of input/output pairs can't reveal the full
  decision surface.

## Search Your Own History Before Re-Deriving From Scratch

Before diving into a fresh disassembly or trace of a named function/kernel you
haven't looked at *this session*, search your own prior notes/findings for that exact
name first. It is easy to burn a large number of tool calls fully re-deriving a
formula from zero — locating the right binary/compilation unit among many near-
duplicates, tracing register provenance by hand — only to discover a prior
investigation already reached a more reliable answer (e.g. from live tracing, which
beats static disassembly reading) and also already has a documented "ruled out" list
for tempting-but-wrong alternative hypotheses for that exact function. A fresh pass
isn't wasted — it can corroborate the finding via an independent method and add
detail — but doing the search first reframes the work as "confirm and deepen" instead
of "discover from zero," and avoids nearly reintroducing a conclusion that contradicts
an already-established, higher-confidence one.

## General Debugging & Validation Lessons

- **A decompiled/disassembled function "looking structurally right" is not evidence it
  runs on the path you're actually testing** — especially for a virtual/polymorphic
  method. Code whose logic matches your expected formula exactly can still be dead for
  the specific build/mode under test, reachable only via indirect dispatch whose
  concrete target resolves elsewhere. The cheap, decisive check: set a live breakpoint
  on the function and confirm it's actually hit for the exact input/config you're
  studying. Zero hits (or zero real, non-vtable-slot callers found statically) is a hard
  veto on any conclusion drawn from that function's code, no matter how plausible it
  looks.
- **When several candidates share a superficial pattern** (same call cluster, same
  address range, "looks like the same pipeline stage"), don't assume they're all live.
  Breakpoint the whole cluster in one run and look at hit counts — it's common for only
  a minority of a plausible-looking cluster to ever fire for a given scenario, with the
  rest being compiled-in paths for configurations you aren't exercising.
- **A cleanly-converging aggregate statistic does not prove the per-element computation
  is correct.** An iterative scheme with a wrong per-step divisor can still converge to
  the exact right *total* (each pass re-measures the remaining deficit and silently
  absorbs the error) while the per-element shape is measurably wrong. Check
  element-level structure against a real intermediate buffer separately — don't trust a
  matching final/aggregate number as proof the steps along the way are right.
- **A bug in a recursive or iterative formula can be invisible on short test sequences
  and only surface after many compounding applications.** Validate any temporal-state
  or iterative formula against the longest realistic sequence available, not a short
  representative clip — multiple independently-invisible small errors (an unintended
  precision downgrade, a normalization against a fixed instead of a drifting total, an
  off-by-one that self-corrects over enough iterations) can each pass short tests and
  only compound into a real failure much later.
- **To localize a bug that only appears after many iterations**, don't try to diagnose
  it from the final output. Isolate the smallest sub-sequence that still reproduces it,
  then diff *every* intermediate buffer (not just the final result) against the
  equivalent reference computation at each step, until you find the first exact point
  of divergence. Once you've isolated the diverging buffer, manually reconstructing the
  real formula from finite differences of the raw data at that one point is often
  faster than continuing to guess-and-check whole formula variants.
- **An argument's declared constness or type does not tell you its temporal role.** A
  parameter that reads naturally as "the old/reference value" from its signature (e.g.
  a `const` pointer, suggesting "read-only, i.e. previous state") can in practice be the
  *fresh* current-step input, while the mutable, non-`const` parameter is the
  persistent state being carried forward and overwritten in place. Settle this by
  dumping both buffers across at least three real consecutive steps and checking
  algebraically which one matches which step's raw input and which one matches a
  recursive blend of the previous call's own output.
- **Two samples can't distinguish genuine recursive (IIR) state from a simple two-step
  blend — you need three.** Both look identical on the very first blended step. Confirm
  recursion by checking `state[N] == f(state[N-1], fresh[N-1])` where `state[N-1]`
  is itself an already-blended value, not the raw input at step N-1.
- **A config value's documented range can misrepresent its actual use.** A doc string
  implying a parameter is a fraction (e.g. "range 0–16384" suggesting divide-by-16384)
  can instead be used raw, with no normalization at all, inside the real formula. A
  documented range is often just the UI slider bound, not a normalization divisor —
  verify the real scale via a live trace before curve-fitting against an assumed one.
- **A suspiciously clean fit with one unexplained kink across an otherwise smooth input
  range is a stop signal, not an invitation to try a fancier curve shape.** A kink
  usually means the real mechanism is qualitatively different in that region (a
  discrete clip-and-redistribute step, not a smooth function) — go trace it rather than
  keep fitting.
- **Re-using the same log file path across a batch of runs without clearing it between
  them silently accumulates every run's output into one file**, producing an output
  that looks like one call made many sub-calls when it's actually N separate single
  runs concatenated. Tell: a repeated-event count that suspiciously matches your sweep's
  iteration count. Fix: clear or re-path the log before each individual run whose
  output you intend to read in isolation.
- **A plausible-sounding name is not evidence something is on the path you're
  studying.** Functions/symbols that "sound relevant" by name can belong to a
  completely separate subsystem never invoked by the code path under test. Confirm a
  candidate is actually exercised (a full trace of everything that executes for your
  test input) before investing time reading its logic.

## GPU/Embedded Targets

If the target involves CUDA kernels, Jetson/embedded ARM, or similarly specialized
hardware debugging (Nsight Systems/`nsys` kernel-timeline tracing, cuda-gdb
device-kernel tracing, Ghidra/PyGhidra static analysis, multi-threaded ARM gdb
quirks), see `references/gpu-embedded-debugging.md` for the tool-specific
techniques — defeating LD_PRELOAD-resistant CUDA loaders with `nsys`, stream-aware
kernel-order analysis, breakpoint-warming pitfalls, register float decoding,
kernel-name recovery via the CUDA registration mechanism, and RTTI-based class
recovery in stripped binaries.
