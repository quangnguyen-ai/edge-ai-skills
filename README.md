# Edge AI skills

Agent skills for Embedded AI engineering — from a trained model handed over by research to a pipeline running at budget on the device.

## The lifecycle

```
trained model ──► model-deployment ──► quantization ──► gstreamer-pipeline ──► on device
                  (export, convert,    (FP16/INT8,      (ingest, decode,
                   parity, benchmark)   pruning)         infer, drop policy)
                                                              │
        embedded-debugging ◄── leaks, races, latency spikes ──┤
        gpu-kernel-engineering ◄── a stage is too slow ───────┘
        reverse-engineer-closed-source ◄── match a vendor black box

  edge-benchmark — measures every step above
  cpp-library-design — the C++ library all of it ships in
```

## Edge AI

- **[model-deployment](./skills/edge-ai/model-deployment/SKILL.md)** — PyTorch/TF → ONNX → TensorRT/TFLite: intake, golden reference, export, op triage, engine build, parity, on-target benchmark.
- **[quantization](./skills/edge-ai/quantization/SKILL.md)** — FP16/INT8 (PTQ, QAT, mixed precision) and pruning, gated on the task metric and end-to-end latency.
- **[vision-experiments](./skills/edge-ai/vision-experiments/SKILL.md)** — Comparable, honest image/vision experiments: per-run directories, small samples first, full-res visual judgment, measuring the right path, collaborating on live tests, fixing in code not config.
- **[edge-benchmark](./skills/edge-ai/edge-benchmark/SKILL.md)** — Trustworthy, reproducible timing and accuracy numbers on edge devices: protocol, metrics, what to record, report layout, and accuracy/latency regression tests in CI.

## Embedded

- **[target-workflow](./skills/embedded/target-workflow/SKILL.md)** — Edit on the host, build and run on the board: per-project `target.sh` (rsync + remote build/run + log pull), host-build and `workspace/` scratch conventions.
- **[gstreamer-pipeline](./skills/embedded/gstreamer-pipeline/SKILL.md)** — Low-latency GStreamer video pipelines: RTSP ingest, HW decode, zero-copy, queues and drop policy, appsink/appsrc, tracers.
- **[embedded-debugging](./skills/embedded/embedded-debugging/SKILL.md)** — Leaks, crashes, races, deadlocks, latency spikes on Embedded Linux: where the loop runs, and which tool fits which symptom.
- **[gpu-kernel-engineering](./skills/embedded/gpu-kernel-engineering/SKILL.md)** — Everything CUDA/OpenCL: kernels and the host code around them (RAII buffers/streams, error checks, transfers, CUDA CMake), measurement, optimization ladder, parity.
- **[cpp-engineering](./skills/embedded/cpp-engineering/SKILL.md)** — Production C++: RAII for every handle, checked calls and a no-throw API boundary, owned threads + bounded queues, debug-switch registry, target-based CMake (Linux + Windows), new-project skeleton, review checklist.
- **[cpp-library-design](./skills/embedded/cpp-library-design/SKILL.md)** — General, extensible, navigable, debuggable C++ libraries for edge work (AI inference, GPU image processing, any multi-backend engine): layers, file layout and naming, debug tooling, config/error contracts, design-doc template.
- **[reverse-engineer-closed-source](./skills/embedded/reverse-engineer-closed-source/SKILL.md)** — Reproduce a closed algorithm/binary from input/output behavior alone.

## Communication

- **[onboard-codebase](./skills/communication/onboard-codebase/SKILL.md)** — Learn an unfamiliar repo fast: map, trace one real path, build and run on the target, write CLAUDE.md + overview + glossary + questions for the team.
- **[prompt-coach](./skills/communication/prompt-coach/SKILL.md)** — Turn a weak prompt into one that works first time (goal, context, constraints, done-check, output, example); templates per task type; failure patterns with rewrites.
- **[retro](./skills/communication/retro/SKILL.md)** — Automatic retro every 4 h of session time (hook-driven): finds corrections, approvals, repeats, hard-won lessons and saves them to CLAUDE.md, a skill, or project memory.
- **[token-audit](./skills/communication/token-audit/SKILL.md)** — `/token-audit`: measure what loads every turn (CLAUDE.md, skill descriptions, settings) and the heaviest sessions, then recommend savings.
- **[tech-writing](./skills/communication/tech-writing/SKILL.md)** — Reports and docs in the user's voice: answer first, final results only, no repetition or session history, templates per document type, AI-tell checklist (VI/EN).
- **[diagrams](./skills/communication/diagrams/SKILL.md)** — Technical diagrams that answer one question (data flow, layers, threads/queues, sequence, states, deployment, latency budget, interfaces): brief from a vague request → Mermaid → render → look → fix.

## Works with

The general engineering skills in the [`mattpocock/skills`](https://github.com/mattpocock/skills) fork — `diagnosing-bugs`, `tdd`, `research`, `setup-matt-pocock-skills` (its remote-target execution preset fits on-device work).

## Third-party skills used alongside

- **[drawio-skill](https://github.com/Agents365-ai/drawio-skill)** (MIT) — editable draw.io diagrams, code/IaC → diagram, validation. User-invoked: `/drawio-skill`. Install:
  ```bash
  git clone --depth 1 https://github.com/Agents365-ai/drawio-skill ~/DATA/Projects/third-party-skills/drawio-skill
  ln -sfn ~/DATA/Projects/third-party-skills/drawio-skill/skills/drawio-skill ~/.claude/skills/drawio-skill
  ```
  Needs the draw.io desktop CLI on `PATH` as `drawio` (AppImage from the jgraph/drawio-desktop releases, checksum-verified; wrapper passes `--disable-gpu --no-sandbox` after the input and finds an X display, or uses `xvfb-run` if installed). Check with `python3 ~/.claude/skills/drawio-skill/scripts/diagramctl.py doctor`.

## Install

```bash
git clone <this repo> ~/DATA/Projects/edge-ai-skills
cd ~/DATA/Projects/edge-ai-skills
./install.sh --dry-run            # see what would change
./install.sh --with-drawio        # skills + CLAUDE.md + settings (+ draw.io)
```

`install.sh` links every skill, symlinks `~/.claude/CLAUDE.md` to `config/claude/CLAUDE.md` (so edits travel with git), merges `config/claude/settings.fragment.json` into `~/.claude/settings.json` without overwriting existing keys (model, connectors, skill overrides, retro hooks), and with `--with-drawio` installs the pinned draw.io skill, the checksum-verified AppImage, the `drawio` wrapper and the `soft` preset. Anything it replaces is backed up as `*.bak-<timestamp>`; re-running changes nothing. Machine-specific settings (auto-mode environment, plugins, MCP) are left alone. The upstream `mattpocock/skills` fork is installed separately with its own `scripts/link-skills.sh`.
