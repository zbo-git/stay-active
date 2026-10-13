#!/bin/bash
set -euo pipefail
BIN="$HOME/.local/bin/stay-active"
if [[ -f "$BIN" ]]; then
    /bin/bash "$BIN" autostart-off || true
    /bin/bash "$BIN" stop || true
else
    echo 'Executable not installed; cannot safely verify or stop old process.' >&2
fi
# Don't remove state from an active or uncertain process.
if [[ -f "$HOME/.local/.stay_active_pid" ]] || [[ -d "$HOME/.local/.stay_active_lock" ]]; then
    echo 'Review ~/.local/.stay_active_pid and ~/.local/.stay_active_lock before cleaning up.' >&2
fi
rm -f "$BIN"
echo 'Executable removed. Existing logs and state preserved for safety.'
echo 'Remove cliclick separately with brew uninstall cliclick if no longer needed.'
