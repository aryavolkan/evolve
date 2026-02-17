# W&B Integration

## Webhook

**Endpoint:** `https://mint-desktop.tail1cabdc.ts.net/hooks/wandb`  
**Token:** `67f26ce1dfec5149ecd0687da28f848a18868831420e10279c67fe47b71d9670`  
**Transform:** `~/.openclaw/hooks/transforms/wandb.js`

### Events

| Event | Action |
|-------|--------|
| `run_finished` (fitness > 160K) | Alert if near/above all-time record |
| `run_finished` (normal) | Silent log to `memory/YYYY-MM-DD.md` |
| `run_failed` | Immediate ⚠️ notification |

### wandb UI Setup

1. Go to https://wandb.ai/aryavolkan-personal/evolve-neuroevolution/settings
2. Add webhook with URL above + `Authorization: Bearer <token>`
3. Subscribe to: `run_finished`, `run_failed`

### Manual Test

```bash
curl -X POST https://mint-desktop.tail1cabdc.ts.net/hooks/wandb \
  -H 'Authorization: Bearer 67f26ce1dfec5149ecd0687da28f848a18868831420e10279c67fe47b71d9670' \
  -H 'Content-Type: application/json' \
  -d '{"event_type":"run_finished","project_name":"evolve-neuroevolution","run_name":"test","summary_metrics":{"fitness":165000}}'
```

### Troubleshooting

- Funnel down: `tailscale status`
- Gateway down: `openclaw status`
- Auth errors: check header format `Authorization: Bearer <token>`

---

## Sweep Runner

Workers use `overnight-agent/overnight_evolve.py`:

```bash
cd ~/projects/evolve
export GODOT_PATH=/usr/local/bin/godot
export EVOLVE_PROJECT_PATH=$HOME/projects/evolve
nohup ~/.venv/wandb-worker/bin/python overnight-agent/overnight_evolve.py \
  --sweep-id <sweep_id> --count 5 > logs/worker_$(date +%H%M).log 2>&1 &
```

**Never use** `nohup bash -c "..."` — causes 30-min exit. Always invoke Python directly.

### Create a Sweep

```bash
~/.venv/wandb-worker/bin/wandb sweep sweep_full_explore.yaml --project evolve-neuroevolution
```

### Monitor Workers

```bash
python3 ~/.openclaw/workspace/skills/worker-monitor/scripts/check_workers.py
```

Exit 0 = healthy, exit 1 = stuck workers detected (kill their Godot PIDs).

---

## Known Constraints

- **NEAT + NSGA2**: mutually exclusive — NeatEvolution has no `set_objectives()`. Guarded in `standard_training_mode.gd` (commit `8143fa1`).
- **use_memory + NEAT**: memory flag disables batch NN processing even for NEAT (which doesn't need per-individual state). May slow large populations significantly.
- **Target workers:** 5 Python processes, 5 Godot processes.
