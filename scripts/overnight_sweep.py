#!/usr/bin/env python3
"""
Overnight W&B Sweep for Godot Neuroevolution

Runs hyperparameter search using W&B sweeps, launching Godot in headless mode
for each configuration.

Usage:
    python overnight_sweep.py --hours 8 --project evolve-neuroevolution

This will:
1. Create a W&B sweep with the defined hyperparameter ranges
2. Launch Godot headless training for each configuration
3. Log results to W&B for analysis
"""

import wandb
import subprocess
import json
import time
from pathlib import Path
import os
import argparse
import signal
import sys

# Sweep configuration - hyperparameters to search
SWEEP_CONFIG = {
    'method': 'bayes',
    'metric': {'name': 'all_time_best', 'goal': 'maximize'},
    'parameters': {
        # Population
        'population_size': {'values': [50, 100, 150]},

        # Selection
        'elite_count': {'values': [5, 10, 15, 20]},

        # Mutation
        'mutation_rate': {'distribution': 'uniform', 'min': 0.10, 'max': 0.35},
        'mutation_strength': {'distribution': 'uniform', 'min': 0.15, 'max': 0.5},

        # Crossover
        'crossover_rate': {'distribution': 'uniform', 'min': 0.5, 'max': 0.85},

        # Network architecture
        'hidden_size': {'values': [24, 32, 48, 64]},

        # Training
        'max_generations': {'value': 30},  # Keep short for sweep
        'evals_per_individual': {'values': [1, 2]},
    }
}

# Paths - adjust for your system
GODOT_PATH = "/Applications/Godot.app/Contents/MacOS/Godot"
PROJECT_PATH = Path.home() / "Projects/evolve"
GODOT_USER_DATA = Path.home() / "Library/Application Support/Godot/app_userdata/Evolve"
METRICS_PATH = GODOT_USER_DATA / "metrics.json"
CONFIG_PATH = GODOT_USER_DATA / "sweep_config.json"


def write_config_for_godot(config: dict):
    """Write sweep config so Godot can read it"""
    GODOT_USER_DATA.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_PATH, 'w') as f:
        json.dump(dict(config), f, indent=2)
    print(f"  Config written: {CONFIG_PATH}")


def clear_metrics():
    """Clear old metrics file"""
    if METRICS_PATH.exists():
        METRICS_PATH.unlink()


def run_godot_training(timeout_minutes: int = 20) -> float:
    """Launch Godot in headless training mode and monitor progress"""

    clear_metrics()

    # Build command
    cmd = [
        GODOT_PATH,
        "--path", str(PROJECT_PATH),
        "--headless",
        "--",
        "--auto-train",
    ]

    print(f"  Starting Godot (timeout: {timeout_minutes}m)...")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )

    start_time = time.time()
    last_gen = -1
    best_fitness = 0

    try:
        while time.time() - start_time < timeout_minutes * 60:
            # Check if process died
            if proc.poll() is not None:
                print("  Godot process ended")
                break

            # Read metrics
            try:
                if METRICS_PATH.exists():
                    with open(METRICS_PATH, 'r') as f:
                        data = json.load(f)

                    gen = data.get('generation', 0)
                    if gen > last_gen:
                        last_gen = gen
                        best_fitness = data.get('all_time_best', 0)

                        # Log to W&B
                        wandb.log({
                            'generation': gen,
                            'best_fitness': data.get('best_fitness', 0),
                            'avg_fitness': data.get('avg_fitness', 0),
                            'min_fitness': data.get('min_fitness', 0),
                            'avg_kill_score': data.get('avg_kill_score', 0),
                            'avg_powerup_score': data.get('avg_powerup_score', 0),
                            'avg_survival_score': data.get('avg_survival_score', 0),
                            'all_time_best': best_fitness,
                            'stagnation': data.get('generations_without_improvement', 0),
                        })

                        print(f"    Gen {gen:3d}: best={best_fitness:.1f}, avg={data.get('avg_fitness', 0):.1f}")

                        # Check if done
                        if data.get('training_complete', False):
                            print("  Training complete (early stop or max gen)")
                            break

                        if gen >= wandb.config.max_generations:
                            print("  Max generations reached")
                            break

            except (json.JSONDecodeError, FileNotFoundError, KeyError):
                pass

            time.sleep(3)

    finally:
        # Clean up
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()

    return best_fitness


def train():
    """Single training run with W&B sweep config"""

    run = wandb.init()
    config = wandb.config

    print(f"\n{'='*60}")
    print(f"Starting sweep run: {run.name}")
    print(f"Config: pop={config.population_size}, hidden={config.hidden_size}, "
          f"elite={config.elite_count}, mut={config.mutation_rate:.2f}")
    print(f"{'='*60}")

    # Write config for Godot to read
    write_config_for_godot(config)

    # Run training
    best = run_godot_training(timeout_minutes=15)

    # Log final result
    wandb.summary['final_best_fitness'] = best
    print(f"  Final best fitness: {best:.1f}")

    wandb.finish()


def main():
    parser = argparse.ArgumentParser(description='Overnight W&B sweep for Godot neuroevolution')
    parser.add_argument('--hours', type=float, default=8, help='Hours to run sweep')
    parser.add_argument('--project', default='evolve-neuroevolution', help='W&B project name')
    parser.add_argument('--count', type=int, default=None, help='Max number of runs (default: unlimited)')
    args = parser.parse_args()

    # Check Godot exists
    if not Path(GODOT_PATH).exists():
        print(f"Error: Godot not found at {GODOT_PATH}")
        print("Please update GODOT_PATH in this script.")
        sys.exit(1)

    # Check project exists
    if not PROJECT_PATH.exists():
        print(f"Error: Project not found at {PROJECT_PATH}")
        sys.exit(1)

    print(f"Starting W&B sweep")
    print(f"  Project: {args.project}")
    print(f"  Duration: {args.hours} hours")
    print(f"  Godot: {GODOT_PATH}")
    print(f"  Project: {PROJECT_PATH}")

    # Create sweep
    sweep_id = wandb.sweep(SWEEP_CONFIG, project=args.project)
    print(f"\nSweep URL: https://wandb.ai/{args.project}/sweeps/{sweep_id}")

    # Handle Ctrl+C gracefully
    def signal_handler(sig, frame):
        print("\n\nSweep interrupted. Results saved to W&B.")
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    # Run sweep agent
    wandb.agent(sweep_id, function=train, count=args.count)


if __name__ == '__main__':
    main()
