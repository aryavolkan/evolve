#!/bin/bash
# Workaround launcher for Godot window visibility bug
# Creates a separate X display and makes it accessible via VNC

set -e

# Kill existing Godot instances
pkill -f "godot.*res://main.tscn" || true

# Start Xvfb on display :99
Xvfb :99 -screen 0 1280x720x24 &
XVFB_PID=$!
export DISPLAY=:99

# Wait for Xvfb to start
sleep 1

# Start x11vnc for remote viewing (port 5900)
x11vnc -display :99 -forever -shared &
VNC_PID=$!

# Launch Godot
/usr/local/bin/godot --path . res://main.tscn &
GODOT_PID=$!

echo "====================================="
echo "Godot launched on virtual display :99"
echo "Connect with VNC client to localhost:5900"
echo "Or use: vncviewer localhost:5900"
echo "====================================="
echo ""
echo "Process IDs:"
echo "  Xvfb: $XVFB_PID"
echo "  x11vnc: $VNC_PID"
echo "  Godot: $GODOT_PID"
echo ""
echo "To stop all: pkill -P $$"

# Wait for Godot to exit
wait $GODOT_PID

# Cleanup
kill $VNC_PID $XVFB_PID 2>/dev/null || true
