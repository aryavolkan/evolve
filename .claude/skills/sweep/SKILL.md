---
name: sweep
description: Launch a W&B hyperparameter sweep, check sweep status, or join an existing sweep. Use when user wants to run a sweep, check sweep status, start hyperparameter search, or tune training parameters.
disable-model-invocation: true
---

# W&B Hyperparameter Sweep

Launch, monitor, or join a Weights & Biases hyperparameter sweep that runs Godot neuroevolution training in headless mode.

## Current State
- Virtual env: !`test -d .venv && echo "exists" || echo "missing"`
- W&B logged in: !`source .venv/bin/activate 2>/dev/null && python -c "import wandb; wandb.login(anonymous='never'); print('yes')" 2>/dev/null || echo "no"`

## Instructions

First, check if the user's arguments start with `status`. If so, follow the **Status** instructions. Otherwise, follow the **Launch/Join** instructions.

---

### Status: `/sweep status [SWEEP_ID]`

Query the W&B API for sweep status. If a sweep ID is provided, show details for that sweep. Otherwise, list all sweeps.

1. Activate the virtual environment:
   ```bash
   source .venv/bin/activate
   ```

2. Run this Python snippet to query sweep info:
   ```bash
   python -c "
   import wandb
   api = wandb.Api()
   # If SWEEP_ID provided, show detailed status for that sweep
   # If no SWEEP_ID, list all sweeps in the project
   "
   ```

   **Listing all sweeps (no ID):**
   - Query `api.project('evolve-neuroevolution').sweeps()`
   - Show a table: Sweep ID, State, Run Count, URL

   **Detailed status (with ID):**
   - Query `api.sweep('aryavolkan-personal/evolve-neuroevolution/SWEEP_ID')`
   - Show: state, total runs, run state breakdown (finished/running/failed/crashed)
   - Show sweep parameters
   - Show top 10 runs sorted by `best_fitness` (name, state, best_fitness, generation, duration)
   - Show hyperparameter configs of the top 3 runs
   - Summarize emerging patterns in the top configs

3. Report the dashboard URL for the sweep.

   **Examples:**
   - `/sweep status` — List all sweeps
   - `/sweep status 32g71hrl` — Detailed status for a specific sweep

---

### Launch/Join: `/sweep [OPTIONS]`

1. Ensure the Python virtual environment is set up:
   ```bash
   source .venv/bin/activate
   ```
   If `.venv` doesn't exist, create it:
   ```bash
   python3 -m venv .venv && source .venv/bin/activate && pip install wandb
   ```

2. Verify W&B login:
   ```bash
   wandb login
   ```

3. Run the sweep with user-provided arguments (or defaults):
   ```bash
   python scripts/overnight_sweep.py $ARGUMENTS
   ```

   Default: `--hours 8 --project evolve-neuroevolution`

   **Common options:**
   - `--hours N` — Duration to run (default: 8)
   - `--project NAME` — W&B project name (default: evolve-neuroevolution)
   - `--count N` — Max number of runs (default: unlimited)
   - `--join SWEEP_ID` — Join an existing sweep

   **Examples:**
   - `/sweep` — 8-hour sweep with defaults
   - `/sweep --hours 2` — Quick 2-hour sweep
   - `/sweep --hours 12 --count 20` — 12 hours, max 20 runs
   - `/sweep --join 32g71hrl` — Join an existing sweep

4. Report the sweep URL back to the user so they can monitor progress in the W&B dashboard.
