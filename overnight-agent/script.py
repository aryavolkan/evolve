# test_sweep.py
import wandb
import random
import time

sweep_config = {
    'method': 'bayes',
    'metric': {'name': 'val_loss', 'goal': 'minimize'},
    'parameters': {
        'lr': {'distribution': 'log_uniform_values', 'min': 1e-5, 'max': 1e-2},
        'hidden_dim': {'values': [64, 128, 256]},
        'dropout': {'distribution': 'uniform', 'min': 0.0, 'max': 0.5},
    }
}

def train():
    run = wandb.init()
    config = wandb.config
    
    for epoch in range(20):
        train_loss = random.random() * config.lr * 100 + config.dropout * 0.5
        val_loss = train_loss + random.random() * 0.1
        
        wandb.log({
            'epoch': epoch,
            'train_loss': train_loss,
            'val_loss': val_loss,
        })
        
        time.sleep(0.5)
    
    wandb.finish()

if __name__ == '__main__':
    # Try using the Api class instead
    api = wandb.Api()
    
    # Or create sweep via CLI first, then use agent
    # For now, let's check what's available
    print(dir(wandb))
