#!/bin/bash
cd ~/Projects/evolve/overnight-agent
source venv/bin/activate

echo "Starting worker 1..."
nohup python overnight_evolve.py --sweep-id 32g71hrl --project evolve-neuroevolution --count 3 \
  > worker1.log 2>&1 &
WORKER1_PID=$!
echo "Worker 1 started (PID $WORKER1_PID)"

sleep 2

echo "Starting worker 2..."
nohup python overnight_evolve.py --sweep-id 32g71hrl --project evolve-neuroevolution --count 3 \
  > worker2.log 2>&1 &
WORKER2_PID=$!
echo "Worker 2 started (PID $WORKER2_PID)"

echo ""
echo "Workers running:"
echo "  Worker 1: PID $WORKER1_PID, log: worker1.log"
echo "  Worker 2: PID $WORKER2_PID, log: worker2.log"
echo ""
echo "Monitor with:"
echo "  tail -f worker1.log | grep 'Gen [0-9]'"
echo "  ps aux | grep overnight_evolve"
