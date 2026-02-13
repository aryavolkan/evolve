#!/bin/bash
# Sweep management helper script
# Usage: ./sweep.sh [start|join|status|parallel] [SWEEP_ID] [--visible]

set -e

PROJECT_DIR="/Users/aryasen/Projects/evolve/overnight-agent"
PROJECT_NAME="evolve-neuroevolution-new"

# Check for --visible flag in any argument
VISIBLE_FLAG=""
for arg in "$@"; do
    if [ "$arg" = "--visible" ]; then
        VISIBLE_FLAG="--visible"
    fi
done

cd "$PROJECT_DIR"
source venv/bin/activate

case "${1:-start}" in
    start)
        echo "Starting new sweep... ${VISIBLE_FLAG:+(visible mode)}"
        python overnight_evolve.py --project "$PROJECT_NAME" $VISIBLE_FLAG
        ;;

    join|parallel)
        if [ -z "$2" ] || [ "$2" = "--visible" ]; then
            echo "Error: Please provide a sweep ID"
            echo "Usage: $0 join <SWEEP_ID> [--visible]"
            exit 1
        fi
        echo "Joining sweep: $2 ${VISIBLE_FLAG:+(visible mode)}"
        python overnight_evolve.py --sweep-id "$2" --project "$PROJECT_NAME" $VISIBLE_FLAG
        ;;

    status)
        echo "=== Running Processes ==="
        ps aux | grep -E "(overnight_evolve|Godot)" | grep -v grep || echo "No running processes"
        echo ""
        echo "=== Recent Runs ==="
        ls -lt "$PROJECT_DIR/wandb/" 2>/dev/null | head -10 || echo "No runs found"
        echo ""
        echo "=== Latest Metrics ==="
        for f in ~/Library/Application\ Support/Godot/app_userdata/evolve/metrics*.json; do
            if [ -f "$f" ]; then
                echo "--- $(basename "$f") ---"
                cat "$f" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Gen {d.get(\"generation\",\"?\")}: best={d.get(\"all_time_best\",0):.0f}, avg={d.get(\"avg_fitness\",0):.0f}')" 2>/dev/null || cat "$f"
            fi
        done
        ;;

    *)
        echo "Usage: $0 [start|join|status|parallel] [SWEEP_ID] [--visible]"
        echo ""
        echo "Commands:"
        echo "  start [--visible]      - Create a new sweep and start the first agent"
        echo "  join <ID> [--visible]  - Join an existing sweep with a new agent"
        echo "  parallel <ID>          - Same as join (start parallel agent)"
        echo "  status                 - Check running sweeps and recent runs"
        echo ""
        echo "Options:"
        echo "  --visible              - Run with Godot window visible (only one at a time)"
        exit 1
        ;;
esac
