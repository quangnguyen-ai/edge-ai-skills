#!/usr/bin/env bash
# Render Mermaid sources to PNG + SVG next to them.
#
#   render.sh docs/diagrams/04-data-flow.mmd [more.mmd ...]
#
# Uses a local `mmdc` if installed, otherwise a pinned @mermaid-js/mermaid-cli via npx
# (first run downloads it and a headless Chromium). Exit code != 0 on any parse error.

set -euo pipefail
[ $# -ge 1 ] || { echo "usage: $0 file.mmd [...]" >&2; exit 2; }

MMDC_VERSION="${MMDC_VERSION:-11.4.2}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HERE/mermaid-config.json"

if command -v mmdc >/dev/null 2>&1; then
  MMDC=(mmdc)
else
  MMDC=(npx -y "@mermaid-js/mermaid-cli@$MMDC_VERSION")
fi

rc=0
for src in "$@"; do
  base="${src%.mmd}"
  if "${MMDC[@]}" -q -i "$src" -o "$base.png" -c "$CONFIG" -b white -s 2 \
     && "${MMDC[@]}" -q -i "$src" -o "$base.svg" -c "$CONFIG" -b white; then
    echo "ok: $base.png $base.svg"
  else
    echo "FAILED: $src" >&2
    rc=1
  fi
done
exit $rc
