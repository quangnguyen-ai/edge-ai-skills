---
name: prompt-coach
description: Diagnose and rewrite a weak prompt into one that gets the right result first time — goal, context, constraints, done-check, output, example — and teach the pattern. Use when the user asks to improve, rewrite, or review a prompt, asks how to phrase a request to Claude, wants a prompt template for a task, or a request went wrong and they ask how they should have asked.
---

# Prompt coach

A prompt works when a capable colleague with no context could do the task from it. Most prompts that go wrong miss one of six things — and the user is not expected to remember them. This skill finds what is missing, fills what it can from context, asks only for what it can't, and hands back a better prompt.

Reply in the user's language; keep prompts in the language the user works in (Vietnamese prose, English technical terms).

## The six parts

| Part | Question it answers | Typical gap |
|---|---|---|
| **Goal** | What should exist or be true afterwards — and why? | "làm cái này tốt hơn" with no definition of better |
| **Context** | Which repo, files (`@path`), board, data, prior decision? | "chuyển vào phần đó" — which part? |
| **Constraints** | What must not change? Style, budget, scope limits? | config must stay unchanged; don't commit |
| **Done-check** | How will we know it worked — test, number, image, command? | no verification, so "looks done" is the only signal |
| **Output** | What form, where saved, what language, how long? | report vs chat answer; file path |
| **Example** | Is there a sample of the desired result? | describing a look in words instead of pointing at a file that has it |

The example beats description: one reference file ("box kiểu như file này") settles what three rounds of adjectives ("trung tính", "đơn điệu quá") could not.

## Fix a prompt

1. **Restate** the intent in one sentence. If two readings are plausible, say both.
2. **Check the six parts.** For each gap, try to fill it from the conversation, the repo, CLAUDE.md, and memory first — most gaps are fillable.
3. **Ask only for what can't be filled and would change the result** — at most 2 questions, each with concrete options (use the question tool when available).
4. **Return**:
   - the rewritten prompt in a copyable block, short — add only what was missing, keep the user's words where they were fine;
   - 1–3 bullets: what was added and why (named by the part: *Done-check: …*);
   - an offer to run it now.

Done when the rewritten prompt passes the colleague test: every one of the six parts is either present or genuinely not needed for this task.

Templates per task type (bug, feature, optimization, experiment, report, diagram, review, question, onboarding): [references/templates.md](references/templates.md). Failure patterns and their fixes, with examples: [references/failure-patterns.md](references/failure-patterns.md).

## Session habits worth suggesting

Only when relevant to what just happened — never as a lecture:

- Unrelated new task → `/clear` first; a long mixed session degrades results.
- Corrected the same thing twice → `/clear` and restart with a prompt that includes what was learned; a fresh session with a better prompt beats a third correction.
- Multi-file or unclear approach → ask for a plan first (plan mode), code after approval.
- Big feature with open questions → have Claude interview you (the `grilling` skill) and write a spec, then implement in a fresh session.
- Point at files with `@path`, paste images and error logs directly, give the command that proves success.
- `Esc` to stop and redirect early; `Esc Esc` / `/rewind` to roll back.

## After a misunderstanding

When a request was misread and had to be redone, add one line at the end of the reply: *"Lần sau có thể nói: …"* — the shortest version of the prompt that would have worked. Once per misunderstanding, never for prompts that worked.
