#!/usr/bin/env bash
set -uo pipefail

# Enforces the repo rules in CLAUDE.md. Exits non-zero on any error.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
PROMOTED=(edge-ai embedded communication)
MAX_DESC=450
errors=0
err() { echo "error: $*" >&2; errors=$((errors + 1)); }
warn() { echo "warning: $*" >&2; }

is_promoted() {
  local b
  for b in "${PROMOTED[@]}"; do [ "$1" = "$b" ] && return 0; done
  return 1
}

declare -A seen
while IFS= read -r skill_md; do
  dir="$(dirname "$skill_md")"
  name="$(basename "$dir")"
  bucket="$(basename "$(dirname "$dir")")"

  [ -n "${seen[$name]:-}" ] && err "duplicate skill name '$name' ($dir, ${seen[$name]})"
  seen[$name]="$dir"

  fm_name="$(sed -n '2,10p' "$skill_md" | sed -n 's/^name: //p' | head -1)"
  [ "$fm_name" = "$name" ] || err "$skill_md: frontmatter name '$fm_name' != folder '$name'"

  desc="$(sed -n '2,10p' "$skill_md" | sed -n 's/^description: //p' | head -1)"
  if [ -z "$desc" ]; then
    err "$skill_md: missing description"
  elif [ "${#desc}" -gt 1024 ]; then
    err "$skill_md: description is ${#desc} chars (hard limit 1024)"
  elif [ "${#desc}" -gt "$MAX_DESC" ]; then
    warn "$skill_md: description is ${#desc} chars (aim for <= $MAX_DESC)"
  fi

  rel="./$dir"
  in_readme=0; grep -qF "($rel/SKILL.md)" README.md && in_readme=1
  in_plugin=0; grep -qF "\"$rel\"" .claude-plugin/plugin.json && in_plugin=1

  if is_promoted "$bucket"; then
    [ $in_readme = 1 ] || err "$name: promoted but not linked in README.md"
    [ $in_plugin = 1 ] || err "$name: promoted but missing from plugin.json"
  else
    [ $in_readme = 0 ] || err "$name: in '$bucket/' but listed in README.md"
    [ $in_plugin = 0 ] || err "$name: in '$bucket/' but listed in plugin.json"
  fi
done < <(find skills -name SKILL.md | sort)

# Relative markdown links in skills/, docs/ and README.md must resolve.
while IFS= read -r md; do
  dir="$(dirname "$md")"
  while IFS= read -r target; do
    t="${target%%#*}"
    [ -z "$t" ] && continue
    case "$t" in http*|mailto:*|/*|~*) continue ;; esac
    [ -e "$dir/$t" ] || err "$md: broken link -> $target"
  done < <(awk '/^[ ]*```/{f=!f; next} !f' "$md" | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\((.*)\)$/\1/' | sed -E 's/ .*$//')
done < <(find skills docs README.md -name '*.md' 2>/dev/null)

# plugin.json entries must point at real skills.
while IFS= read -r p; do
  [ -f "$p/SKILL.md" ] || err "plugin.json lists '$p' but it has no SKILL.md"
done < <(grep -o '"\./skills/[^"]*"' .claude-plugin/plugin.json | tr -d '"')

if [ $errors -gt 0 ]; then
  echo "$errors error(s)" >&2
  exit 1
fi
echo "ok: $(find skills -name SKILL.md | wc -l) skills checked"
