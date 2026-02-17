#!/bin/bash
# launch_gui.sh - Launch Evolve game with working display
#
# WORKAROUND for Godot 4.5 + NVIDIA RTX 5070 + Cinnamon/Muffin compositor bug:
# Godot windows are created and rendering correctly, but Muffin compositor fails
# to display them. Root cause: NVIDIA 590.x Vulkan WSI incompatibility with Muffin.
#
# Solution: Xephyr nested X server (confirmed working, no system changes needed)
# Game renders inside a 1280x720 window on your main desktop.
#
# Usage: ./launch_gui.sh [mode]
#   modes: play, watch, train, sandbox, compare, coevol, live, team
#   default: opens the title screen (click to select mode)

set -e

GODOT="${GODOT_PATH:-/usr/local/bin/godot}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DISPLAY_NUM=":3"
RESOLUTION="1280x720"

MODE="${1:-}"
TITLE="Evolve"

# Map friendly mode names to game args
case "$MODE" in
    play)    EXTRA="-- --mode play" ;;
    watch)   EXTRA="-- --mode watch" ;;
    train)   EXTRA="-- --mode train" ;;
    sandbox) EXTRA="-- --mode sandbox" ;;
    compare) EXTRA="-- --mode compare" ;;
    coevol)  EXTRA="-- --mode coevol" ;;
    live)    EXTRA="-- --mode live" ;;
    team)    EXTRA="-- --mode team" ;;
    *)       EXTRA="" ;;
esac

# Kill any leftover Xephyr on our display
pkill -f "Xephyr $DISPLAY_NUM" 2>/dev/null || true
sleep 0.3

echo "Starting Xephyr display $DISPLAY_NUM..."
Xephyr "$DISPLAY_NUM" -screen "$RESOLUTION" -title "$TITLE" -resizeable 2>/dev/null &
XPID=$!

# Wait for Xephyr to be ready
for i in $(seq 1 10); do
    sleep 0.3
    DISPLAY="$DISPLAY_NUM" xdpyinfo &>/dev/null && break
done

echo "Launching Evolve..."
DISPLAY="$DISPLAY_NUM" \
GODOT_PATH="$GODOT" \
EVOLVE_PROJECT_PATH="$PROJECT_DIR" \
    "$GODOT" --path "$PROJECT_DIR" res://main.tscn $EXTRA

# Cleanup
kill $XPID 2>/dev/null || true
echo "Done."
