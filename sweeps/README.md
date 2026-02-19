# Sweep configs

This repo keeps the active W&B sweep configs in the project root for easy CLI use:

- **`sweep_optimized.yaml`** — Tight, exploitation-focused ranges based on recent top runs. Use this for pushing the current SOTA.
- **`sweep_full_explore.yaml`** — Wide exploration across architecture and GA settings. Use this when you want to rediscover or challenge assumptions.

## Launching a sweep

From the repo root:

```bash
wandb sweep sweep_optimized.yaml
# or
wandb sweep sweep_full_explore.yaml
```

Then start one or more workers:

```bash
wandb agent <entity>/<project>/<sweep_id>
```

## Current best known results

- **All‑time record:** 196,745.7 fitness (Gen 46, sweep `ikc6gtf5`)
- Previous record: 175,600.9
- Earlier record: 171,069

**Best known params (sweep `x0cst76l`):**

- population_size: **120**
- hidden_size: **80**
- elite_count: **20**
- mutation_rate: **0.270**
- mutation_strength: **0.110**
- crossover_rate: **0.704**
