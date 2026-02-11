# overnight_evolve.py
import wandb
import subprocess
import json
import time
from pathlib import Path
import os
import uuid

sweep_config = {
    'method': 'bayes',
    'metric': {'name': 'all_time_best', 'goal': 'maximize'},
    'parameters': {
        # Population
        'population_size': {'values': [50, 100, 150, 200]},

        # Selection
        'elite_count': {'values': [5, 10, 15, 20]},

        # Mutation
        'mutation_rate': {'distribution': 'uniform', 'min': 0.05, 'max': 0.3},
        'mutation_strength': {'distribution': 'uniform', 'min': 0.1, 'max': 0.5},

        # Crossover
        'crossover_rate': {'distribution': 'uniform', 'min': 0.5, 'max': 0.9},

        # Network architecture
        'hidden_size': {'values': [16, 32, 48, 64]},

        # Training
        'max_generations': {'value': 50},
        'evals_per_individual': {'values': [1, 2, 3]},
        'time_scale': {'value': 16.0},  # 16x speed for faster training
        'parallel_count': {'value': 10},  # Reduced from 20 to prevent memory crashes
    }
}

# Paths — configurable via environment variables for cross-platform support
# macOS:   GODOT_PATH=/Applications/Godot.app/Contents/MacOS/Godot
# Linux:   GODOT_PATH=/usr/bin/godot
# Windows: GODOT_PATH=C:/Godot/Godot.exe
GODOT_PATH = os.environ.get("GODOT_PATH", "/Applications/Godot.app/Contents/MacOS/Godot")
PROJECT_PATH = os.environ.get("EVOLVE_PROJECT_PATH", os.path.expanduser("~/Projects/evolve"))


def _default_godot_user_dir() -> str:
    """Return the default Godot user data directory for the current platform."""
    import platform
    system = platform.system()
    if system == "Darwin":
        return os.path.expanduser("~/Library/Application Support/Godot/app_userdata/evolve")
    elif system == "Windows":
        return os.path.join(os.environ.get("APPDATA", ""), "Godot/app_userdata/evolve")
    else:  # Linux and others
        return os.path.expanduser("~/.local/share/godot/app_userdata/evolve")


GODOT_USER_DIR = os.environ.get("GODOT_USER_DIR", _default_godot_user_dir())

# Generate unique worker ID for this process
WORKER_ID = str(uuid.uuid4())[:8]

# Global flag for visible mode (set by argparse, used by train())
VISIBLE_MODE = False


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
    """Write sweep config so Godot can read it"""
    config_path = get_config_path(worker_id)
    os.makedirs(os.path.dirname(config_path), exist_ok=True)

    config_dict = dict(config)
    if worker_id:
        config_dict['worker_id'] = worker_id

    with open(config_path, 'w') as f:
        json.dump(config_dict, f)


def run_godot_training(timeout_minutes=30, worker_id=None, visible=False, max_retries=2):
    """Launch Godot in training mode (headless by default, or with window if visible=True)"""

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
            with open(metrics_path, 'r') as f:
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
                if gen >= wandb.config.max_generations:
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
                except:
                    pass

    # Return metrics for summary
    return {
        'best_fitness': best_fitness,
        'generations': last_gen,
        'fitness_history': fitness_history,
        'avg_fitness_history': avg_fitness_history,
    }


def train():
    """Single training run with W&B sweep config"""

    run = wandb.init()
    config = wandb.config

    # Sync all metrics to generation step
    wandb.define_metric("*", step_metric="generation")

    # Use unique worker ID for this run to allow parallel execution
    worker_id = WORKER_ID

    # Write config for Godot to read
    write_config_for_godot(config, worker_id)

    # Scale timeout with population size and evals_per_individual
    # More evals per individual = more time needed
    evals = config.get('evals_per_individual', 1)
    timeout_minutes = int(30 + config.population_size * 0.6 * evals)
    results = run_godot_training(timeout_minutes=timeout_minutes, worker_id=worker_id, visible=VISIBLE_MODE)

    # Log comprehensive summary statistics
    wandb.summary['final_best_fitness'] = results['best_fitness']
    wandb.summary['total_generations'] = results['generations']

    if results['fitness_history']:
        wandb.summary['mean_best_fitness'] = sum(results['fitness_history']) / len(results['fitness_history'])
        wandb.summary['max_best_fitness'] = max(results['fitness_history'])

    if results['avg_fitness_history']:
        wandb.summary['mean_avg_fitness'] = sum(results['avg_fitness_history']) / len(results['avg_fitness_history'])
        wandb.summary['final_avg_fitness'] = results['avg_fitness_history'][-1]

    wandb.finish()


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--hours', type=float, default=8)
    parser.add_argument('--project', default='evolve-neuroevolution')
    parser.add_argument('--sweep-id', type=str, default=None, help='Join existing sweep instead of creating new one')
    parser.add_argument('--count', type=int, default=None, help='Number of runs for this agent (default: unlimited)')
    parser.add_argument('--visible', action='store_true', help='Run with Godot window visible (default: headless)')
    args = parser.parse_args()

    if args.visible:
        VISIBLE_MODE = True

    if args.sweep_id:
        # Join existing sweep
        sweep_id = args.sweep_id
        print(f"\nJoining sweep: https://wandb.ai/aryavolkan-personal/{args.project}/sweeps/{sweep_id}")
    else:
        # Create new sweep
        sweep_id = wandb.sweep(sweep_config, project=args.project)
        print(f"\nCreated sweep: https://wandb.ai/aryavolkan-personal/{args.project}/sweeps/{sweep_id}")

    print(f"Worker ID: {WORKER_ID}")
    wandb.agent(sweep_id, function=train, count=args.count, project=args.project)
