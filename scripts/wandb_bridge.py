#!/usr/bin/env python3
"""
W&B Bridge for Godot Neuroevolution Training

Watches metrics.json written by Godot and logs to Weights & Biases.

Usage:
    python wandb_bridge.py --project evolve-neuroevolution

The script watches ~/Library/Application Support/Godot/app_userdata/evolve/metrics.json
and logs each generation's metrics to W&B.
"""

import argparse
import os
import sys

# Import shared utilities
sys.path.insert(0, os.path.expanduser("~/Projects/shared-evolve-utils"))
from godot_wandb import godot_user_dir, read_metrics, poll_metrics  # noqa: E402

import wandb  # noqa: E402


EVOLVE_LOG_KEYS = [
    "generation", "best_fitness", "avg_fitness", "min_fitness",
    "avg_kill_score", "avg_powerup_score", "avg_survival_score",
    "all_time_best", "generations_without_improvement",
    # Co-evolution (logged when present)
    "enemy_best_fitness", "enemy_avg_fitness", "enemy_min_fitness",
    "enemy_all_time_best", "hof_size",
]


def run_bridge(project_name: str, run_name: str = None):
    """Watch metrics file and log to W&B."""
    metrics_path = godot_user_dir("evolve") / "metrics.json"

    run = wandb.init(
        project=project_name,
        name=run_name or f"godot-bridge-{int(__import__('time').time())}",
    )

    print(f"W&B run: {run.url}")
    print(f"Watching: {metrics_path}")
    print("Start training in Godot (press T), metrics will be logged here.")
    print("Press Ctrl+C to stop.\n")

    try:
        poll_metrics(
            run, metrics_path,
            max_generations=9999,  # Bridge runs until interrupted
            poll_interval=2.0,
            max_stale=300,  # 10 minutes tolerance
            log_keys=EVOLVE_LOG_KEYS,
        )
    except KeyboardInterrupt:
        print("\nStopped by user")

    # Final summary
    final = read_metrics(metrics_path)
    if final:
        wandb.summary["final_generation"] = final.get("generation", 0)
        wandb.summary["final_best_fitness"] = final.get("all_time_best", 0)
        wandb.summary["final_avg_fitness"] = final.get("avg_fitness", 0)

    wandb.finish()
    print("W&B run finished.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="W&B bridge for Godot neuroevolution")
    parser.add_argument("--project", default="evolve-neuroevolution", help="W&B project name")
    parser.add_argument("--name", default=None, help="W&B run name")
    args = parser.parse_args()

    run_bridge(args.project, args.name)
