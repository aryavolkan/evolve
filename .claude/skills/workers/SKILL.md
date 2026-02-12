---
name: workers
description: Check status of sweep worker processes (Python W&B agents and Godot headless training instances). Use when user wants to see running workers, check training progress, or diagnose worker issues.
disable-model-invocation: true
---

# Worker Status

Check the status of W&B sweep worker processes: Python agents and their spawned Godot headless training instances.

## Instructions

Run the worker status script:

```bash
python3 scripts/check_workers.py
```

Present the output directly to the user. If there are warnings, highlight them.
