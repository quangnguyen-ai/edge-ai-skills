# Knowledge base

Only special, non-obvious knowledge behind the skills: hardware and SDK limits, surprising behaviour, error messages that point to a cause — no measurements or benchmark numbers (those stay in the project that produced them). Each lesson carries a date and an evidence level (**[measured]**, **[docs]**, **[assumption]**). Skills hold the procedure and a short checklist; they link here for the detail.

| File | Covers |
|---|---|
| [arm-cpu-inference.md](arm-cpu-inference.md) | CPU inference on Linux aarch64: threads vs clusters, pinning, float vs quantized, ORT vs LiteRT |
| [qualcomm-qairt.md](qualcomm-qairt.md) | QAIRT (SNPE/QNN) on Qualcomm SoCs: accelerator per SoC, op limits, layout/preprocessing, zero-copy, licensing |

Rules: generic only (public chips, public models, no company or product names); no numbers from measurements — write the lesson, not the data; skip anything obvious or already in a skill; one topic per file; date and SDK/device in the header; when a fact changes, edit it and bump the date rather than appending contradictions.
