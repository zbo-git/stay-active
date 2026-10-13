#!/bin/bash
# Install zbo-git/stay-active. Use local script when running from a checkout.
set -euo pipefail
[[ "$(uname -s)" = Darwin ]] || { echo 'macOS required' >&2; exit 1; }
if ! command -v brew >/dev/null 2>&1; then
    echo 'Homebrew is required. Install from https://brew.sh/' >&2
    exit 1
fi
if ! command -v cliclick >/dev/null 2>&1; then brew install cliclick; fi
mkdir -p "$HOME/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/stay-active" ]]; then
    cp "$SCRIPT_DIR/stay-active" "$HOME/.local/bin/stay-active"
else
    curl -fsSL 'https://raw.githubusercontent.com/zbo-git/stay-active/main/stay-active' -o "$HOME/.local/bin/stay-active"
fi
chmod 755 "$HOME/.local/bin/stay-active"
RC="$HOME/.zshrc"
[[ "${SHELL:-}" = */bash ]] && RC="$HOME/.bashrc"
if ! grep -Fq '$HOME/.local/bin' "$RC" 2>/dev/null; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
fi
cat <<'MESSAGE'
Installed ~/.local/bin/stay-active.
Open a new terminal or run: export PATH="$HOME/.local/bin:$PATH"
Grant your terminal and cliclick Accessibility access in System Settings > Privacy & Security > Accessibility.
Then run: stay-active start
Optional login service: stay-active autostart-on
MESSAGE
