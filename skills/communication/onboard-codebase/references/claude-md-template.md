# CLAUDE.md template for an embedded / edge repo

Keep it under ~80 lines: it loads into every session. Link to docs for anything longer. Delete sections that don't apply.

```markdown
<One or two lines: what this repo is, what it produces (library / app / service), for which targets.>

## Build & run

Built and run on the target board, not on the dev host.

| Target | Build | Notes |
|---|---|---|
| <board / SoC> | `<exact command>` | <options that are silently wrong when omitted> |

- Host → board loop: `./target.sh up`, `./target.sh run "<cmd>"` (see the `target-workflow` skill).
- Smoke test: `<command>` — expected: <what success looks like>.
- Tests: `<command>`.
- Stop before running camera tools: `<service names>` (ask first).

## Layout

| Path | Role |
|---|---|
| `include/` | public API |
| `src/…` | … |
| `config/` | profiles; defaults live in `<file>` |
| `tests/`, `tools/` | … |

Not code: `workspace/` (scratch, never committed), `third-party/` (vendored, don't edit), `build*/`.

## Conventions

- Naming: <one token per concept across config key / class / file / kernel>.
- Errors: <no exceptions across the API / error codes / last_error()>.
- Logging: <logger, levels, env vars that enable debug output>.
- Style: `.clang-format` at the root; <other rules>.
- Commits: <message style from the log, e.g. `area: imperative summary`>; no assistant attribution.

## Verification before a change is done

- <bit-exact check / golden test / stage bench / parity tool and how to run it>.
- Numbers in reports and MRs: measured on the board, with config and commit.

## Git

<commit / push / MR policy, e.g. never commit or push without an explicit go-ahead.>

## Docs

- Overview: `docs/<overview>.md` · Glossary: `CONTEXT.md` · Open questions: `docs/onboarding-questions.md`
```
