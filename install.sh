#!/usr/bin/env bash
# Install this repo's skills and the personal Claude Code setup on a machine.
#
#   ./install.sh [--dry-run] [--with-drawio] [--no-settings] [--no-claude-md]
#
# Steps (each idempotent; anything replaced is backed up as <file>.bak-<timestamp>):
#   1. Link every skill into ~/.claude/skills and ~/.agents/skills (scripts/link-skills.sh).
#   2. ~/.claude/CLAUDE.md -> symlink to config/claude/CLAUDE.md, so edits (including the
#      retro skill's) land in this repo and travel with git.
#   3. Merge config/claude/settings.fragment.json into ~/.claude/settings.json: model,
#      connectors, skill overrides, retro hooks. Existing keys are kept; hook entries are
#      added once. Machine-specific settings (autoMode, plugins, MCP) are not touched.
#   4. --with-drawio: clone drawio-skill at a pinned commit and link it, install the
#      draw.io AppImage (checksum-verified), the `drawio` wrapper, and the `soft` preset.
#
# The skills expect this repo at ~/DATA/Projects/edge-ai-skills; elsewhere works, but
# CLAUDE.md is then copied with the path rewritten instead of symlinked.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CANON="$HOME/DATA/Projects/edge-ai-skills"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY=0; WITH_DRAWIO=0; DO_SETTINGS=1; DO_CLAUDE_MD=1
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --with-drawio) WITH_DRAWIO=1 ;;
    --no-settings) DO_SETTINGS=0 ;;
    --no-claude-md) DO_CLAUDE_MD=0 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

DRAWIO_SKILL_REPO="https://github.com/Agents365-ai/drawio-skill.git"
DRAWIO_SKILL_COMMIT="57270820d3cd71cbdf4fb6b2f7091d4fb37bb019"
DRAWIO_VER="31.5.2"
DRAWIO_SHA256="c0b37ee00307d7112c29b28ea33686103f47af620415d710663497459bdf927f"
THIRD_PARTY="${THIRD_PARTY_DIR:-$HOME/DATA/Projects/third-party-skills}"

say()  { echo "==> $*"; }
do_()  { if [ $DRY = 1 ]; then echo "    [dry-run] $*"; else eval "$@"; fi; }
backup() { [ -e "$1" ] && [ ! -L "$1" ] && do_ "cp -a '$1' '$1.bak-$STAMP'" && echo "    backup: $1.bak-$STAMP" || true; }

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
mkdir -p "$HOME/.claude"

# 1. skills -----------------------------------------------------------------
say "Linking skills"
if [ $DRY = 1 ]; then echo "    [dry-run] $REPO/scripts/link-skills.sh"; else "$REPO/scripts/link-skills.sh" | grep -c linked | sed 's/^/    links created: /'; fi

# 2. CLAUDE.md --------------------------------------------------------------
if [ $DO_CLAUDE_MD = 1 ]; then
  say "Global CLAUDE.md"
  T="$HOME/.claude/CLAUDE.md"; SRC="$REPO/config/claude/CLAUDE.md"
  if [ -L "$T" ] && [ "$(readlink -f "$T")" = "$(readlink -f "$SRC")" ]; then
    echo "    already linked"
  elif [ "$REPO" = "$CANON" ]; then
    backup "$T"; do_ "ln -sfn '$SRC' '$T'"; echo "    linked -> $SRC"
  else
    NEW="$(sed "s#~/DATA/Projects/edge-ai-skills#$REPO#g" "$SRC")"
    if [ -f "$T" ] && [ "$NEW" = "$(cat "$T")" ]; then
      echo "    up to date (copy)"
    else
      backup "$T"
      if [ $DRY = 1 ]; then echo "    [dry-run] write rewritten copy to $T"; else printf '%s\n' "$NEW" > "$T"; fi
      echo "    repo is not at $CANON: copied with the path rewritten (edits will NOT flow back to git)"
    fi
  fi
fi

# 3. settings ---------------------------------------------------------------
if [ $DO_SETTINGS = 1 ]; then
  say "Merging settings into ~/.claude/settings.json"
  S="$HOME/.claude/settings.json"
  DRY=$DRY STAMP=$STAMP python3 - "$S" "$REPO/config/claude/settings.fragment.json" <<'PY'
