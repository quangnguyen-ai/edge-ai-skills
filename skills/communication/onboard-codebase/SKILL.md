---
name: onboard-codebase
description: Get productive in an unfamiliar repo fast — map it, trace one real path, build and run it on the target, then leave a CLAUDE.md, overview with diagram, glossary, and questions for the team. Use when the user joins a new project, opens a repo they don't know, asks how a codebase works or where something lives, or wants a CLAUDE.md written for a repo.
---

# Onboard a codebase

Goal: in one or two sessions, be able to answer **how do I build and run it, where does the data go, where does config come from, how is it tested, who owns what** — and write those answers into the repo so no session has to rediscover them.

Don't read everything. Map, then follow one real path, then run it.

Onboarding notes are company-internal: they live in the company repo (or locally), never in a personal or public repo. Write files; commit only when the user asks.

## 1. Scope

Ask (or infer) which part matters first: the whole repo, or the subsystem the user will work on. Name it in one line. Skip vendored code (`third-party/`, `external/`, submodules), build outputs, and scratch areas (`workspace/`).

## 2. Map — mechanical, fast

Collect, without deep reading:

- **What it says about itself**: README, `docs/`, existing `CLAUDE.md`/`AGENTS.md`/`CONTRIBUTING`, MR/PR templates (`.gitlab/merge_request_templates/`, `.github/`).
- **How it is really built and tested**: CI config first (`.gitlab-ci.yml`, `.github/workflows/`, Jenkinsfile) — it is the most reliable source of the real commands. Then CMake/Makefile/`setup.py`/`pyproject.toml`, Dockerfiles, `scripts/`.
- **Shape**: directory tree two levels deep with line counts per directory (`tokei`/`cloc` if present, else `find … | xargs wc -l`).
- **History**: `git log --oneline -20`; most-changed files (`git log --since=6.months --format= --name-only | sort | uniq -c | sort -rn | head -20`); who knows each area (`git shortlog -sn --since=1.year -- <dir>`).
- **Conventions**: `.clang-format`/`.clang-tidy`, test framework, logging and error-handling style, commit message style from the log, branch naming.

Done when there is a table: directory → role (one line) → key files → owner.

## 3. Trace one real path

Pick the path the product exists for — one frame from capture to result, one inference call through the public API, one request end to end. Follow it through the code from entry point to output, noting for each hop: file:function, the data format, where it runs (host/device/thread), and where its config comes from. Stop at well-named library boundaries.

Done when the path can be told as 5–12 hops with file references, and every config value on it is traced to where its default lives.

## 4. Build and run it

Use the CI command, on the real target (the `target-workflow` skill: sync, build on the board, run). Run the smallest meaningful check: the unit tests, or one sample input through the main binary. Record the exact commands that worked. A failure is a finding: note the error and turn it into a question — don't silently patch build files in someone else's repo.

Done when one build and one run have succeeded on the target (or the blocker is written down with its error).

## 5. Write it down

Four outputs, in the repo's language and conventions. Merge into existing files, never overwrite them.

1. **`CLAUDE.md`** (or the repo's `AGENTS.md`) — from [references/claude-md-template.md](references/claude-md-template.md): build/run/test per target, layout, conventions, verification rules, what not to touch. Short — it is read every session.
2. **Overview doc** — the `tech-writing` skill's Overview template, with one diagram from the `diagrams` skill (layers, or the traced data path).
3. **Glossary** — internal terms, acronyms, product and board names → meaning → where in the code. Use `CONTEXT.md` if the repo follows that convention.
4. **Questions for the team** — each one specific and grounded: what you found (file:line), what is unclear, why it matters. "X is set in `a.cpp:120` and `b.json`; which wins in production?" — not "how does config work?".

## Completion

Done when, from the written files alone, a new session can answer: how to build for each target; where the main data enters and leaves; where config is loaded and defaults live; how to run the tests; who to ask about each area — and the open questions list exists. Report to the user what was written where, and the top 3 questions.
