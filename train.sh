#!/bin/bash
# Headless training script for neuroevolution
# Usage: ./train.sh [options]
#
# Options:
#   -p, --population N    Population size (default: 50)
#   -g, --generations N   Max generations (default: 100)
#   -j, --parallel N      Parallel evaluations (default: 10)
#   -t, --eval-time N     Max eval time in seconds (default: 60)
#
# Examples:
#   ./train.sh                           # Default settings
#   ./train.sh -p 100 -g 200 -j 20       # Larger population, more parallel
#   ./train.sh -t 30                     # Shorter evaluation time

set -e

# Find Godot executable
if command -v godot &> /dev/null; then
    GODOT="godot"
elif [ -f "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
else
    echo "Error: Godot not found. Please install Godot or add it to PATH."
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Starting headless training..."
echo "Press Ctrl+C to stop (progress is auto-saved)"
echo ""

# Run headless training
"$GODOT" --headless --path "$SCRIPT_DIR" --script res://headless_trainer.gd "$@"
