# overnight.sh
timeout 8h python -c "
import wandb
wandb.agent('YOUR_SWEEP_ID', function=train_sweep, project='overnight-training')
"
