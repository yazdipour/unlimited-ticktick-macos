#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$SCRIPT_DIR/force-checkpoint-zero.js"
APP="${TICKTICK_APP:-$REPO_DIR/TickTick.debug.app}"
APP_BIN="$APP/Contents/MacOS/TickTick"

usage() {
  cat <<USAGE
Usage:
  $0             Launch the prepared debug TickTick app under Frida
  $0 spawn       Same as above
  $0 attach      Attach to an already-running TickTick process
  $0 attach PID  Attach to a specific process id

Examples:
  $0
  $0 attach
  $0 attach 12345

Environment:
  TICKTICK_APP    Override app path. Default: $APP
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 was not found in PATH"
}

spawn_app() {
  [[ -f "$HOOK" ]] || die "hook script not found: $HOOK"
  [[ -x "$APP_BIN" ]] || die "TickTick debug executable not found: $APP_BIN
Run tools/checkpoint-zero/prepare-app.sh first."

  exec frida -f "$APP_BIN" -l "$HOOK"
}

attach_app() {
  [[ -f "$HOOK" ]] || die "hook script not found: $HOOK"

  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    exec frida -p "$1" -l "$HOOK"
  fi

  exec frida -n TickTick -l "$HOOK"
}

mode="${1:-spawn}"

require_tool frida

case "$mode" in
  spawn)
    spawn_app
    ;;
  attach)
    attach_app "${2:-}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
