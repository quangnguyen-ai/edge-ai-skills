#!/usr/bin/env bash
set -euo pipefail

# Symlinks every non-deprecated skill into the local harness skill dirs, and
# removes links that point into this repo but whose target no longer exists
# (skills renamed, moved, or deprecated).

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DESTS=("$HOME/.claude/skills" "$HOME/.agents/skills")

names=()
srcs=()
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  names+=("$(basename "$src")")
  srcs+=("$src")
done < <(find "$REPO/skills" -name SKILL.md -not -path '*/deprecated/*' -print0)

for DEST in "${DESTS[@]}"; do
  mkdir -p "$DEST"

  # Prune stale links into this repo.
  for link in "$DEST"/*; do
    [ -L "$link" ] || continue
    target="$(readlink "$link")"
    case "$target" in
      "$REPO"/*)
        if [ ! -e "$target" ] || [[ "$target" == */deprecated/* ]]; then
          rm "$link"
          echo "pruned $(basename "$link") ($DEST)"
        fi
        ;;
    esac
  done

  for i in "${!names[@]}"; do
    name="${names[$i]}"
    src="${srcs[$i]}"
    target="$DEST/$name"

    if [ -L "$target" ]; then
      current="$(readlink "$target")"
      if [ "$current" != "$src" ] && [ -e "$current" ]; then
        echo "warning: $name already links to $current — overriding" >&2
      fi
    elif [ -e "$target" ]; then
      echo "skip $name: $target is a real file/dir, not a link" >&2
      continue
    fi

    ln -sfn "$src" "$target"
    echo "linked $name -> $src ($DEST)"
  done
done
