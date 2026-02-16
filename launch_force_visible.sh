#!/bin/bash
# Force window visibility workaround

set -e

echo "Launching Godot..."
DISPLAY=:0 /usr/local/bin/godot --path . --single-window res://main.tscn > /tmp/godot_forced.log 2>&1 &
GODOT_PID=$!

echo "Godot PID: $GODOT_PID"
echo "Waiting for window to appear..."

# Wait for window to be created
sleep 3

# Find the Godot window
WINDOW_ID=$(DISPLAY=:0 xdotool search --pid $GODOT_PID --class "Godot" | head -1)

if [ -z "$WINDOW_ID" ]; then
    echo "ERROR: Could not find Godot window!"
    echo "Searching all windows..."
    DISPLAY=:0 xdotool search --name "Evolve" || true
    exit 1
fi

echo "Found window ID: $WINDOW_ID"

# Force window to be visible
echo "Forcing window to map and raise..."
DISPLAY=:0 xdotool windowmap $WINDOW_ID
DISPLAY=:0 xdotool windowactivate --sync $WINDOW_ID
DISPLAY=:0 xdotool windowraise $WINDOW_ID
DISPLAY=:0 xdotool windowfocus $WINDOW_ID

# Move to front and center
echo "Moving window to center..."
DISPLAY=:0 xdotool windowmove $WINDOW_ID 640 340

echo "Window should now be visible!"
echo ""
echo "Window info:"
DISPLAY=:0 xwininfo -id $WINDOW_ID | head -15

echo ""
echo "Godot is running. Check your screen!"
echo "To kill: kill $GODOT_PID"

# Keep script running
wait $GODOT_PID
