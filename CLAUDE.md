Generic, company-independent skills for Embedded AI engineering: taking models to edge devices, video pipelines, and system-level work on Embedded Linux / Jetson / ARM SoCs.

Skills live in bucket folders under `skills/`:

- `edge-ai/` — model lifecycle: export, conversion, quantization, deployment
- `embedded/` — systems work on the device: video pipelines, GPU kernels, debugging, reverse engineering, library design
- `communication/` — reports, docs, and diagrams
- `in-progress/` — drafts, not linked into the README or plugin
- `deprecated/` — no longer used, not linked anywhere

`edge-ai/`, `embedded/`, and `communication/` are the **promoted** buckets: every skill in them must have an entry in the top-level `README.md` (name linked to its `SKILL.md`) and in `.claude-plugin/plugin.json`. Skills in `in-progress/` and `deprecated/` must appear in neither. Run `scripts/check-skills.sh` after adding, moving, or renaming a skill — it enforces these rules.

## Writing skills

Follow the `writing-great-skills` skill (from the `mattpocock/skills` fork in `../skills`). In short:

- All skills here are **model-invoked** (no `disable-model-invocation`). The `description` lists distinct triggers, one per branch — no synonym lists. Keep it under ~450 characters: it sits in context every turn.
- Steps end on a checkable completion criterion. Push material only some runs need into `references/*.md` behind a pointer.
- Cross-skill dependencies are prose (`the \`quantization\` skill`), never `../other-skill/` links.
- Projects follow the `target-workflow` conventions: build/run on the board via `target.sh`, host builds only when asked, `workspace/` is uncommitted scratch.
- Skills that run, build, or measure anything read `docs/agents/execution-environment.md` in the working repo (written by `/setup-matt-pocock-skills`) and fall back to "give the user the command, work from pasted output" when execution is remote-only.

## Skills vs knowledge

- `skills/` hold **procedure**: what to check and do, in order, short. Loaded when the skill triggers.
- `docs/knowledge/` holds **special knowledge only**: non-obvious hardware/SDK limits, surprising behaviour, error messages that point to a cause — **no measurements or benchmark numbers** (they stay in the project that produced them) — each file dated, with SDK/device in the header and an evidence label per claim (**[measured]**, **[docs]**, **[assumption]**). Skills link to them; `scripts/check-skills.sh` fails on broken relative links.
- Rule of thumb: an instruction is a skill; a non-obvious lesson with its context and date is knowledge; a number is neither — it belongs to the project's report.

## Confidentiality

Skills are generic know-how. Never put employer- or customer-specific material in this repo: internal model names, product codenames, hostnames, datasets, customer footage, or measured numbers from company products. Project-specific detail belongs in the work repo itself (its own notes file or a project-local skill).

## Installing

`./install.sh` sets up a machine (skills, global CLAUDE.md, settings fragment, optional draw.io) — see the README. Personal config lives in `config/`: when you change `~/.claude/settings.json` hooks or skill overrides, copy the change into `config/claude/settings.fragment.json` too (`~/.claude/CLAUDE.md` is a symlink into `config/` once installed). Never put `autoMode` or other company-specific settings in `config/`.


`scripts/link-skills.sh` symlinks every non-deprecated skill into `~/.claude/skills` and `~/.agents/skills`, and removes stale links that point into this repo. Re-run it after adding, removing, or renaming a skill.
