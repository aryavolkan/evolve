#!/bin/bash
export PATH="/home/aryasen/.local/bin:$PATH"
export GODOT_PATH="/home/aryasen/.local/bin/godot"
export EVOLVE_PROJECT_PATH="/home/aryasen/evolve"
cd /home/aryasen/evolve
source .venv/bin/activate
exec python overnight-agent/overnight_evolve.py --hours 168 --project evolve-neuroevolution --sweep-id "${SWEEP_ID:-etuc685q}"
