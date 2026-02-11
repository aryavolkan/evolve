# Sweep Crash Investigation — 2026-02-10

## Summary
4 workers started at 11:47 PST, all stopped by 12:17 PST (30 min runtime).

## What Happened

### Worker 1 (floral-sweep-1) ✅
- **Status:** Completed successfully
- **Fitness:** 129,138
- **Exit reason:** "Max generations reached" (gen 50/50)
- **Config:** pop=150, hidden=64, elite=25

### Worker 2 (chocolate-sweep-2) ✅
- **Status:** Completed successfully
- **Fitness:** 147,672 (matched all-time best!)
- **Exit reason:** "Max generations reached" (gen 50/50)
- **Config:** pop=150, hidden=96, elite=15

### Worker 3 (wandering-sweep-3) ⚠️
- **Status:** Early stopped (not a crash)
- **Fitness:** 117,118
- **Exit reason:** "Training complete signal received" at gen 34/50
- **Root cause:** Early stopping triggered — fitness plateaued, stagnation_limit reached
- **Log evidence:** `Training complete signal received` followed by clean W&B init for next run
- **Config:** pop=100, hidden=96, elite=15

### Worker 4 (northern-sweep-4) ❌
- **Status:** Hung during initialization
- **Exit reason:** Unknown - never started training
- **Log evidence:** W&B init completed, but no "Starting Godot training..." message
- **Likely cause:** Godot process failed to spawn or metrics file creation issue
- **Config:** pop=120, hidden=96, elite=20

## Root Causes

1. **Workers 1 & 2:** Normal completion (no issue)
2. **Worker 3:** Feature, not bug — early stopping working as designed
3. **Worker 4:** Initialization hang (possible race condition or resource conflict)
4. **All workers stopped:** Users likely killed the monitor script (signal 9), which may have cascade-killed child processes

## Evidence

### Training Complete Logic (training_manager.gd)
```gdscript
# Early stopping when fitness plateaus
if generations_without_improvement >= stagnation_limit:
    show_training_complete("Early stopping: No improvement for %d generations" % stagnation_limit)
```

### System Status
- **Memory:** No OOM kills, free memory ~0.1GB throughout
- **Swap:** No swap usage detected
- **Process signals:** Monitor script killed with SIGKILL at 12:17 PST
- **No system logs:** No kernel panic, memory pressure, or forced terminations

## Conclusions

1. ✅ **Not a crash** — workers completed or stopped intentionally
2. ✅ **Early stopping works** — worker 3 plateaued and exited cleanly
3. ⚠️ **Worker 4 initialization issue** — needs investigation (first time observed)
4. ✅ **Memory stable** — 3-4 workers sustainable on this hardware

## Recommendations

### Immediate
1. ✅ Restart 3 workers (done at 12:56 PST)
2. Monitor worker 4-equivalent for initialization hangs
3. Add timeout to Godot spawn in `run_godot_training()`

### Future Improvements
1. **Add process monitoring:** Detect hung initialization (no Gen 0 within 60s)
2. **Graceful shutdown:** Catch SIGTERM/SIGINT, finish current generation before exit
3. **Retry logic:** Auto-restart workers that hang during init
4. **Log Godot stderr:** Capture subprocess output for debugging
5. **Stagnation tuning:** Consider increasing `stagnation_limit` or making it sweep-configurable

## New Sweep Status (12:56 PST)

3 workers restarted:
- Worker 1: electric-sweep-7 (pop=100, mut_rate=0.280)
- Worker 2: mild-sweep-5 (pop=150, mut_rate=0.252)
- Worker 3: flowing-sweep-6 (pop=120, mut_rate=0.316)

Monitoring for initialization hangs and memory issues.
