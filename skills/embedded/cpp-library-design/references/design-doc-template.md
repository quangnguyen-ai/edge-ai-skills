# Design doc template — embedded/edge C++ library

A doc a new engineer (or agent) can act on in one read. Each section answers a question someone will otherwise ask in chat.

```markdown
# <Library> — Overview

> **Purpose**: one sentence — what goes in, what comes out
> **Primary target**: device + backend; secondary targets
> **Scope**: one instance = one model / one pipeline. What is outside (capture, transport, multi-model).

## 1. Introduction
- Inputs supported (sensor/format/size) — a table if more than one.
- What the library provides, as a numbered list.

### 1.1 Design goals
One API · config over code · fail loudly at load, degrade quietly at run time · bit-exact refactoring (or "within noise band N").

### 1.2 Non-goals
Explicit list.

## 2. Pipeline / data flow
Diagram per mode. Which config key selects the mode.

## 3. Architecture
### 3.1 Layers — ASCII stack, each layer with its source path
### 3.2 Directory structure — tree with one-line comments, plus a "to change X, edit Y" table (stage → config key, class, kernel per backend, test)
### 3.3 Per-frame data flow and state — what is carried between frames, warm-up, what resets state
### 3.4 Configuration loading — parse → defaults → resolve paths → load derived data → validate (with example error messages)
### 3.5 Threading, platform, power — thread-safety contract, CPU affinity, clocks/power policy and what is restored
### 3.6 Errors and observability — error contract, timing/profiling switches, the benchmark tool

## 4. API usage
### 4.1 Minimal integration — 10–20 lines, real calls, including the warm-up / not-ready case
### 4.2 Output sizes and buffers — when to allocate, byte counts per mode
### 4.3 Run-time controls — each setter and what it resets
### 4.4 Reference applications and tools — table: program → purpose → build flag → still used? Include the offline batch tool with per-stage dumps, the stage bench, and the backend parity tool
### 4.5 Build and run — exact commands per target, and the options that are silently wrong if omitted

## 5. Configuration
### 5.1 Profiles — table: file → device/camera, mode, algorithm, output, notes
### 5.2 Keys that most often matter — key, default, effect (and what was measured when a default was chosen)
### 5.3 Adding a profile — numbered steps ending in a verification

## 6. Verification
How changes are proven before commit: bit-exact hashes, noise band, cost measurement. A before/after table with a Note column.

## 7. Status and known limitations
Table: area → status (and what was *not* re-verified). Open items in priority order, each with cause and next step.

## 8. Further reading
Links to deep-dive docs, each with one line on what it answers.

**Status / version / target / last updated** footer.
```

Review checklist for an existing doc:
- Can someone build and run it on the target from section 4.5 alone?
- Is every number in it dated or tied to a commit, device, and config?
- Does "status" say what was **not** verified?
- Do the embedded defaults and the recommended profiles agree?
- Can you go from a stage's name to its config key, class, kernels, and test using only the doc?
- Can a reported bug be reproduced offline from a capture + config, using a tool the doc names?
