#!/usr/bin/env python3
"""
Offline evolution training - runs locally without internet, syncs to W&B later.

Runs a predefined schedule of hyperparameter configs, starting with small populations
and progressively increasing complexity.
"""
import json
import os
import subprocess
import time
import uuid
from datetime import datetime

import wandb

# Paths
GODOT_PATH = "/Applications/Godot.app/Contents/MacOS/Godot"
PROJECT_PATH = os.path.expanduser("~/Projects/evolve")
GODOT_USER_DIR = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/evolve")

# Progressive config schedule - starts small, increases complexity
# Format: (population, hidden_size, elite_count, mutation_rate, crossover_rate, evals_per_individual)
# NOTE: Skipping H48+ configs - they're 10-20x slower and timeout before completing meaningful gens
CONFIG_SCHEDULE = [
    # Phase 1: Quick exploration with small populations (30-40 min total) - COMPLETED
    (50, 32, 10, 0.15, 0.7, 2),   # Baseline - DONE (103,687)
    (50, 16, 5, 0.20, 0.6, 2),    # Smaller network, more mutation - DONE (100,842)
    (50, 32, 15, 0.10, 0.8, 2),   # More elitism, less mutation (was 48->32)
    (50, 32, 10, 0.25, 0.5, 2),   # High mutation, low crossover - DONE (74,233)

    # Phase 2: Medium populations (60-90 min total)
    (100, 32, 10, 0.15, 0.7, 2),  # Standard config, larger pop - DONE (79,375)
    (100, 32, 15, 0.10, 0.8, 2),  # Higher elitism (was H48)
    (100, 32, 10, 0.20, 0.6, 2),  # Higher mutation, 2 evals (was 3)
    (100, 32, 20, 0.12, 0.75, 2), # Max elitism, balanced

    # Phase 3: Large populations (90-150 min total)
    (150, 32, 15, 0.15, 0.7, 2),  # Scale up - RUNNING
    (150, 32, 20, 0.10, 0.8, 2),  # Max elitism (was H64)
    (150, 32, 15, 0.20, 0.6, 2),  # Higher mutation (was H48)

    # Phase 4: Maximum scale (150-240 min total)
    (200, 32, 20, 0.15, 0.7, 2),  # Max population (was H48)
    (200, 32, 20, 0.10, 0.8, 2),  # Max pop + max elitism (was H64, 3 evals)
]

# Fixed training parameters
FIXED_PARAMS = {
    'max_generations': 50,
    'time_scale': 16.0,
    'parallel_count': 10,
    'mutation_strength': 0.3,
}


def get_metrics_path(worker_id=None):
    """Get metrics path, optionally with worker-specific suffix"""
    if worker_id:
        return os.path.join(GODOT_USER_DIR, f"metrics_{worker_id}.json")
    return os.path.join(GODOT_USER_DIR, "metrics.json")


def get_config_path(worker_id=None):
    """Get config path, optionally with worker-specific suffix"""
    if worker_id:
        return os.path.join(GODOT_USER_DIR, f"sweep_config_{worker_id}.json")
    return os.path.join(GODOT_USER_DIR, "sweep_config.json")


def write_config_for_godot(config, worker_id=None):
    """Write config so Godot can read it"""
    config_path = get_config_path(worker_id)
    os.makedirs(os.path.dirname(config_path), exist_ok=True)

    config_dict = dict(config)
    if worker_id:
        config_dict['worker_id'] = worker_id

    with open(config_path, 'w') as f:
        json.dump(config_dict, f)


