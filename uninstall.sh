#!/bin/bash
# Removes Hold Space to Talk (leaves Hammerspoon and the rest of your config alone).
INIT="$HOME/.hammerspoon/init.lua"
[ -f "$INIT" ] && sed -i '' '/hold-space-to-talk\/holdspace.lua/d' "$INIT"
rm -rf "$HOME/.hammerspoon/hold-space-to-talk"
pkill -x Hammerspoon 2>/dev/null; sleep 1; open -a Hammerspoon
echo "Hold Space to Talk removed."