import json, os, sys
target, frag_path = sys.argv[1], sys.argv[2]
cur = json.load(open(target)) if os.path.exists(target) else {}
frag = json.load(open(frag_path))
changes = []
for k in ("model", "disableClaudeAiConnectors"):
    if k in frag and k not in cur:
        cur[k] = frag[k]; changes.append(f"{k}={frag[k]}")
    elif k in frag and cur.get(k) != frag[k]:
        changes.append(f"{k}: kept existing {cur[k]!r} (repo has {frag[k]!r})")
so = cur.setdefault("skillOverrides", {})
added = [k for k in frag.get("skillOverrides", {}) if k not in so]
for k in added:
    so[k] = frag["skillOverrides"][k]
changes.append(f"skillOverrides: +{len(added)}")
hooks = cur.setdefault("hooks", {})
for ev, entries in frag.get("hooks", {}).items():
    have = {h.get("command") for e in hooks.get(ev, []) for h in e.get("hooks", [])}
    for e in entries:
        cmds = [h.get("command") for h in e.get("hooks", [])]
        if not any(c in have for c in cmds):
            hooks.setdefault(ev, []).append(e); changes.append(f"hook {ev}")
before = json.load(open(target)) if os.path.exists(target) else None
print("    " + "; ".join(changes))
if cur == before:
    print("    no changes")
elif os.environ.get("DRY") != "1":
    if before is not None:
        import shutil
        bak = f"{target}.bak-{os.environ['STAMP']}"
        shutil.copy2(target, bak); print(f"    backup: {bak}")
    json.dump(cur, open(target, "w"), indent=2, ensure_ascii=False)
    json.load(open(target))  # re-read to prove it is valid JSON
PY
fi

# 4. draw.io ----------------------------------------------------------------
if [ $WITH_DRAWIO = 1 ]; then
  say "draw.io skill, app, wrapper, preset"
  D="$THIRD_PARTY/drawio-skill"
  if [ ! -d "$D/.git" ]; then
    do_ "mkdir -p '$THIRD_PARTY' && git clone -q '$DRAWIO_SKILL_REPO' '$D'"
  fi
  do_ "git -C '$D' fetch -q origin '$DRAWIO_SKILL_COMMIT' 2>/dev/null || true; git -C '$D' checkout -q '$DRAWIO_SKILL_COMMIT'"
  do_ "ln -sfn '$D/skills/drawio-skill' '$HOME/.claude/skills/drawio-skill'"
  echo "    drawio-skill @ ${DRAWIO_SKILL_COMMIT:0:7} (review its changes before moving the pin)"

  APP_DIR="$HOME/.local/opt/drawio"; APP="$APP_DIR/drawio-$DRAWIO_VER.AppImage"
  if [ -f "$APP" ] && echo "$DRAWIO_SHA256  $APP" | sha256sum -c --status; then
    echo "    AppImage $DRAWIO_VER present, checksum ok"
  else
    do_ "mkdir -p '$APP_DIR' && curl -sSL -o '$APP' https://github.com/jgraph/drawio-desktop/releases/download/v$DRAWIO_VER/drawio-x86_64-$DRAWIO_VER.AppImage"
    if [ $DRY = 0 ]; then
      echo "$DRAWIO_SHA256  $APP" | sha256sum -c --status || { echo "    checksum MISMATCH — removing $APP" >&2; rm -f "$APP"; exit 1; }
      chmod +x "$APP"; echo "    AppImage $DRAWIO_VER downloaded, checksum ok"
    fi
  fi
  do_ "mkdir -p '$HOME/.local/bin' && install -m 755 '$REPO/config/bin/drawio' '$HOME/.local/bin/drawio'"
  do_ "mkdir -p '$HOME/.drawio-skill/styles' && cp '$REPO/config/drawio/styles/soft.json' '$HOME/.drawio-skill/styles/soft.json'"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "    note: add ~/.local/bin to PATH" ;; esac
fi

say "Done. Open a new Claude Code session; check /skills and /hooks."