def run_godot_training(timeout_minutes=30, worker_id=None, visible=False, max_retries=2, config=None):
    """Launch Godot in training mode"""

    metrics_path = get_metrics_path(worker_id)

    # Clear old metrics
    if os.path.exists(metrics_path):
        os.remove(metrics_path)

    # Build command
    cmd = [GODOT_PATH, "--path", PROJECT_PATH]

    if not visible:
        cmd.extend(["--headless", "--rendering-driver", "dummy"])

    cmd.extend(["--", "--auto-train"])

    # Add worker ID if running multiple instances
    if worker_id:
        cmd.append(f"--worker-id={worker_id}")

    print(f"Starting Godot training (timeout: {timeout_minutes}m, worker: {worker_id or 'default'})...")

    start_time = time.time()
    last_gen = -1
    best_fitness = 0
    retries = 0

    # Track metrics history for summary stats
    fitness_history = []
    avg_fitness_history = []

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    while time.time() - start_time < timeout_minutes * 60:
        # Check if process died unexpectedly
        if proc.poll() is not None:
            exit_code = proc.returncode
            elapsed = time.time() - start_time
            # If it died early (< 80% of expected time) and we have retries left, restart
            if exit_code != 0 and retries < max_retries and elapsed < timeout_minutes * 60 * 0.8:
                retries += 1
                stderr_out = proc.stderr.read().decode('utf-8', errors='replace')[-500:]
                print(f"Godot crashed (exit {exit_code}, {elapsed:.0f}s in). Retry {retries}/{max_retries}...")
                if stderr_out.strip():
                    print(f"  stderr: {stderr_out.strip()[:200]}")
                wandb.log({"crash_retry": retries}, step=last_gen if last_gen >= 0 else 0)
                time.sleep(3)  # Brief cooldown before retry
                # Clear stale metrics
                if os.path.exists(metrics_path):
                    os.remove(metrics_path)
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                continue
            else:
                print(f"Godot process ended (exit {exit_code}, {retries} retries used)")
                break

        # Read metrics
        try:
            with open(metrics_path) as f:
                data = json.load(f)

            gen = data.get('generation', 0)
            if gen > last_gen:
                last_gen = gen
                best_fitness = data.get('all_time_best', 0)
                current_best = data.get('best_fitness', 0)
                avg_fitness = data.get('avg_fitness', 0)

                # Track history for summary
                fitness_history.append(current_best)
                avg_fitness_history.append(avg_fitness)

                # Log all available metrics with explicit step
                wandb.log({
                    'generation': gen,
                    'best_fitness': current_best,
                    'avg_fitness': avg_fitness,
                    'min_fitness': data.get('min_fitness', 0),
                    'all_time_best': best_fitness,
                    'stagnation': data.get('generations_without_improvement', 0),
                    # Score breakdown (if available)
                    'avg_kill_score': data.get('avg_kill_score', 0),
                    'avg_powerup_score': data.get('avg_powerup_score', 0),
                    'avg_survival_score': data.get('avg_survival_score', 0),
                }, step=gen)

                print(f"  Gen {gen}: best={best_fitness:.1f}, avg={avg_fitness:.1f}")

                # Check if training complete (hit max generations or stagnation)
                if config and gen >= config.get('max_generations', 50):
                    print("Max generations reached")
                    break

                # Check if Godot signaled training complete
                if data.get('training_complete', False):
                    print("Training complete signal received")
                    break

        except (json.JSONDecodeError, FileNotFoundError):
            pass

        time.sleep(2)

    # Clean up
    proc.terminate()
    proc.wait(timeout=5)

    # Clean up worker-specific files
    if worker_id:
        for path in [metrics_path, get_config_path(worker_id)]:
            if os.path.exists(path):
                try:
                    os.remove(path)
                except Exception:
                    pass

    # Return metrics for summary
    return {
        'best_fitness': best_fitness,
        'generations': last_gen,
        'fitness_history': fitness_history,
        'avg_fitness_history': avg_fitness_history,
    }


