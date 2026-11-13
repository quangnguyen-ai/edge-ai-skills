---
name: token-audit
description: Audit Claude Code token use — what loads every turn, the heaviest sessions, costly settings — and recommend concrete savings.
disable-model-invocation: true
---

# Token audit

Run occasionally (monthly, or when usage limits bite). Measure first, then recommend; change nothing without the user's yes.

## 1. Measure

```bash
~/.claude/skills/token-audit/scripts/audit.sh "$PWD"
```

Reports: always-loaded instruction files (CLAUDE.md, memory index) with sizes; every model-invoked skill description and their total per turn; cost-relevant settings (model, effort, prompt suggestions, connectors, skill overrides, plugins, hooks); the largest recent session transcripts. Also ask the user to run `/context` (what fills the window now) and `/usage` (cache hit rate, attribution by skill/MCP/subagent) and paste the result if they want it included.

## 2. Find the waste — biggest first

| Where | Signal | Fix |
|---|---|---|
| **Long mixed sessions** | many compactions, weeks of prompts, unrelated tasks in one session (transcript size on disk is only a hint — it includes images and /rewind snapshots that never reach the model) | `/clear` between unrelated tasks (`/rename` first to resume later); start a task with a precise prompt instead of correcting repeatedly |
| **Model** | Opus as the default for routine edits | Sonnet by default, Opus for hard design/debugging (`/model`); lower `/effort` for simple tasks |
| **Tool output in context** | long build/test/log output pasted in full | filter to errors + tail, keep the full log on disk (`target.sh` does this); a PreToolUse hook can rewrite test commands to print failures only |
| **Exploration** | many files read to answer a narrow question | scope the question, grep first, read ranges; delegate broad searches to a subagent so only the summary returns |
| **Always-loaded instructions** | CLAUDE.md growing past ~200 lines; workflow-specific detail in it | move workflow detail into skills (loaded on demand); keep CLAUDE.md to rules that apply every session |
| **Skill descriptions** | model-invoked skills never used in this work | `skillOverrides` → `"user-invocable-only"` (still available as `/name`) or `"off"`; shorten descriptions to distinct triggers |
| **MCP / connectors** | servers or claude.ai connectors not used | disable in `/mcp`; `disableClaudeAiConnectors: true` if none are used; prefer CLIs (`gh`, `glab`) over MCP servers |
| **Cache misses** | first message after a long break re-reads the whole context | resume big sessions from a summary, or `/clear` after breaks longer than the cache lifetime |
| **Background turns** | scheduled loops, idle check-ins, cross-session messages on a large session | stop loops when done; keep them in small sessions |

## 3. Recommend

Give a short table: change → expected saving (per turn or per session) → trade-off. Put changes that alter behaviour (default model, disabling connectors or skills) as choices for the user; apply only what they pick, through the `update-config` skill for settings.

Done when the measurements are shown, each recommendation names its saving and trade-off, and only approved changes were applied.
