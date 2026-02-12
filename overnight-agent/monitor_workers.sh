#!/bin/bash
# Monitor and maintain 4 sweep workers

cd ~/Projects/evolve/overnight-agent
source venv/bin/activate

# Set Godot path for macOS
export GODOT_PATH="/Applications/Godot.app/Contents/MacOS/Godot"

SWEEP_ID="32g71hrl"
PROJECT="evolve-neuroevolution"
TARGET_WORKERS=4

# Count running workers
RUNNING=$(ps aux | grep "overnight_evolve.py --sweep-id $SWEEP_ID" | grep -v grep | wc -l | xargs)

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Current workers: $RUNNING / $TARGET_WORKERS"

if [ "$RUNNING" -lt "$TARGET_WORKERS" ]; then
  NEEDED=$((TARGET_WORKERS - RUNNING))
  echo "⚠️  Need to start $NEEDED worker(s)"
  
  for i in $(seq 1 $NEEDED); do
    LOG_NUM=$((RUNNING + i))
    nohup python overnight_evolve.py --sweep-id $SWEEP_ID --project $PROJECT --count 3 \
      > "worker${LOG_NUM}.log" 2>&1 &
    NEW_PID=$!
    echo "✅ Started worker $LOG_NUM (PID $NEW_PID)"
    sleep 2
  done
else
  echo "✅ All workers running"
fi

# Show running processes
echo ""
echo "Running Workers:"
PIDS=($(ps aux | grep "overnight_evolve.py --sweep-id $SWEEP_ID" | grep -v grep | awk '{print $2}'))
for PID in "${PIDS[@]}"; do
  RUNTIME=$(ps -p $PID -o etime= 2>/dev/null | xargs)
  echo "  PID $PID - runtime $RUNTIME"
done

# Show detailed progress from each worker log
echo ""
echo "Progress by Log File:"
for i in 1 2 3 4; do
  LOG="worker${i}.log"
  if [ -f "$LOG" ]; then
    # Get latest generation info
    LAST_GEN=$(grep "Gen [0-9]" "$LOG" | tail -1 2>/dev/null || echo "")
    # Get latest run name
    RUN_NAME=$(grep "Syncing run" "$LOG" | tail -1 2>/dev/null | sed 's/.*Syncing run //' || echo "")
    
    echo "  Worker $i:"
    
    if [ -n "$RUN_NAME" ]; then
      echo "    Run: $RUN_NAME"
    fi
    
    if [ -n "$LAST_GEN" ]; then
      echo "    $LAST_GEN"
    else
      echo "    Starting..."
    fi
  fi
done

echo ""
echo "Note: PIDs and logs shown separately (mapping not reliable with nohup)"