def run_offline_training_schedule(visible=False, start_from=0, limit=None):
    """Run through the predefined config schedule in offline mode"""

    # Set wandb to offline mode
    os.environ['WANDB_MODE'] = 'offline'

    print("="*80)
    print("OFFLINE TRAINING MODE")
    print("="*80)
    print(f"Total configs in schedule: {len(CONFIG_SCHEDULE)}")
    if limit:
        print(f"Limited to first {limit} configs")
    print(f"Starting from config #{start_from}")
    print(f"Mode: {'VISIBLE' if visible else 'HEADLESS'}")
    print(f"\nRuns will be saved locally to: {os.getcwd()}/wandb/")
    print("To sync later: wandb sync wandb/offline-run-*")
    print("="*80)
    print()

    # Determine which configs to run
    configs_to_run = CONFIG_SCHEDULE[start_from:start_from+limit] if limit else CONFIG_SCHEDULE[start_from:]

    for idx, (pop_size, hidden_size, elite_count, mutation_rate, crossover_rate, evals) in enumerate(configs_to_run, start=start_from):
        config_num = idx + 1
        total_configs = len(CONFIG_SCHEDULE)

        print(f"\n{'='*80}")
        print(f"CONFIG {config_num}/{total_configs} - Population: {pop_size}, Hidden: {hidden_size}")
        print(f"{'='*80}")

        # Build full config
        config = {
            'population_size': pop_size,
            'hidden_size': hidden_size,
            'elite_count': elite_count,
            'mutation_rate': mutation_rate,
            'crossover_rate': crossover_rate,
            'evals_per_individual': evals,
            **FIXED_PARAMS
        }

        # Print config
        print("\nHyperparameters:")
        for key, value in sorted(config.items()):
            print(f"  {key}: {value}")

        # Generate unique worker ID for this run
        worker_id = str(uuid.uuid4())[:8]

        # Initialize wandb run (offline)
        run = wandb.init(
            project='evolve-neuroevolution-offline',
            config=config,
            name=f"offline-pop{pop_size}-h{hidden_size}-run{config_num}",
            tags=['offline', f'pop_{pop_size}', f'phase_{(config_num-1)//4 + 1}']
        )

        # Write config for Godot
        write_config_for_godot(config, worker_id)

        # Calculate timeout based on population, evals, and network size
        # Larger networks are significantly slower (H48 is ~18x slower than H32)
        network_factor = (hidden_size / 32.0) ** 1.5  # Quadratic-ish scaling for network size
        timeout_minutes = int(30 + pop_size * 0.6 * evals * network_factor)
        print(f"\nTimeout: {timeout_minutes} minutes (network_factor: {network_factor:.2f})")
        print(f"Starting training at {datetime.now().strftime('%H:%M:%S')}...")

        # Run training
        results = run_godot_training(
            timeout_minutes=timeout_minutes,
            worker_id=worker_id,
            visible=visible,
            config=config
        )

        # Log summary statistics
        wandb.summary['final_best_fitness'] = results['best_fitness']
        wandb.summary['total_generations'] = results['generations']

        if results['fitness_history']:
            wandb.summary['mean_best_fitness'] = sum(results['fitness_history']) / len(results['fitness_history'])
            wandb.summary['max_best_fitness'] = max(results['fitness_history'])

        if results['avg_fitness_history']:
            wandb.summary['mean_avg_fitness'] = sum(results['avg_fitness_history']) / len(results['avg_fitness_history'])
            wandb.summary['final_avg_fitness'] = results['avg_fitness_history'][-1]

        # Finish run
        wandb.finish()

        print(f"\n✓ Config {config_num} complete!")
        print(f"  Best fitness: {results['best_fitness']:.1f}")
        print(f"  Generations: {results['generations']}")
        print(f"  Finished at {datetime.now().strftime('%H:%M:%S')}")

        # Brief pause between runs
        if idx < len(configs_to_run) - 1:
            print("\nPausing 5 seconds before next config...\n")
            time.sleep(5)

    print("\n" + "="*80)
    print("ALL CONFIGS COMPLETE!")
    print("="*80)
    print(f"\nRuns saved to: {os.getcwd()}/wandb/")
    print("\nTo upload results when back online:")
    print("  cd overnight-agent")
    print("  source venv/bin/activate")
    print("  wandb sync wandb/")
    print()


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Run offline training with predefined config schedule')
    parser.add_argument('--visible', action='store_true', help='Run with Godot window visible (default: headless)')
    parser.add_argument('--start-from', type=int, default=0, help='Start from config N (0-indexed)')
    parser.add_argument('--limit', type=int, default=None, help='Only run N configs from schedule')
    args = parser.parse_args()

    run_offline_training_schedule(
        visible=args.visible,
        start_from=args.start_from,
        limit=args.limit
    )
