#!/bin/bash
# Local multiplayer test: launches the dedicated server + a Human client + a
# Zombie client, all on this machine. Both clients auto-join and jump straight
# into the match.
#
# How to use:
#   - Double-click this file in Finder, OR
#   - In Terminal:  ./run_local_mp.command
#
# Close this Terminal window (or press Ctrl+C) to shut the server down.

cd "$(dirname "$0")" || exit 1

GODOT="/Applications/Godot 2.app/Contents/MacOS/Godot"
if [ ! -x "$GODOT" ]; then
  echo "Godot engine not found at:"
  echo "  $GODOT"
  echo "Open this file and set GODOT to your Godot app's binary path"
  echo "(right-click your Godot.app > Show Package Contents > Contents/MacOS/Godot)."
  read -r -p "Press Return to close."
  exit 1
fi

echo "Starting dedicated server (headless, no window)..."
"$GODOT" --headless --path . -- --server &
SERVER_PID=$!

# Stop the server when this script exits.
trap 'echo "Stopping server..."; kill $SERVER_PID 2>/dev/null' EXIT

sleep 2
echo "Launching Human client..."
"$GODOT" --path . -- --autojoin --role=human &
echo "Launching Zombie client..."
"$GODOT" --path . -- --autojoin --role=zombie &

echo ""
echo "Two game windows should open and start the match automatically."
echo "Leave this window open while playing. Ctrl+C (or closing it) stops the server."
wait
