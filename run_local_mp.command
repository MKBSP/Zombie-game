#!/bin/bash
# Local multiplayer test: dedicated server + a Human client + a Zombie client,
# all on this machine. One client auto-hosts a room; the other auto-joins it
# (the room code is read from the server log), so both jump into the match.
#
# How to use:
#   - Double-click this file in Finder, OR
#   - In Terminal:  ./run_local_mp.command
#
# To test the Host/Join menu by hand instead, launch a client with no flags:
#   "/Applications/Godot 2.app/Contents/MacOS/Godot" --path .
#
# Close this Terminal window (or press Ctrl+C) to shut the server down.

cd "$(dirname "$0")" || exit 1

GODOT="/Applications/Godot 2.app/Contents/MacOS/Godot"
if [ ! -x "$GODOT" ]; then
  echo "Godot engine not found at: $GODOT"
  echo "Open this file and set GODOT to your Godot app's binary path."
  read -r -p "Press Return to close."
  exit 1
fi

LOG=/tmp/zg_server.log
rm -f "$LOG"

echo "Starting dedicated server (headless, no window)..."
"$GODOT" --headless --path . -- --server > "$LOG" 2>&1 &
SERVER_PID=$!
trap 'echo "Stopping server..."; kill $SERVER_PID 2>/dev/null' EXIT

# Wait for the server to be listening.
for _ in $(seq 1 40); do grep -q "listening on port" "$LOG" && break; sleep 0.5; done

echo "Launching Human client (auto-hosts a room)..."
"$GODOT" --path . -- --autojoin --host --role=human &

# Read the room code the host just created.
CODE=""
for _ in $(seq 1 40); do
  CODE=$(grep -oE "room created: [A-Z0-9]+" "$LOG" | head -1 | awk '{print $3}')
  [ -n "$CODE" ] && break
  sleep 0.5
done

if [ -z "$CODE" ]; then
  echo "Could not read a room code from the server log — check $LOG"
else
  echo "Room code: $CODE — launching Zombie client (auto-joins)..."
  "$GODOT" --path . -- --autojoin --join="$CODE" --role=zombie &
fi

echo ""
echo "Two game windows should open and start the match. Click into a window to control it."
echo "Leave this Terminal open while playing. Ctrl+C (or closing it) stops the server."
wait
