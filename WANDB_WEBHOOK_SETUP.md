# wandb Webhook Setup Guide

## ✅ OpenClaw Configuration (DONE)

- ✅ Webhook endpoint configured: `/hooks/wandb`
- ✅ Custom transform created: `~/.openclaw/hooks/transforms/wandb.js`
- ✅ OpenClaw restarted with new config

## 🔐 Webhook Token

**Secure Token (save this):**
```
67f26ce1dfec5149ecd0687da28f848a18868831420e10279c67fe47b71d9670
```

This token is already configured in OpenClaw. You'll need it when setting up the webhook in wandb.

## 🌐 Public Webhook URL

**Endpoint:** `https://mint-desktop.tail1cabdc.ts.net/hooks/wandb`

This URL is accessible via Tailscale Funnel (public HTTPS).

## 📋 wandb Web UI Setup

### Step 1: Navigate to Webhooks Settings

1. Go to: https://wandb.ai/aryavolkan-personal/evolve-neuroevolution/settings
2. Look for "Webhooks" or "Integrations" section
   - If not visible, try: https://wandb.ai/settings/webhooks
   - Or: https://wandb.ai/aryavolkan-personal/settings/webhooks

### Step 2: Create New Webhook

Click "Add Webhook" or "New Webhook" and configure:

**Webhook URL:**
```
https://mint-desktop.tail1cabdc.ts.net/hooks/wandb
```

**Authentication:**
- Method: `Bearer Token` or `Custom Header`
- Header name: `Authorization` (if using Bearer) or `x-openclaw-token`
- Value: `Bearer 67f26ce1dfec5149ecd0687da28f848a18868831420e10279c67fe47b71d9670`
  - OR just: `67f26ce1dfec5149ecd0687da28f848a18868831420e10279c67fe47b71d9670` (if using x-openclaw-token)

**Events to Subscribe:**
Select these events:
- ✅ `run_finished` - Notify when runs complete
- ✅ `run_failed` - Notify when runs fail
- ⚠️ `run_started` (optional) - Can be noisy, only enable if needed
- ⚠️ `sweep_run_created` (optional) - Can be noisy

**Filters (if available):**
- Project: `evolve-neuroevolution` (limit to this project only)
- Sweep ID: `ikc6gtf5` (optional - limit to current sweep)

### Step 3: Test the Webhook

After saving, wandb usually sends a test payload. Check OpenClaw logs to verify:

```bash
# Check OpenClaw logs for webhook receipt
journalctl -u openclaw --follow
# OR if running in terminal:
tail -f ~/.openclaw/logs/gateway.log
```

You should see a log entry showing the wandb webhook was received.

## 🎯 What Happens When Events Arrive

### High Score Runs (fitness > 160,000)
- OpenClaw logs the event to `memory/YYYY-MM-DD.md`
- Checks gap to all-time record (171,069)
- If new record: **immediate notification with 🏆**
- If close (within 5k): **notification with 🔥**
- Checks worker pool status

### Normal Runs
- Logged to memory
- No chat notification (silent background logging)
- Processed on next heartbeat

### Failed Runs
- Logged with error details
- Checks if worker needs restart
- **Immediate notification with ⚠️**

## 🧪 Manual Test

You can test the webhook manually:

```bash
curl -X POST https://mint-desktop.tail1cabdc.ts.net/hooks/wandb \
  -H 'Authorization: Bearer 67f26ce1dfec5149ecd0687da28f848a18868831420e10279c67fe47b71d9670' \
  -H 'Content-Type: application/json' \
  -d '{
    "event_type": "run_finished",
    "event_author": "aryavolkan",
    "project_name": "evolve-neuroevolution",
    "entity_name": "aryavolkan-personal",
    "run_name": "test-run",
    "run_url": "https://wandb.ai/test",
    "summary_metrics": {
      "fitness": 165000,
      "score": 165000
    },
    "sweep_id": "ikc6gtf5"
  }'
```

Expected response: `200 OK` or `202 Accepted`

## 🔍 Troubleshooting

### Webhook not receiving events
1. Verify Tailscale Funnel is running: `tailscale status`
2. Check OpenClaw is running: `openclaw status`
3. Test webhook URL is accessible: `curl https://mint-desktop.tail1cabdc.ts.net/hooks/wandb`
4. Check wandb webhook logs in their UI for delivery failures

### Events being ignored
Check the transform logic in `~/.openclaw/hooks/transforms/wandb.js`:
- Only processes `evolve-neuroevolution` project
- Only acts on `run_finished` and `run_failed` events
- Other events return `action: 'ignore'`

### Authentication errors (401)
- Verify token matches in both places
- Check header format: `Authorization: Bearer <token>` or `x-openclaw-token: <token>`

## 📝 Next Steps

1. Set up webhook in wandb UI (see Step 2 above)
2. Run a test (manual curl or wait for next sweep run)
3. Monitor `memory/YYYY-MM-DD.md` for logged events
4. Celebrate when you beat 171,069! 🎉

## 🔒 Security Notes

- Token is 64 hex characters (256-bit security)
- Webhook endpoint is public (via Funnel) but requires auth token
- Transform validates project name to prevent spam from other projects
- All payloads are treated as untrusted by OpenClaw
