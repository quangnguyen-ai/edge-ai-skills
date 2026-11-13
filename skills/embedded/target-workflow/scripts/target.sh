#!/usr/bin/env bash
# Host → target loop for this project: edit on the host, build and run on the board.
#
#   ./target.sh check            confirm the board is reachable and is the right one
#   ./target.sh sync [-n]        rsync the project to the board (-n = dry run)
#   ./target.sh build            run BUILD_CMD on the board
#   ./target.sh up               sync + build
#   ./target.sh run "<cmd>"      run a command in TARGET_DIR on the board; output saved to logs/
#   ./target.sh pull [path]      copy a remote path (default: REMOTE_OUT) into logs/pulled/
#   ./target.sh shell            interactive shell in TARGET_DIR
#
# Config: .target.env next to this script (per developer, gitignored).
# Copy .target.env.example and fill it in.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${TARGET_ENV:-$HERE/.target.env}"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

: "${TARGET_HOST:?set TARGET_HOST in $ENV_FILE (a Host from ~/.ssh/config)}"
: "${TARGET_DIR:?set TARGET_DIR in $ENV_FILE (absolute path on the board)}"
BUILD_CMD="${BUILD_CMD:-cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j\$(nproc)}"
REMOTE_OUT="${REMOTE_OUT:-outputs}"
LOG_DIR="$HERE/logs"
# Output shown to the caller is trimmed to save context; the full log is always kept.
# TARGET_VERBOSE=1 streams everything; TARGET_MAX_LINES sets the trim (default 40).
MAX_LINES="${TARGET_MAX_LINES:-40}"

# Reuse one ssh connection for every call (no handshake per command).
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/cm-%r@%h:%p" -o ControlPersist=10m)

# Never shipped to the board: VCS, local builds, scratch space, logs, editor/sync state.
EXCLUDES=(
  --exclude=.git/ --exclude='build*/' --exclude=workspace/ --exclude=logs/
  --exclude=outputs/ --exclude=.vscode/ --exclude=.claude/ --exclude='*.ffs_db'
  --exclude=.target.env
)
[ -f "$HERE/.targetignore" ] && EXCLUDES+=(--exclude-from="$HERE/.targetignore")

remote() {
  local inner
  inner="cd $(printf %q "$TARGET_DIR") && $1"
  # Login shell so the board's PATH (CUDA, SDKs) is loaded.
  ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "bash -lc $(printf %q "$inner")"
}

# DHCP leases shift: make sure TARGET_HOST still points at the intended board.
verify_host() {
  [ -n "${TARGET_HOSTNAME:-}" ] || return 0
  local actual
  actual="$(ssh "${SSH_OPTS[@]}" -o ConnectTimeout=8 "$TARGET_HOST" hostname)" || {
    echo "error: cannot reach $TARGET_HOST -- has its IP changed?" >&2; exit 1; }
  if [ "$actual" != "$TARGET_HOSTNAME" ]; then
    echo "error: $TARGET_HOST is '$actual', expected '$TARGET_HOSTNAME' -- wrong board?" >&2
    exit 1
  fi
}

cmd_check() {
  verify_host
  ssh "${SSH_OPTS[@]}" -o ConnectTimeout=8 "$TARGET_HOST" \
    "echo host: \$(hostname) \$(uname -m); df -h $(printf %q "$(dirname "$TARGET_DIR")") | tail -1"
}

cmd_sync() {
  verify_host
  local dry=()
  [ "${1:-}" = "-n" ] && dry=(--dry-run)
  # --delete only when asked: the board may hold files that exist nowhere else.
  local del=()
  [ "${SYNC_DELETE:-0}" = 1 ] && del=(--delete)
  ssh "${SSH_OPTS[@]}" "$TARGET_HOST" "mkdir -p $(printf %q "$TARGET_DIR")"
  rsync -az --protect-args --itemize-changes "${dry[@]}" "${del[@]}" "${EXCLUDES[@]}" \
    -e "ssh ${SSH_OPTS[*]}" "$HERE/" "$TARGET_HOST:$TARGET_DIR/"
}

# Print a long log as head + tail; build logs as their error/warning lines + tail.
show_log() {  # $1 = log file, $2 = "build" to filter diagnostics
  local log="$1" n
  n=$(wc -l < "$log")
  if [ "${TARGET_VERBOSE:-0}" = 1 ] || [ "$n" -le $((MAX_LINES * 2)) ]; then
    cat "$log"
  elif [ "${2:-}" = build ]; then
    grep -nE "error|warning:|undefined reference|FAILED|No such file|Killed" "$log" | head -n "$MAX_LINES"
    echo "... ($n lines total) ..."
    tail -n 5 "$log"
  else
    head -n "$MAX_LINES" "$log"
    echo "... ($((n - MAX_LINES * 2)) lines omitted — full log: $log) ..."
    tail -n "$MAX_LINES" "$log"
  fi
}

cmd_build() {
  mkdir -p "$LOG_DIR"
  local log="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S)-$$.log" rc
  set +e
  if [ "${TARGET_VERBOSE:-0}" = 1 ]; then remote "$BUILD_CMD" 2>&1 | tee "$log"; rc=${PIPESTATUS[0]}
  else remote "$BUILD_CMD" > "$log" 2>&1; rc=$?; show_log "$log" build; fi
  set -e
  echo "build log: $log (exit $rc)" >&2
  return "$rc"
}

cmd_run() {
  [ $# -ge 1 ] || { echo "usage: $0 run \"<command>\"" >&2; exit 2; }
  mkdir -p "$LOG_DIR"
  local log="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S)-$$.log" rc
  echo "# $TARGET_HOST:$TARGET_DIR \$ $*" > "$log"
  set +e
  if [ "${TARGET_VERBOSE:-0}" = 1 ]; then remote "$*" 2>&1 | tee -a "$log"; rc=${PIPESTATUS[0]}
  else remote "$*" >> "$log" 2>&1; rc=$?; show_log "$log"; fi
  set -e
  echo "# exit $rc" >> "$log"
  echo "log: $log (exit $rc)" >&2
  return "$rc"
}

cmd_pull() {
  local path="${1:-$REMOTE_OUT}"
  path="${path%/}"  # copy the directory itself, not just its contents
  mkdir -p "$LOG_DIR/pulled"
  rsync -az --protect-args -e "ssh ${SSH_OPTS[*]}" "$TARGET_HOST:$TARGET_DIR/$path" "$LOG_DIR/pulled/"
  echo "pulled into $LOG_DIR/pulled/" >&2
}

cmd_shell() {
  ssh -t "${SSH_OPTS[@]}" "$TARGET_HOST" "cd $(printf %q "$TARGET_DIR") && exec \$SHELL -l"
}

case "${1:-}" in
  check) cmd_check ;;
  sync)  shift; cmd_sync "$@" ;;
  build) cmd_build ;;
  up)    cmd_sync && cmd_build ;;
  run)   shift; cmd_run "$@" ;;
  pull)  shift; cmd_pull "$@" ;;
  shell) cmd_shell ;;
  *) sed -n '2,13p' "$0"; exit 2 ;;
esac
