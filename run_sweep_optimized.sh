#!/bin/bash
cd /home/aryasen/evolve
source .venv/bin/activate
export GODOT_PATH=/home/aryasen/.local/bin/godot

for i in {1..10}; do
    python scripts/overnight_sweep.py --hours 168 --project evolve-neuroevolution --join 84jfx9jj > worker_opt_$i.log 2>&1 &
done

wait
