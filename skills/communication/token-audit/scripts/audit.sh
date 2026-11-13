#!/usr/bin/env bash
# Measure what Claude Code loads into every turn, and the biggest recent sessions.
#   audit.sh [project-dir]   (default: current directory)
set -uo pipefail
PROJ="${1:-$PWD}"
C="$HOME/.claude"

echo "== Always-loaded instructions (chars ≈ 4 per token)"
for f in "$C/CLAUDE.md" "$PROJ/CLAUDE.md" "$PROJ/AGENTS.md" "$PROJ/.claude/CLAUDE.md"; do
  [ -f "$f" ] && printf "%7d  %s (%d lines)\n" "$(wc -c < "$f")" "$f" "$(wc -l < "$f")"
done
MEM="$C/projects/$(echo "$PROJ" | sed 's|/|-|g')/memory/MEMORY.md"
[ -f "$MEM" ] && printf "%7d  %s\n" "$(wc -c < "$MEM")" "$MEM (memory index)"

echo
echo "== Model-invoked skill descriptions (listed every turn)"
total=0
for d in "$C"/skills/*/ "$PROJ"/.claude/skills/*/; do
  f="$d/SKILL.md"; [ -f "$f" ] || continue
  head -n 15 "$f" | grep -q "disable-model-invocation: true" && continue
  c=$(head -n 15 "$f" | sed -n 's/^description: //p' | wc -c)
  total=$((total + c)); printf "%5d  %s\n" "$c" "$(basename "$d")"
done | sort -rn
for d in "$C"/skills/*/ "$PROJ"/.claude/skills/*/; do
  f="$d/SKILL.md"; [ -f "$f" ] || continue
  head -n 15 "$f" | grep -q "disable-model-invocation: true" && continue
  head -n 15 "$f" | sed -n 's/^description: //p'
done | wc -c | awk '{printf "total ≈ %d chars ≈ %d tokens per turn (plus plugin and built-in skills)\n", $1, $1/4}'

echo
echo "== Settings that change cost"
for f in "$C/settings.json" "$PROJ/.claude/settings.json" "$PROJ/.claude/settings.local.json"; do
  [ -f "$f" ] || continue
  echo "-- $f"
  jq -c '{model, effortLevel, alwaysThinkingEnabled, promptSuggestionEnabled, disableClaudeAiConnectors, skillOverrides, enabledPlugins, hooks: (.hooks // {} | keys)}' "$f" 2>/dev/null
done

echo
echo "== Largest sessions in the last 14 days (on-disk log: images, /rewind snapshots and every compacted turn; NOT the per-turn context)"
find "$C/projects" -name '*.jsonl' -mtime -14 -printf '%s %p\n' 2>/dev/null | sort -rn | head -5 \
  | awk '{printf "%6.1f MB  %s\n", $1/1048576, $2}'
