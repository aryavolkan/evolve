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

import argparse
import json
import math
import os
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path

import wandb

# Sweep configuration - hyperparameters to search
SWEEP_CONFIG = {
    'method': 'bayes',
    'metric': {'name': 'avg_fitness', 'goal': 'maximize'},
    'parameters': {
        # Population (120-150 dominated top runs)
        'population_size': {'values': [120, 150]},

        # Selection (20-25 in top configs)
        'elite_count': {'values': [15, 20, 25]},

        # Mutation (rate 0.26-0.31, strength 0.08-0.11 in top configs)
        'mutation_rate': {'distribution': 'uniform', 'min': 0.22, 'max': 0.35},
        'mutation_strength': {'distribution': 'uniform', 'min': 0.06, 'max': 0.15},

        # Crossover (0.72-0.75 in top configs)
        'crossover_rate': {'distribution': 'uniform', 'min': 0.65, 'max': 0.80},

        # NEAT topology evolution (always on — NEAT doesn't use hidden_size)
        'use_neat': {'value': True},

        # Training (top runs all reached gen 50; 2 evals won every top run)
        'max_generations': {'value': 50},
        'evals_per_individual': {'value': 2},

        # Parallel arenas per Godot instance (lower to allow multiple workers)
        'parallel_count': {'value': 5},
    }
}

# Paths - auto-detect OS
import platform as _platform

GODOT_PATH = os.getenv("GODOT_PATH", "/home/aryasen/.local/bin/godot") if _platform.system() == "Linux" else "/Applications/Godot.app/Contents/MacOS/Godot"
PROJECT_PATH = Path.home() / "evolve"
if _platform.system() == "Linux":
    GODOT_USER_DATA = Path.home() / ".local/share/godot/app_userdata/Evolve"
else:
    GODOT_USER_DATA = Path.home() / "Library/Application Support/Godot/app_userdata/Evolve"

# Generate unique worker ID for this process
WORKER_ID = uuid.uuid4().hex[:8]


def get_config_path():
    return GODOT_USER_DATA / f"sweep_config_{WORKER_ID}.json"


def get_metrics_path():
    return GODOT_USER_DATA / f"metrics_{WORKER_ID}.json"


def write_config_for_godot(config: dict):
    """Write sweep config so Godot can read it"""
    GODOT_USER_DATA.mkdir(parents=True, exist_ok=True)
    config_path = get_config_path()
    cfg = dict(config)
    # Ensure parallel_count is always set (sweep may not include it)
    if 'parallel_count' not in cfg:
        cfg['parallel_count'] = SWEEP_CONFIG['parameters'].get('parallel_count', {}).get('value', 5)
    with open(config_path, 'w') as f:
        json.dump(cfg, f, indent=2)
    print(f"  Config written: {config_path}")


def clear_metrics():
    """Clear old metrics file"""
    metrics_path = get_metrics_path()
    if metrics_path.exists():
        metrics_path.unlink()


def cleanup_worker_files():
    """Remove worker-specific config and metrics files"""
    for path in [get_config_path(), get_metrics_path()]:
        try:
            if path.exists():
                path.unlink()
        except OSError:
            pass


