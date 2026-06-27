#!/usr/bin/env bash
# Claude Code Statusline — installer
# Installs the statusline script and wires it into ~/.claude/settings.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.claude/scripts"
TARGET_SCRIPT="$TARGET_DIR/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

say() { printf "\033[96m▶\033[0m %s\n" "$*"; }
ok()  { printf "\033[92m✓\033[0m %s\n" "$*"; }
err() { printf "\033[91m✗\033[0m %s\n" "$*" >&2; }

# 1) Requirements
command -v python3 >/dev/null || { err "python3 not found"; exit 1; }
command -v curl    >/dev/null || { err "curl not found"; exit 1; }
command -v security >/dev/null 2>&1 || say "macOS Keychain not available (Linux/WSL) — Anthropic quota readout will be disabled, fallback estimates will be used."

# 2) Optional: ccusage (improves burn-rate + token breakdown)
if ! command -v ccusage >/dev/null 2>&1; then
    say "ccusage not installed — burn rate and Opus/Sonnet breakdown will be limited."
    say "Install later with:  npm i -g ccusage   (or:  npx ccusage)"
fi

# 3) Install the script
mkdir -p "$TARGET_DIR"
cp "$SCRIPT_DIR/statusline.sh" "$TARGET_SCRIPT"
chmod +x "$TARGET_SCRIPT"
ok "Installed $TARGET_SCRIPT"

# 4) Wire into settings.json (idempotent merge)
mkdir -p "$HOME/.claude"
python3 - <<PY
import json, os, sys

p = "$SETTINGS"
data = {}
if os.path.exists(p):
    try:
        with open(p) as f:
            data = json.load(f)
    except Exception as e:
        print(f"\033[91m✗\033[0m settings.json is invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

data["statusLine"] = {
    "type": "command",
    "command": f"bash {os.path.expanduser('~/.claude/scripts/statusline.sh')}",
    "refreshInterval": 10,
}

with open(p, "w") as f:
    json.dump(data, f, indent=2)
print(f"\033[92m✓\033[0m Updated {p}")
PY

echo
ok "Done. Restart Claude Code (or run /statusline) to see it."
echo
echo "Tip: the statusline reads your real Anthropic quota via the OAuth token"
echo "Claude Code stored in your macOS Keychain (key: 'Claude Code-credentials')."
echo "If you see '~%' it's a local estimate (Anthropic endpoint not reachable)."
