#!/bin/bash
# Hold Space to Talk installer:
#   curl -fsSL https://raw.githubusercontent.com/capi789/hold-space-to-talk/main/install.sh | bash
set -euo pipefail
RAW="https://raw.githubusercontent.com/capi789/hold-space-to-talk/main"
DEST="$HOME/.hammerspoon/hold-space-to-talk"
INIT="$HOME/.hammerspoon/init.lua"
LINE='dofile(hs.configdir .. "/hold-space-to-talk/holdspace.lua") -- Hold Space to Talk'

[ "$(uname)" = "Darwin" ] || { echo "Hold Space to Talk only runs on macOS."; exit 1; }

# 1. Hammerspoon (the free app that runs the script)
if [ ! -d "/Applications/Hammerspoon.app" ]; then
  echo "Installing Hammerspoon..."
  if command -v brew >/dev/null 2>&1; then
    brew install --cask hammerspoon
  else
    url=$(curl -fsSL https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest | grep -o 'https://[^"]*Hammerspoon-[^"]*\.zip' | head -1)
    tmp=$(mktemp -d)
    curl -fsSL "$url" -o "$tmp/hs.zip"
    ditto -x -k "$tmp/hs.zip" /Applications
    rm -rf "$tmp"
  fi
fi

# 2. The script (from this folder if you cloned the repo, otherwise from GitHub)
mkdir -p "$DEST"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$here" ] && [ -f "$here/holdspace.lua" ]; then
  cp "$here/holdspace.lua" "$DEST/holdspace.lua"
else
  curl -fsSL "$RAW/holdspace.lua" -o "$DEST/holdspace.lua"
fi

# 3. Load it from Hammerspoon's config (once), and start Hammerspoon at login
touch "$INIT"
grep -qF "hold-space-to-talk/holdspace.lua" "$INIT" || printf '\n%s\n' "$LINE" >> "$INIT"

# 4. (Re)start Hammerspoon
pkill -x Hammerspoon 2>/dev/null || true
sleep 1
open -a Hammerspoon

echo
echo "Done. If macOS asks, allow Hammerspoon in System Settings > Privacy & Security > Accessibility."
echo "Then open Claude or ChatGPT, hold Space to talk, tap Space to stop, Return to send."