def run_godot_training(timeout_minutes: int = 20) -> float:
    """Launch Godot in headless training mode and monitor progress"""

    clear_metrics()

    # Build command with worker ID
    cmd = [
        GODOT_PATH,
        "--path", str(PROJECT_PATH),
        "--headless",
        "--",
        "--auto-train",
        f"--worker-id={WORKER_ID}",
    ]

    print(f"  Starting Godot (timeout: {timeout_minutes}m, worker: {WORKER_ID})...")

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )

    start_time = time.time()
    last_gen = -1
    best_fitness = 0
    last_avg_fitness = 0
    metrics_path = get_metrics_path()

    # Running aggregates for derived metrics
    best_fitness_history = []
    avg_fitness_history = []

    try:
        while time.time() - start_time < timeout_minutes * 60:
            # Check if process died
            if proc.poll() is not None:
                print("  Godot process ended")
                break

            # Read metrics
            try:
                if metrics_path.exists():
                    with open(metrics_path) as f:
                        data = json.load(f)

                    gen = data.get('generation', 0)
                    if gen > last_gen:
                        last_gen = gen
                        best_fitness = data.get('all_time_best', 0)
                        gen_best = data.get('best_fitness', 0)
                        gen_avg = data.get('avg_fitness', 0)
                        last_avg_fitness = gen_avg

                        # Track history for aggregates
                        best_fitness_history.append(gen_best)
                        avg_fitness_history.append(gen_avg)

                        # Compute derived metrics
                        mean_best = sum(best_fitness_history) / len(best_fitness_history)
                        mean_avg = sum(avg_fitness_history) / len(avg_fitness_history)
                        max_best = max(best_fitness_history)
                        improvement_rate = (best_fitness_history[-1] - best_fitness_history[0]) / max(len(best_fitness_history), 1) if len(best_fitness_history) > 1 else 0
                        fitness_std = (sum((x - gen_avg) ** 2 for x in avg_fitness_history) / len(avg_fitness_history)) ** 0.5 if avg_fitness_history else 0

                        # Log to W&B
                        wandb.log({
                            # Core fitness
                            'generation': gen,
                            'best_fitness': gen_best,
                            'avg_fitness': gen_avg,
                            'min_fitness': data.get('min_fitness', 0),
                            'all_time_best': best_fitness,
                            # Score breakdown
                            'avg_kill_score': data.get('avg_kill_score', 0),
                            'avg_powerup_score': data.get('avg_powerup_score', 0),
                            'avg_survival_score': data.get('avg_survival_score', 0),
                            # Evolution state
                            'stagnation': data.get('generations_without_improvement', 0),
                            'population_size': data.get('population_size', 0),
                            'evals_per_individual': data.get('evals_per_individual', 0),
                            # Curriculum
                            'curriculum_stage': data.get('curriculum_stage', 0),
                            'curriculum_label': data.get('curriculum_label', ''),
                            # Training config
                            'time_scale': data.get('time_scale', 0),
                            'parallel_count': int(wandb.config.get('parallel_count', 5)),
                            # MAP-Elites
                            'map_elites_best': data.get('map_elites_best', 0),
                            'map_elites_coverage': data.get('map_elites_coverage', 0),
                            'map_elites_occupied': data.get('map_elites_occupied', 0),
                            # NSGA-II / NEAT
                            'pareto_front_size': data.get('pareto_front_size', 0),
                            'neat_species_count': data.get('neat_species_count', 0),
                            'neat_compatibility_threshold': data.get('neat_compatibility_threshold', 0),
                            'hypervolume': data.get('hypervolume', 0),
                            # Derived aggregates
                            'mean_best_fitness': mean_best,
                            'mean_avg_fitness': mean_avg,
                            'max_best_fitness': max_best,
                            'fitness_std_dev': fitness_std,
                            'improvement_rate': improvement_rate,
                        })

                        print(f"    Gen {gen:3d}: best={best_fitness:.1f}, avg={gen_avg:.1f}")

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
        cleanup_worker_files()

    return best_fitness, last_avg_fitness, last_gen


def train():
    """Single training run with W&B sweep config"""

    run = wandb.init()
    wandb.define_metric("generation")
    wandb.define_metric("*", step_metric="generation")
    config = wandb.config

    print(f"\n{'='*60}")
    print(f"Starting sweep run: {run.name} (worker: {WORKER_ID})")
    print(f"Config: pop={config.population_size}, neat={config.get('use_neat', False)}, "
          f"elite={config.elite_count}, mut={config.mutation_rate:.2f}")
    print(f"{'='*60}")

    # Write config for Godot to read
    write_config_for_godot(config)

    # Run training
    # 5 min/gen when pop*evals/parallel = 60 (e.g. pop=150, evals=2, parallel=5)
    parallel = config.get('parallel_count', SWEEP_CONFIG['parameters'].get('parallel_count', {}).get('value', 5))
    evals_per_gen = config.population_size * config.evals_per_individual / parallel
    min_per_gen = 5 * evals_per_gen / 60
    timeout = int(math.ceil(config.max_generations * min_per_gen))
    best, final_avg, total_gens = run_godot_training(timeout_minutes=timeout)

    # Log final summaries
    wandb.summary['final_best_fitness'] = best
    wandb.summary['final_avg_fitness'] = final_avg
    wandb.summary['total_generations'] = total_gens
    wandb.summary['parallel_count'] = config.get('parallel_count', 5)
    print(f"  Final best fitness: {best:.1f}")

    wandb.finish()


def main():
    parser = argparse.ArgumentParser(description='Overnight W&B sweep for Godot neuroevolution')
    parser.add_argument('--hours', type=float, default=8, help='Hours to run sweep')
    parser.add_argument('--project', default='evolve-neuroevolution', help='W&B project name')
    parser.add_argument('--count', type=int, default=None, help='Max number of runs (default: unlimited)')
    parser.add_argument('--join', type=str, default=None, help='Join an existing sweep by ID instead of creating a new one')
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

    print("Starting W&B sweep")
    print(f"  Worker ID: {WORKER_ID}")
    print(f"  Project: {args.project}")
    print(f"  Duration: {args.hours} hours")
    print(f"  Godot: {GODOT_PATH}")
    print(f"  Project: {PROJECT_PATH}")

    # Create or join sweep
    if args.join:
        sweep_id = args.join
        print(f"\nJoining existing sweep: {sweep_id}")
    else:
        sweep_id = wandb.sweep(SWEEP_CONFIG, project=args.project)
    print(f"Sweep URL: https://wandb.ai/{args.project}/sweeps/{sweep_id}")

    # Handle Ctrl+C gracefully
    def signal_handler(sig, frame):
        print("\n\nSweep interrupted. Cleaning up...")
        cleanup_worker_files()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Parse entity/project for wandb.agent
    if '/' in args.project:
        entity, project = args.project.split('/', 1)
    else:
        entity, project = None, args.project

    # Run sweep agent
    wandb.agent(sweep_id, function=train, count=args.count, entity=entity, project=project)


if __name__ == '__main__':
    main()
