---
name: diagrams
description: Draw technical diagrams that answer one question — architecture layers, per-frame data flow, threads and queues, sequences, state machines, deployment, latency budgets, interfaces — as Mermaid source plus rendered PNG/SVG, checked by looking at the render. Use when the user asks to draw, diagram, visualize, or sketch a system, flow, pipeline, or design, or a doc needs a figure — even from a vague one-line request.
---

# Diagrams

A good diagram answers **one question** for **one reader**, with names taken from the real code. Most bad diagrams come from a vague request drawn literally ("draw the architecture" → a box for every class). So the first job is to turn the request into a brief — the user is not expected to write one.

## 1. Brief — from whatever the user said

Fill these yourself from the request, the conversation, and the code. Ask **at most one** question, and only if the question the diagram answers is genuinely unclear; otherwise pick the default and state it.

| Field | How to fill it | Default |
|---|---|---|
| **Question** | One sentence the diagram answers ("what happens to one frame and where it lives") | Inferred from the request |
| **Reader** | New engineer, reviewer, manager, the user themselves | New engineer on the project |
| **View** | Pick from the table below | — |
| **Scope** | Which part of the system; one level of abstraction only | The part being discussed |
| **Names** | Real tokens from the code: classes, stages, config keys, elements | Read the code first |
| **Where it goes** | Doc it belongs in | `docs/diagrams/NN-<name>.mmd` |

| The question is about… | View | Mermaid |
|---|---|---|
| what happens to one frame / one request | Data flow | `flowchart LR` |
| layers, components, dependency direction | Layered architecture | `flowchart TB` + `subgraph` |
| which thread does what, where things queue up | Threads and queues | `flowchart LR`, queues as nodes |
| who calls whom, in what order, where it syncs | Sequence | `sequenceDiagram` |
| modes, lifecycle, recovery | State machine | `stateDiagram-v2` |
| what runs on which machine | Deployment | `flowchart LR` + `subgraph` per machine |
| where the time goes | Latency budget | `gantt` (ms offsets) |
| what a new plugin must implement | Interfaces | `classDiagram` |

A request that mixes questions ("show the architecture and the data flow and the threads") becomes **several diagrams**, one per question — say so.

Done when the brief is written down (in the reply or the doc) in 3–6 lines.

## 2. Draft the source

Start from the matching pattern in [references/patterns.md](references/patterns.md), then:

- **5–15 nodes.** More means the scope is too wide: split, or collapse a group into one node and draw it separately.
- **One level of abstraction.** Don't mix "Engine" with a single helper function.
- **Short node labels, detail on edges**: format, resolution, memory type (host/device), rate, time.
- **Direction**: `LR` for pipelines and flows, `TB` for hierarchies and layers. Arrows point the way data or dependency goes, consistently.
- **House style**: white page, soft tinted boxes — one hue per group (pale fill, hue border, dark-shade bold title, muted description), dashed group frames with UPPERCASE labels, dark start box, solid end box, numbered badges when order matters. Palette and rules in [references/style.md](references/style.md), with a finished example in [examples/skill-lifecycle.png](examples/skill-lifecycle.png); never decorative colour.
- **Quote labels** containing punctuation (`A -->|"NV12, 1080p"| B`); use `<br/>` for at most one line break.
- Numbers on a diagram are real measurements with their condition (p50/p99, device), or left out.

## 3. Render and look

```bash
~/.claude/skills/diagrams/scripts/render.sh docs/diagrams/04-data-flow.mmd   # the skill's own scripts/ folder
```

Writes `.png` and `.svg` next to the source (first run downloads mermaid-cli via npx). Then **open the PNG and look at it** — the source never tells you what the reader will see. Check:

- [ ] It answers the brief's question at a glance.
- [ ] Every label readable, none clipped or overlapping; no edge label sitting on another edge.
- [ ] No crossing edges that could be removed by reordering nodes or changing direction.
- [ ] Names match the code.
- [ ] Nothing on it the reader doesn't need for the question.

Fix and re-render, up to 3 rounds. A parse error means fix the source — never deliver unrendered source.

## 4. Deliver

- Files: `docs/diagrams/NN-<name>.mmd` (source of truth) + `.png` + `.svg`. Number them in reading order.
- In Markdown docs, embed the PNG (renders everywhere) and keep the `.mmd` beside it; GitHub/GitLab can also render a ```` ```mermaid ```` fence inline if the team prefers.
- Show the PNG to the user, state the question it answers, and list what was deliberately left out.
- Editing later: change the `.mmd`, re-render — never hand-edit the PNG/SVG.

Done when the source, PNG, and SVG exist, the render passed the checklist, and the user has seen the image.

## When Mermaid isn't enough

- Large architecture diagrams that people will hand-edit in draw.io, with vendor icons, or generated/synced from code, IaC, SQL, or API schemas: suggest the user run `/drawio-skill` (user-invoked, if installed — see the README). It validates (`validate.py --score`), exports a PNG to look at, and keeps the `.drawio` editable. A Mermaid source from this skill can be its starting point.
- Explanatory, whiteboard-style figures for slides or articles: Excalidraw-based skills.
- Inside a claude.ai artifact or web page: inline SVG, following the artifact diagramming guidance.
