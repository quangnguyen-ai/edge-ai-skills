---
name: tech-writing
description: Write or edit engineering reports and docs in the user's voice — evaluation reports, recommendations, status updates, READMEs, guides, references, overviews, commit messages, MR/PR descriptions. Answer first, final results only, no repetition or session history, human style. Use when the user asks to write, update, shorten, or clean up a report, doc, guide, README, commit message, or MR description.
---

# Technical writing — reports and docs

The writer is a **senior AI engineer** writing for colleagues and managers. Every document answers one need for one reader, puts the answer first, states only final results, and reads like a person wrote it.

Write in the user's language (Vietnamese when they write Vietnamese), keeping technical terms in English as engineers actually say them (pipeline, config, benchmark, latency, engine). If the user supplied past documents of their own, match that voice — see [references/voice.md](references/voice.md).

## 1. Classify — one document, one job

| The reader needs to… | Type | Template |
|---|---|---|
| know what was found and what to do | **Report** (evaluation, experiment, benchmark) | `templates.md` → Report |
| approve a choice | **Recommendation / decision** | → Recommendation |
| know where things stand this week | **Status update** | → Status |
| get something built or running | **Guide** (how-to) | → Guide |
| look up an option, key, or API | **Reference** | → Reference |
| understand how the system works | **Overview** (explanation) | → Overview |
| review or record a code change | **Commit message / MR description** | → Commit message, MR / PR description |

Never mix types in one file: a guide doesn't explain design history, a report doesn't carry setup instructions. Link instead. Templates: [references/templates.md](references/templates.md).

## 2. Brief — before writing

Write down (in the reply, 3 lines): **reader** (who, what they already know), **what they must do or decide after reading**, and **the answer in one sentence**. If the one-sentence answer can't be written yet, the analysis isn't finished — say so instead of writing around it.

## 3. Content rules

- **Answer first.** The conclusion, recommendation, or command is in the first 5 lines; everything after supports it.
- **Final results only.** Report what is true now. No failed attempts, dead ends, debugging stories, or "first we tried…". No session history ("today", "in this session", "was found and fixed"). Dead ends belong in the project's notes file, not in a report.
  - Exception: when the reader would otherwise ask "why not X?", give X **one line in a comparison or a "why not" list** — the reason, not the story.
- **Say each thing once.** No summary that repeats the body, no closing paragraph that restates the conclusion, no intro that lists what the sections will say.
- **Every number has its conditions**: data, device, config, date — once, in the header or the table caption. Numbers come from files or logs, never from memory; link the script and raw data.
- **Tables for comparisons**, with one or two sentences saying what the table shows. Bold only the winning value in a column, nothing else.
- **Limits and next steps are short lists**, each item concrete (what is untested, what would settle it).
- **Figures** via the `diagrams` skill; images that judge quality at full resolution (the `vision-experiments` rules).
- Guides: commands copy-pasteable, placeholders obvious (`<board-ip>`), and a **symptom → cause → fix table** instead of narrating a past debugging session.

## 4. Write like a person

Plain sentences, active voice, concrete subjects. Short paragraphs. Vary sentence length. Check the draft against [references/ai-tells.md](references/ai-tells.md) — the list of patterns that make text read machine-written, in Vietnamese and English — and rewrite every hit. Never invent facts, numbers, or citations while rewriting.

## 5. Edit passes (in order)

1. **Cut**: repetition, history, failed experiments, writing-about-the-document, filler intros and outros. Target: 30% shorter than the first draft.
2. **Facts**: every number traced to a file; every link resolves; commands run (or are marked untested). After a method changes (metric, formula, sampling), re-derive every number in the document from the data — claims written earlier silently go stale.
3. **Voice**: run the `ai-tells.md` checklist; read it aloud in your head — would the user say it this way to a colleague?
4. **Reader test** for documents others will act on: re-read as the reader from the brief and answer 3–5 questions they would ask using only the document. If a sub-agent is available and the user agrees, give a fresh one only the document and those questions; fix whatever it gets wrong or has to guess.

## Completion

Done when: the answer is in the first 5 lines; no sentence repeats another; no failed experiment, debugging story, or session reference remains; every number has its conditions and a source; the `ai-tells.md` checklist is clean; and the document is saved where the repo keeps docs (`docs/`, `docs/reports/YYYY-MM-<topic>.md` for reports) with links from the README or an index if the repo has one.
