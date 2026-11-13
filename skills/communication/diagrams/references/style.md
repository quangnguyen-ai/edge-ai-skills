# House style — white page, soft tinted boxes

The default look for every diagram (Mermaid or draw.io) unless the user asks otherwise.

**Reference example:** [../examples/skill-lifecycle.png](../examples/skill-lifecycle.png) is what "done" looks like — open it before drawing. Its source [../examples/skill-lifecycle.drawio](../examples/skill-lifecycle.drawio) shows how each element is built in draw.io XML (group frames, tinted boxes, badges nested inside boxes, hue-coloured arrows, title + subtitle); copy its styles rather than re-deriving them.

- **White background.** No grey bands, no coloured page.
- **One hue per group of related boxes.** Box fill is a pale tint of the hue, the border is the hue at 1.8 px, the title is a dark shade of the hue (bold, ~15 px), the description a muted shade (~12 px). Rounded corners.
- **Groups** are dashed rounded frames (2 px, dash 7/5) in a lighter shade of the hue, with a very pale fill and an UPPERCASE, letter-spaced label at top-left in the hue colour — not a header bar.
- **Input / start**: dark slate box with white bold title and light-grey description. **Output / end**: solid hue box with white text.
- **Numbered badges** (white digit in a filled hue circle, left inside the box) when the order of steps matters.
- **Arrows** 2.5 px in the hue of the group they belong to, solid block heads; dashed for "only when…" paths. Short labels in the arrow's colour on a white chip.
- **Title** centered, bold ~25 px near-black; one-line **subtitle** below in grey saying what the diagram answers (in the user's language).
- At most 4 hues per diagram; every hue means a group, never decoration.

## Palette

| Hue | Stroke / arrow | Box fill | Title text | Description | Group fill | Group frame |
|---|---|---|---|---|---|---|
| purple | `#6A3D96` | `#EFE7F7` | `#4A2870` | `#5A3A80` | `#F8F4FC` | `#9A78C0` |
| hot | `#B0431C` | `#FBEAE2` | `#7E2E10` | `#6E4436` | `#FDF3EE` | `#C4703F` |
| amber | `#A0730B` | `#FAF0D9` | `#6E4E06` | `#7A5810` | `#FDF8EC` | `#C49A3A` |
| slate | `#4A6070` | `#E8EEF2` | `#2C3E4C` | `#4A6070` | `#F5F8FA` | `#7D93A3` |
| start (dark) | `#12181F` | `#1F2A37` | `#FFFFFF` | `#B9C4CF` | — | — |

Text: title `#12181F`, subtitle `#5A6672`. Font: Helvetica Neue / Helvetica / Arial.

Suggested meaning when it fits: purple = the main path, hot = problems / failure handling, amber = cross-cutting support, slate = infrastructure / docs / external.

## Mermaid

`scripts/mermaid-config.json` sets the white page and font. Apply hues with `classDef` (see `patterns.md`):

```
classDef start fill:#1F2A37,stroke:#12181F,color:#FFFFFF,stroke-width:2px
classDef purple fill:#EFE7F7,stroke:#6A3D96,color:#4A2870,stroke-width:1.8px
classDef hot fill:#FBEAE2,stroke:#B0431C,color:#7E2E10,stroke-width:1.8px
classDef amber fill:#FAF0D9,stroke:#A0730B,color:#6E4E06,stroke-width:1.8px
classDef slate fill:#E8EEF2,stroke:#4A6070,color:#2C3E4C,stroke-width:1.8px
classDef finish fill:#6A3D96,stroke:#4A2870,color:#FFFFFF,stroke-width:2px
```

Group frames: `style <subgraph-id> fill:#FDF3EE,stroke:#C4703F,stroke-width:2px,stroke-dasharray:7 5,color:#B0431C`. Colour an edge with `linkStyle <n> stroke:#6A3D96,stroke-width:2.5px`.

## draw.io

The user preset `~/.drawio-skill/styles/soft.json` (default) carries this palette. For hand-authored XML use the same values; put numbered badges *inside* their box (box `container=1`, badge `parent=` the box) so the validator sees no overlap.
