---
name: target-workflow
description: Work in a project that is edited on a dev host and built/run on an embedded board over ssh — set up and use the per-project sync script (rsync + remote build/run + log pull), respect the host-build and workspace/ scratch conventions. Use when setting up a new project for a board, syncing or deploying code to a target, building or running on the device, or when a repo has target.sh or a workspace/ folder.
---

# Host → target workflow

Code is edited on the host and **built and run on the board**. Every project carries one script, `target.sh`, that closes that loop in single commands — so the agent can run it instead of asking the user to copy-paste.

## Conventions

- **Build on the target, not the host.** The host may be able to compile (an x86 build dir may exist), but it is not the preferred path: don't build on the host unless the user asks for it. The truth is the board's toolchain, SDKs, and libraries.
- **`workspace/` is scratch.** Experiments, captured data, datasets, model files, third-party clones, notebooks, logs — gitignored, never committed, never synced to the board.
  - Don't search it when looking for project code, and don't edit it unless asked. A nested repo inside it (its own `.git`) is a separate project with its own rules.
  - Put new experiments, throwaway scripts, and scratch outputs there, not in the source tree.
  - When a result from `workspace/` matters (a measurement, a decision), record it in `docs/` — the scratch copy can disappear.
- **Commit/push policy** is whatever `docs/agents/execution-environment.md` says; this skill never changes it.

## Set up a project (once)

1. Pick the board's `Host` in `~/.ssh/config` and confirm key login works: `ssh <host> true` returns without a password prompt. If not, stop and ask the user.
2. Copy [scripts/target.sh](scripts/target.sh) to the project root (`chmod +x`), and [scripts/target.env.example](scripts/target.env.example) to `.target.env.example`. Fill a `.target.env` with the user's host, remote dir, and the project's build command for that board.
3. `.gitignore`: add `.target.env`, `logs/`, `workspace/` (if missing). Project-specific sync exclusions go in `.targetignore` (rsync exclude patterns).
4. `./target.sh check` (set `TARGET_HOSTNAME` so a shifted IP can't land on another board), then a dry run: `./target.sh sync -n` — check the list contains only source/config/assets the board needs (no builds, data, `workspace/`).
5. Add to the project's `CLAUDE.md` a **Build & run** section: `./target.sh up`, the main run commands, which board(s), anything that must be stopped first (e.g. a service holding the camera).
6. Allow `./target.sh` in the project's Claude permissions so the loop doesn't prompt every call.

Done when `./target.sh up` builds on the board from a clean sync and `./target.sh run "<smoke test>"` exits 0 with its log in `logs/`.

## Use

- After editing: `./target.sh up` (sync + build). Read the compiler errors from the output and fix them before anything else.
- Run: `./target.sh run "<command>"` — output is saved to `logs/run-<timestamp>.log`; cite that file when reporting.
- Results (images, dumps, profiles): `./target.sh pull <remote path>` → `logs/pulled/`.
- If the board is unreachable or the script is missing, fall back to the remote-only mode: give the user the exact commands and work from pasted output.

Read [references/board-gotchas.md](references/board-gotchas.md) when ssh, a build, or a board behaves strangely, and before committing from a tree that also holds other people's uncommitted edits.

**Ask before** anything that changes the board beyond `TARGET_DIR`: stopping/starting services, changing clocks or power modes, installing packages, rebooting, `SYNC_DELETE=1`. Restore board-wide settings afterwards.
