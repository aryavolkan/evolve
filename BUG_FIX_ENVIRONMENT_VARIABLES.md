# Critical Bug Fix: Environment Variables for overnight_evolve.py

## Problem
All wandb sweep workers crashed immediately (exit code 1, 2-7 seconds) when running overnight_evolve.py.

**Root Cause**: 
- Script defaults to macOS paths
- `GODOT_PATH` defaults to `/opt/homebrew/bin/godot` (doesn't exist on Linux)
- `EVOLVE_PROJECT_PATH` defaults to `~/Projects/evolve` (wrong location)

## Investigation Timeline
- **21:08 PST**: All 10 workers completed with fitness=0
- **21:10 PST**: Found Godot loads fine manually with `--auto-train` flag
- **21:15 PST**: Discovered environment variables weren't set
- **21:15 PST**: Confirmed `/opt/homebrew/bin/godot` doesn't exist

## Solution

### Required Environment Variables
```bash
export GODOT_PATH=/usr/local/bin/godot
export EVOLVE_PROJECT_PATH=$HOME/.openclaw/workspace/evolve
```

### Starting Workers (Corrected)
```bash
# Terminal 1-10
cd ~/.openclaw/workspace/evolve
source ~/.venv/wandb-worker/bin/activate

# SET ENVIRONMENT VARIABLES FIRST
export GODOT_PATH=/usr/local/bin/godot
export EVOLVE_PROJECT_PATH=$HOME/.openclaw/workspace/evolve

# Then start worker
python overnight-agent/overnight_evolve.py > worker1.log 2>&1 &
```

### Alternative: Add to Shell RC
Add to `~/.bashrc` or `~/.zshrc`:
```bash
export GODOT_PATH=/usr/local/bin/godot
export EVOLVE_PROJECT_PATH=$HOME/.openclaw/workspace/evolve
```

## Verification
To verify Godot can run:
```bash
export GODOT_PATH=/usr/local/bin/godot
export EVOLVE_PROJECT_PATH=$HOME/.openclaw/workspace/evolve

timeout 15 $GODOT_PATH --headless --path $EVOLVE_PROJECT_PATH -- --auto-train
```

Should output:
```
[NeuralNetworkFactory] Using Rust backend (RustNeuralNetwork)
Gen 0 (seed 1/2): Evaluating 100 individuals...
Training started: pop=100, max_gen=100, parallel=20
```

## Lessons Learned
- Always check environment variable defaults in cross-platform scripts
- Test workers in isolation before scaling to 10 instances
- Check for actual error messages (not just exit codes)
- Verify file paths exist before assuming they're correct

## Status
- ❌ All workers from 20:40-21:08 PST failed due to missing env vars
- ✅ Manual test with correct paths: Working (Rust backend loads)
- 🔄 Ready to restart workers with correct environment
