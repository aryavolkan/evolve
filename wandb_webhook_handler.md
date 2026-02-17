# wandb Webhook Integration

## Endpoint Setup

**Public URL:** `https://mint-desktop.tail1cabdc.ts.net/webhook/wandb`

This endpoint receives notifications from wandb about:
- New sweep runs started
- Runs completed
- New best scores achieved
- Run failures

## Configuration Steps

### 1. Create Webhook in wandb Web UI

1. Go to https://wandb.ai/aryavolkan-personal/evolve-neuroevolution/settings/webhooks
2. Click "Add Webhook"
3. Configure:
   - **URL:** `https://mint-desktop.tail1cabdc.ts.net/webhook/wandb`
   - **Secret:** (generate a secure token - see below)
   - **Events:** Select:
     - `run_finished` - When runs complete
     - `run_failed` - When runs fail
     - `run_queued` - When runs are queued (optional)
     - `sweep_run_created` - When sweep creates new runs (optional)
4. Save

### 2. Generate Webhook Secret

```bash
# Generate a secure random secret
openssl rand -hex 32
```

Store this secret in OpenClaw config under `webhooks.wandb.secret`

### 3. Test Webhook

After configuration, wandb will send a test payload. Check OpenClaw logs to verify receipt.

## Webhook Payload Examples

### Run Finished
```json
{
  "event_type": "run_finished",
  "event_author": "aryavolkan",
  "project_name": "evolve-neuroevolution",
  "entity_name": "aryavolkan-personal",
  "run_name": "graceful-sweep-21",
  "run_url": "https://wandb.ai/...",
  "summary_metrics": {
    "fitness": 170184.5,
    "score": 170184
  },
  "sweep_id": "ikc6gtf5"
}
```

### Run Failed
```json
{
  "event_type": "run_failed",
  "run_name": "...",
  "error_message": "..."
}
```

## OpenClaw Response Actions

When webhook is received, OpenClaw can:
- Log the event to `memory/YYYY-MM-DD.md`
- Alert user if new high score achieved
- Restart workers if pool drops below target
- Track sweep progress in `memory/heartbeat-state.json`
