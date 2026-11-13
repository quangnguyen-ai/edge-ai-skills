---
name: retro
description: Review a stretch of a working session and save what is worth keeping — corrections, approved approaches, repeated requests, hard-won technical lessons — into the right place (global CLAUDE.md, a skill, or project memory). Runs automatically every few hours via a hook, or on request. Use when a "[retro]" instruction appears in context, or the user asks for a retro, a session review, or to save what was learned.
---

# Retro

Turns a session into durable knowledge without the user having to remember to ask. A hook (`scripts/retro_timer.py`) starts a clock at the session's first prompt and, every 4 hours (or at the next session if one ends early), injects a `[retro]` instruction naming the transcript and time window. Run it **after** fully answering the user's current message, as a short closing section — the user's request always comes first.

## 1. Read the window

```bash
python3 ~/.claude/skills/retro/scripts/extract_transcript.py "<transcript>" --since <ISO> --until <ISO> > <scratch>/retro.md
```

Read `retro.md`: user prompts in full, assistant prose shortened, tool calls as one-line markers. When run by hand with no window, use the whole current session's transcript.

## 2. Find candidates

Look for exactly these signals:

| Signal | Example | Save |
|---|---|---|
| Correction or rejection | "không phải vậy", "đơn điệu quá", "hỏi t trước khi code" | the rule + why |
| Approval of a non-obvious choice | "ổn rồi", "hay", "đúng rồi" after a judgment call | what worked |
| A request made twice | same preference stated again | the preference — it should have stuck |
| Hard-won technical lesson | root cause after a long hunt, a measurement trap, a tool gotcha | the lesson, generalised |

Ignore routine progress, one-off task details, anything already in code or git history, and guesses.

## 3. Check before writing

For each candidate, search where it would live: `~/.claude/CLAUDE.md`, the project's memory (`MEMORY.md` + files), and the skills in `~/DATA/Projects/edge-ai-skills` (`grep -ri`). Already recorded → skip, or update if the new instance adds something. Contradicts an existing entry → update the entry, note the date.

## 4. Save in the right place

- **How the user likes to work, everywhere** → `~/.claude/CLAUDE.md`, in the matching section, one line each.
- **Reusable engineering knowledge** → the matching skill in `edge-ai-skills` (no company, product, board, IP, or person names), then `scripts/check-skills.sh`. Test: would this hold in a different project with a different algorithm and sensor? If it only makes sense for this project's algorithm, data, or pipeline, it goes to project memory instead — removing the names doesn't make it general.
- Within `edge-ai-skills`, split by kind: **procedure** (what to check or do, in order) → the matching skill, kept short; **special knowledge** (non-obvious hardware/SDK limits, surprising behaviour, error messages that point to a cause — no measurement numbers) → `docs/knowledge/<topic>.md` with date, context and an evidence label (**[measured]**, **[docs]**, **[assumption]**), linked from the skill. Edit an existing fact and bump its date rather than appending a contradiction.
- **Facts true only for this project** → the project's memory (one file per fact + a line in `MEMORY.md`).

Never save credentials, passwords, tokens, or private data that appeared in the session.

Apply clear-cut items directly. Items that are ambiguous, or that would change a skill's behaviour substantially, become proposals: ask once at the end (one multi-select question), apply what the user picks.

## 5. Report

At most ~10 lines, in the user's language:

```
**Retro HH:MM–HH:MM**
Đã lưu: <item> → <where> · <item> → <where>
Đề xuất (chưa lưu): <item> — <where>?
```

Nothing worth saving → one line: "Retro HH:MM–HH:MM: không có gì mới cần lưu."

## Completion

Done when every candidate from the window is saved, skipped as already recorded, or listed as a proposal; no duplicate entries were created; nothing secret was written; and the report is shown.

## Tuning

Env vars read by the hook: `RETRO_INTERVAL_HOURS` (default 4), `RETRO_MIN_PROMPTS` (8) and `RETRO_MIN_MINUTES` (30) for the end-of-session carry-over, `RETRO_DISABLE=1` to turn it off. Hooks live in `~/.claude/settings.json`; `/hooks` shows them.
