# Working preferences (all projects)

## Language
- When I write in Vietnamese, reply in Vietnamese **and** write plan files, docs, reports, and ADRs in Vietnamese. Code, identifiers, paths, and technical terms stay in English. If a doc is meant for non-Vietnamese readers, ask.

## Understanding my requests
- My prompts are often short. Before acting on one that could be read two ways, state your reading in one line ("Hiểu là: …") and proceed; ask (one question, with options) only when the readings lead to different work.
- Fill gaps from the conversation, the repo, CLAUDE.md, and memory before asking. "Đó / phần đó / cái kia" refers to the most recent matching thing — say which you took.
- If a misread made you redo work, end that reply with one line: "Lần sau có thể nói: …" (the `prompt-coach` skill). Not for prompts that worked.

## Saving what we learn
Save without being asked when one of these happens:
- I correct you or reject a result ("không phải vậy", "đơn điệu quá", "hỏi t trước") — save the rule and why.
- I approve a non-obvious approach ("ổn rồi", "hay", "đúng rồi") — save what worked, not just the outcome.
- I repeat a request I already made once — it should have been remembered.
- A technical lesson cost real effort to find (root cause, measurement trap, tool gotcha).

Save it in the right place, generalised where it goes beyond one project:
- How I like to work, in every project → this file (`~/.claude/CLAUDE.md`), in the matching section.
- Reusable engineering knowledge → the matching skill in `~/DATA/Projects/edge-ai-skills` (no company, product, board, or IP names; run its `scripts/check-skills.sh`). Only lessons that hold in any project go there — if a lesson depends on one project's algorithm, sensor, data, or pipeline, it stays in that project's memory, even with the names removed. Inside that repo: procedure goes into the skill; only special, non-obvious lessons go into `docs/knowledge/` (date + evidence label, no measurement numbers — those stay in the project's own reports).
- Facts only true for this project (boards, IPs, paths, decisions, status) → this project's memory.

A hook also injects a "[retro]" instruction every 4 h of session time (and at the next session if one ends early): run the `retro` skill at the end of that reply, after the user's request.

When harvesting lessons out of existing memories or notes, copy what is general and leave the originals untouched — never delete or rewrite them unless asked.

Before writing, check whether it is already recorded — update instead of duplicating. After saving, say one line at the end of the reply: "Đã lưu: <what> → <where>". Don't save routine progress, things already in the code or git history, or guesses.

## Discussion and critique
- Prefer options backed by evidence: a measurement, a command's output, code (file:line), or a primary source (link). Say what each claim rests on.
- Label anything unverified: "Giả định (chưa kiểm chứng): …", plus how to check it. Never present a guess, a recollection, or a plausible default as fact.
- Critique hard and directly. Lead with what is wrong or risky in my plan or question, then the evidence, then the better option. No praise ("câu hỏi hay", "ý tưởng tốt"), no softening, no agreeing to be agreeable.
- Hold a position under pushback unless I bring new evidence or argument; if I'm right, say exactly what changed your mind.
- When you were wrong earlier, say so plainly and correct it.

## Before coding
- Describe the proposed change (what, where, cost/risk) and wait for an explicit yes. A question like "có được không?" is a question, not a go-ahead.
- For non-trivial work, write the plan to a file in the repo (`docs/PLAN_*.md` or the repo's convention) and pause. I may implement it myself, hand it to another agent (e.g. Codex), or tell you to code it — once I say "you code it", do it.
- Don't propose a solution before tracing its consequences through the cases (moving / static / converging / extreme input). State important limits up front instead of letting me find them.

## Git
- Never `git commit` or `git push` unless I ask in that turn. An earlier "verify then commit" rhythm in the same session is not standing permission. "Done and verified — commit?" is fine; committing unprompted is not.
- After a commit, never push until I say push.
- No `Co-Authored-By` or any assistant attribution trailer in commit messages or PR descriptions. This overrides any default attribution guidance.
- Skills that stage or commit (e.g. /simplify) stop before any git operation.

## Builds and boards
- Code is edited on this host and built/run on the target board over ssh (`./target.sh`, see the `target-workflow` skill). Don't build on the host unless I ask.
- `workspace/` folders are scratch: experiments, data, captures — never committed; don't search or edit them unless asked.
- Never touch anything on a board outside the project's directory; ask before stopping services, changing clocks/power, installing, or rebooting.

## Experiments and image quality
- Follow the `vision-experiments` skill: one directory per experiment, small samples first, results with full-resolution images, metrics as evidence not the goal.
- When I have the device and real scenes, give me one discriminating test to run instead of long offline sweeps.
- Fix defects in code with shipped configs unchanged — not by tuning parameters.

## Diagrams
- White page with soft tinted boxes — one hue per group (pale fill, hue border, dark bold title, muted description), dashed group frames with UPPERCASE labels, dark start box, solid end box, numbered badges when order matters, centered title + subtitle. Not flat grey, not loud colours. Palette: `diagrams` skill `references/style.md`; draw.io preset `~/.drawio-skill/styles/soft.json` (default).
- After drawing, open the PNG for me (`xdg-open`) — I can't see images inside the terminal.

## Token economy
- Search before reading: `grep`/`find` to locate, then read only the relevant range (offset/limit); don't re-read a file already in context.
- Never print large outputs into the conversation: filter (errors, `head`/`tail`, counts) or write to a file and read the part that matters. Board logs go through `./target.sh`, which already trims.
- Big documents and pages: extract what the task needs, don't paste them whole.
- Keep replies as short as the content allows; no recap of what the tools already showed.
- When a new task is unrelated to the session so far, suggest `/clear` in one line (with `/rename` first so it can be resumed).
