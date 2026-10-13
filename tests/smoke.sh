#!/bin/bash
set -eu
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/stay-active"
TEMP_HOME=$(mktemp -d)
trap 'rm -rf "$TEMP_HOME"' EXIT
HOME="$TEMP_HOME" /bin/bash "$SCRIPT" --version | grep -q 'v1.1.0'
HOME="$TEMP_HOME" /bin/bash "$SCRIPT" --help | grep -q 'autostart-on'
if HOME="$TEMP_HOME" /bin/bash "$SCRIPT" status; then echo 'Unexpected running state' >&2; exit 1; fi
mkdir -p "$TEMP_HOME/.local/.stay_active_lock"
printf 'invalid-pid\n' > "$TEMP_HOME/.local/.stay_active_pid"
if HOME="$TEMP_HOME" /bin/bash "$SCRIPT" stop; then echo 'Unsafe stop' >&2; exit 1; fi
test -d "$TEMP_HOME/.local/.stay_active_lock"
echo 'Smoke tests passed'
