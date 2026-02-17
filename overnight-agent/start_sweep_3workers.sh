#!/bin/bash
# Start a new W&B sweep with 3 workers
# Each worker runs 5 experiments then exits

cd ~/Projects/evolve/overnight-agent
source venv/bin/activate

# Set Godot path
export GODOT_PATH=$(which godot)

PROJECT="evolve-neuroevolution"
COUNT=5  # Each worker does 5 runs

echo "=== Starting Sweep with 3 Workers ==="
echo "Project: $PROJECT"
echo "Count per worker: $COUNT"
echo ""

# Start worker 1 (creates the sweep)
echo "[1/3] Starting worker 1 (will create sweep)..."
nohup python overnight_evolve.py \
  --project "$PROJECT" \
  --count $COUNT \
  > worker1.log 2>&1 &
WORKER1_PID=$!

# Wait for sweep to be created (check log)
echo "Waiting for sweep creation..."
sleep 10

# Extract sweep ID from worker 1 log
SWEEP_ID=$(grep "Created sweep:" worker1.log | tail -1 | sed 's|.*/sweeps/||')

if [ -z "$SWEEP_ID" ]; then
  echo "❌ Failed to get sweep ID from worker1.log"
  echo "Check worker1.log for errors"
  exit 1
fi

echo "✅ Sweep created: $SWEEP_ID"
echo "   URL: https://wandb.ai/aryavolkan-personal/$PROJECT/sweeps/$SWEEP_ID"
echo ""

# Start worker 2
echo "[2/3] Starting worker 2..."
nohup python overnight_evolve.py \
  --project "$PROJECT" \
  --sweep-id "$SWEEP_ID" \
  --count $COUNT \
  > worker2.log 2>&1 &
WORKER2_PID=$!
sleep 2

# Start worker 3
echo "[3/3] Starting worker 3..."
nohup python overnight_evolve.py \
  --project "$PROJECT" \
  --sweep-id "$SWEEP_ID" \
  --count $COUNT \
  > worker3.log 2>&1 &
WORKER3_PID=$!
sleep 2

echo ""
echo "=== All 3 workers started ==="
echo "Sweep ID: $SWEEP_ID"
echo "URL: https://wandb.ai/aryavolkan-personal/$PROJECT/sweeps/$SWEEP_ID"
echo ""
echo "Workers:"
echo "  Worker 1: PID $WORKER1_PID → worker1.log"
echo "  Worker 2: PID $WORKER2_PID → worker2.log"
echo "  Worker 3: PID $WORKER3_PID → worker3.log"
echo ""
echo "Monitor with:"
echo "  bash monitor_workers.sh"
echo "  tail -f worker1.log worker2.log worker3.log"
echo ""
echo "Each worker will run $COUNT experiments then exit."
echo "Total: $((COUNT * 3)) experiments"
