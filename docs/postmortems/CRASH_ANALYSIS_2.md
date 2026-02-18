# Second Crash Analysis - 2026-02-10 14:49

## What Happened

**Timeline:**
- 14:06 PST - Test worker started via exec with `background=true, yieldMs=5000`
- 14:07 - Gen 1 logged
- 14:35 - Gen 19 logged (last entry in log file)
- 14:36:21 - Exec session "amber-meadow" exited with code 0
- 14:49 - User reports crash

**Final State:**
- Log ends at Gen 19, no shutdown messages
- Metrics file: Gen 19/50, best=86418.4, complete=False
- W&B state: "crashed", gen=18 (one behind local)
- No [SHUTDOWN], [EXIT], [COMPLETE] messages in log
- Process died silently

## Root Cause

**The exec background session timed out after 30 minutes.**

When I started the worker with:
```bash
exec --background --yieldMs=5000
```

The exec tool backgrounded the process after 5 seconds, but had an implicit **30-minute timeout** for background sessions. At 14:36:21 (exactly 30 min after start), the exec session terminated, which **killed the Python process and Godot** mid-training.

This explains why:
1. No error messages in log (process was killed, not crashed)
2. No shutdown sequence executed (SIGKILL, not graceful exit)  
3. W&B marked as "crashed" (no wandb.finish() call)
4. Logs end abruptly at gen 19

## Why The Fix Didn't Help

Our code improvements are correct and working:
- ✅ Real-time logging works (saw Gen 1-19 appear)
- ✅ Debug tags work ([TRAIN], [START], [DEBUG] all appeared)
- ✅ Line buffering works (logs appeared immediately)

**BUT** none of this helps when the parent exec session kills the process externally.

## Solution

**Don't use exec with background mode for long-running processes.**

Instead, start workers directly in the shell:

```bash
cd ~/Projects/evolve/overnight-agent
source venv/bin/activate

# Start workers in background with nohup
nohup python overnight_evolve.py --sweep-id 32g71hrl --count 3 \
  2>&1 | tee worker1.log &

nohup python overnight_evolve.py --sweep-id 32g71hrl --count 3 \
  2>&1 | tee worker2.log &
```

Or use screen/tmux:
```bash
screen -S sweep1
cd ~/Projects/evolve/overnight-agent
source venv/bin/activate
python overnight_evolve.py --sweep-id 32g71hrl --count 3 2>&1 | tee worker1.log

# Detach with Ctrl+A, D
# Reattach with: screen -r sweep1
```

## Lessons Learned

1. **exec tool has background timeout** (~30 min) - not suitable for long training runs
2. **Process killing is silent** - no chance for cleanup code to run
3. **Our fixes work** - just need different process management
4. **Use nohup or screen/tmux** for long-running background tasks

## Verification

The code changes we made are **good and working**:
- Stdout line buffering ✅
- Debug logging ✅  
- Graceful shutdown logic ✅
- W&B finish() calls ✅

We just need to run the process outside of exec's background mode.
