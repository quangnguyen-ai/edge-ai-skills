---
name: vision-experiments
description: Run iterative image/vision experiments that stay comparable and honest — hypothesis tests, parameter sweeps, algorithm or port comparisons, image-quality judgments, fixing visual defects. Use when the user wants to try a hypothesis, sweep parameters, compare algorithms or a port against a reference, judge image quality, or fix an artifact (ghosting, halos, blow-out, flicker, noise).
---

# Vision experiments

The goal is **understanding the mechanism**, not a lower number. A metric is evidence for or against a hypothesis; a metric that improves on one scene but doesn't generalize, or doesn't correspond to a plausible mechanism, is not a win.

## 1. Set up so runs stay comparable

- **One directory per experiment**: `experiments/<YYYYMMDD_HHMMSS>_<short-name>/` (or the repo's scratch area, e.g. `workspace/`). Never overwrite an earlier run. Each holds the command, the config, the metrics, and the images.
- **Outputs in a stable repo-relative path**, not a session temp dir — the user reuses them across turns.
- **Small sample first** (20–100 frames, strided or contiguous) until a variant looks promising; the full dataset only as the final validation.
- **Stream to disk**: per frame, write output, reference, and a side-by-side comparison with the metric annotated, then update running sums. Never accumulate full-resolution arrays in a list for a final stats pass — it is how eval scripts OOM a shared machine. Use the smallest safe dtype for diffs; isolate long sweep combinations in subprocesses.

Done when the experiment directory exists with a README line stating the hypothesis being tested.

## 2. Make sure you are measuring what you think

Each of these has produced a confidently wrong conclusion:

- **Inputs from the same run.** Dumps, intermediate files, and references must come from the run being compared. A stale dump from an earlier run (or a `/tmp` cleared by a reboot and refilled) silently belongs to different data.
- **The path under test actually executes.** A flag or default can bypass the stage entirely (a passthrough that still looks plausible). Confirm with a stage dump, a log line, or timing that the code path ran.
- **Check the reference is what its name says.** Before judging "looks like the device", confirm a reference capture really came from the device: a "device original" that matches your own output almost exactly (SSIM ≈ 0.99, far closer than port vs device ever is) is an old dump of your own output. Record where each reference came from next to it.
- **Stateful references are fed in order.** If the reference (or the port) carries temporal state (EMAs, damping, history), run the whole sequence through one instance and compare at checkpoints — never isolated frames.
- **Know the expected residual.** Measure the normal difference between a correct port and its reference (border handling, histogram vs exact percentiles, float order) and how it scales with contrast/gain, before calling anything a bug. Compare both sides at identical effective parameters.
- **Temporal artifacts (flicker, pumping) need temporal metrics.** A whole-frame mean hides them. Track per-frame percentiles (p50/p90/p99) of the output next to the input's extremes (max vs a high percentile — a few hot pixels move the max, not p99.5), over a capture long enough to catch the trigger, and mask on-screen overlays (fps text) first. Then bisect by replaying that capture through builds of older commits.
- **One difference per comparison.** Build configs that differ in exactly one flag, run them all, compare each against an identically configured reference. It localizes a discrepancy in one pass.

## 3. Judge images properly

- The user judges quality by looking. Every reported result includes images, not just numbers.
- **Final judgments on full-resolution individual images**, one at a time. Contact sheets and downscaled grids are for coarse screening across many candidates only — they hide posterization, crushed shadows, blotchy local contrast, and fine artifacts.
- Check the hard cases: a bright and a dark object (halos), flat regions (noise, blocking), motion (ghosting), extreme scene content (a hot or saturated source), and the reference output when one exists.

## 4. Collaborate instead of auto-probing

When the user has the camera and real scenes, they can settle a hypothesis in one live run faster and more truthfully than a long offline sweep (offline captures often lack the real motion or content).

- State the hypothesis, hand over **one discriminating command** (configs pre-staged on the device), and say exactly what to look for.
- Ask about the artifact's shape, location, and duration rather than guessing from metrics.
- Keep self-run measurement for what the user can't easily observe: GPU timing, absolute numeric metrics, confirmation after the cause is localized.
- Before proposing a fix or new design, trace it through the cases (static, moving, converging, extreme input) and state its limits up front.

## 5. Fix in code, not in config

- A defect fix is a code change that works with the **shipped configs unchanged**. "Set key X to Y" is not a fix; neither is a new knob that defaults to off.
- Using a temporary config key as an **instrument** to sweep for the right internal constant is fine — then hard-code the measured value as the default, derive it from a model already in the code where possible, and record the sweep in the comment.
- Guards for extreme inputs: pick strength from a measured trade-off table (benefit on the extreme case vs disturbance on normal frames), not from a textbook constant.
- When a default changes behaviour, say which tuned parameter sets need revisiting.

## Completion

Done when the experiment directory holds the hypothesis, command, config, metrics, and full-resolution images; the conclusion states the mechanism (or which hypotheses were ruled out, each by measurement); and anything not verified (scenes, devices, live vs offline) is listed.
