# overnight_evolve.py Fix Notes

**Date:** 2026-02-10  
**Issue:** Runs crashed mid-training, W&B marked as incomplete despite local completion

## Problems Fixed

### 1. **Stdout Buffering** (Critical)
**Problem:** Print statements weren't appearing in logs until process ended  
**Fix:** Added line buffering at startup:
```python
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)
```
**Impact:** Real-time log visibility, easier debugging

### 2. **Premature Process Termination** (Critical)
**Problem:** Code terminated Godot immediately after detecting `training_complete=true`  
**Fix:** Added 5-second wait before termination to let Godot write final metrics:
```python
if training_completed or max_gen_reached:
    print("[WAIT] Waiting 5s for Godot to finish writing final metrics...")
    time.sleep(5)
    # Read metrics one more time to get final state
    try:
        with open(metrics_path, 'r') as f:
            final_data = json.load(f)
        # Update with final values
    except:
        pass
    break
```
**Impact:** Final metrics properly captured, W&B gets complete data

### 3. **Graceful Shutdown** (High Priority)
**Problem:** `proc.terminate()` + `wait(timeout=5)` was too aggressive  
**Fix:** Extended timeout to 10s, added fallback to kill:
```python
try:
    proc.wait(timeout=10)
    print("[SHUTDOWN] Godot terminated gracefully")
except subprocess.TimeoutExpired:
    print("[SHUTDOWN] Godot didn't terminate, killing forcefully...")
    proc.kill()
    proc.wait()
```
**Impact:** Cleaner process exits, less risk of corrupted files

### 4. **Missing Flush Calls** (Medium Priority)
**Problem:** Print statements weren't flushed, logs appeared out of order  
**Fix:** Added `flush=True` to all print statements  
**Impact:** Logs now appear in correct chronological order

### 5. **Better Debug Logging** (Low Priority, High Value)
**Problem:** Hard to diagnose issues from sparse logs  
**Fix:** Added detailed logging at key points:
- `[START]` - Training begins
- `[DEBUG]` - Godot PID, command, config writes
- `[COMPLETE]` - Max generations or training complete signal
- `[WAIT]` - Waiting for final metrics
- `[FINAL]` - Updated metrics after wait
- `[SHUTDOWN]` - Process termination stages
- `[CLEANUP]` - File cleanup
- `[SUMMARY]` - W&B summary logging
- `[FINISH]` - W&B finalization
- `[DONE]` - Run complete with final stats

**Impact:** Much easier to diagnose future issues

### 6. **Error Handling** (Medium Priority)
**Problem:** Exceptions during training weren't logged properly  
**Fix:** Wrapped `run_godot_training()` in try/except with proper W&B exit:
```python
try:
    results = run_godot_training(...)
except Exception as e:
    print(f"[ERROR] Training failed with exception: {e}", flush=True)
    wandb.finish(exit_code=1)
    raise
```
**Impact:** Failed runs properly reported to W&B

### 7. **Final Metric Read** (Critical)
**Problem:** Code used cached `last_gen` and `best_fitness` from polling loop  
**Fix:** Re-read metrics file after 5s wait to capture any late updates  
**Impact:** W&B summary gets actual final values, not stale cached ones

## Testing Recommendations

1. **Test with 1 worker first:**
   ```bash
   cd ~/Projects/evolve/overnight-agent
   python overnight_evolve.py --sweep-id 32g71hrl --project evolve-neuroevolution --count 1 2>&1 | tee test_run.log
   ```
   - Check for `[DEBUG]` logs appearing in real-time
   - Verify `[COMPLETE]`, `[WAIT]`, `[FINAL]` sequence
   - Confirm W&B run shows as "finished" not "crashed"

2. **Test with 2 workers:**
   ```bash
   # Terminal 1
   python overnight_evolve.py --sweep-id 32g71hrl --count 1 2>&1 | tee worker1.log &
   
   # Terminal 2
   python overnight_evolve.py --sweep-id 32g71hrl --count 1 2>&1 | tee worker2.log &
   ```
   - Check both complete successfully
   - Verify no worker-ID file collisions
   - Check W&B sweep page for both runs

3. **Monitor W&B:**
   - https://wandb.ai/aryavolkan-personal/evolve-neuroevolution/sweeps/32g71hrl
   - Check run status: should be "finished" not "crashed"
   - Check summary metrics: `final_best_fitness`, `total_generations`
   - Check charts: should have data up to gen 50

## Known Limitations

1. **Still no retry on init hang:** Worker 4's initialization hang not addressed  
   - Recommendation: Add timeout check (if no Gen 0 within 60s, restart)

2. **Godot crash detection:** Early-crash detection is heuristic (< 80% of expected time)  
   - Might not catch slow degradation or memory leaks

3. **macOS-specific paths:** Still hardcoded to macOS  
   - Future: Make cross-platform

## Backup

Original version backed up to:
`overnight_evolve_backup_YYYYMMDD_HHMMSS.py`

## Changelog

- **2026-02-10:** Initial fix addressing crash issues from sweep 32g71hrl
  - Added stdout line buffering
  - Added 5s wait before Godot termination
  - Added final metrics re-read
  - Added extensive debug logging
  - Added error handling with proper W&B exit codes
  - Extended process termination timeout
  - Added flush=True to all prints
