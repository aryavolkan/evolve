#!/usr/bin/env python3
"""
W&B Bridge for Godot Neuroevolution Training

Watches metrics.json written by Godot and logs to Weights & Biases.

Usage:
    python wandb_bridge.py --project evolve-neuroevolution

The script watches ~/Library/Application Support/Godot/app_userdata/Evolve/metrics.json
and logs each generation's metrics to W&B.
"""

import wandb
import json
import time
from pathlib import Path
import argparse
import os


def get_metrics_path():
    """Get the Godot user data path for metrics.json"""
    # macOS path
    base = Path.home() / "Library/Application Support/Godot/app_userdata/Evolve"
    return base / "metrics.json"


def run_bridge(project_name: str, run_name: str = None):
    """Watch metrics file and log to W&B"""

    metrics_path = get_metrics_path()

    # Initialize W&B
    run = wandb.init(
        project=project_name,
        name=run_name or f"godot-run-{int(time.time())}",
    )

    print(f"W&B run: {run.url}")
    print(f"Watching: {metrics_path}")
    print("Start training in Godot (press T), metrics will be logged here.")
    print("Press Ctrl+C to stop.\n")

    last_generation = -1

    try:
        while True:
            try:
                if metrics_path.exists():
                    with open(metrics_path, 'r') as f:
                        data = json.load(f)

                    gen = data.get('generation', 0)
                    if gen > last_generation:
                        last_generation = gen

                        # Log to W&B
                        wandb.log({
                            'generation': gen,
                            'best_fitness': data.get('best_fitness', 0),
                            'avg_fitness': data.get('avg_fitness', 0),
                            'min_fitness': data.get('min_fitness', 0),
                            'avg_kill_score': data.get('avg_kill_score', 0),
                            'avg_powerup_score': data.get('avg_powerup_score', 0),
                            'avg_survival_score': data.get('avg_survival_score', 0),
                            'all_time_best': data.get('all_time_best', 0),
                            'stagnation': data.get('generations_without_improvement', 0),
                        })

                        print(f"Gen {gen:3d} | Best: {data.get('best_fitness', 0):8.1f} | "
                              f"Avg: {data.get('avg_fitness', 0):8.1f} | "
                              f"Kill$: {data.get('avg_kill_score', 0):6.0f} | "
                              f"Pwr$: {data.get('avg_powerup_score', 0):6.0f}")

                        # Check if training complete
                        if data.get('training_complete', False):
                            print("\nTraining complete!")
                            break

            except (json.JSONDecodeError, FileNotFoundError):
                pass

            time.sleep(2)

    except KeyboardInterrupt:
        print("\nStopped by user")

    # Log final summary
    if last_generation >= 0:
        try:
            with open(metrics_path, 'r') as f:
                data = json.load(f)
            wandb.summary['final_generation'] = data.get('generation', 0)
            wandb.summary['final_best_fitness'] = data.get('all_time_best', 0)
            wandb.summary['final_avg_fitness'] = data.get('avg_fitness', 0)
        except:
            pass

    wandb.finish()
    print("W&B run finished.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='W&B bridge for Godot neuroevolution')
    parser.add_argument('--project', default='evolve-neuroevolution', help='W&B project name')
    parser.add_argument('--name', default=None, help='W&B run name')
    args = parser.parse_args()

    run_bridge(args.project, args.name)
