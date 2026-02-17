#!/usr/bin/env python3
"""
Single W&B-tracked training run with live generation-by-generation logging.
Polls metrics.json instead of parsing stdout for reliability.
"""
import json
import os
import subprocess
import sys
import time

import wandb

# Force unbuffered output
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

# Optimal config from sweep analysis
DEFAULT_CONFIG = {
    "population_size": 120,
    "hidden_size": 80,
    "elite_count": 20,
    "crossover_rate": 0.70,
    "mutation_rate": 0.27,
    "mutation_strength": 0.11,
    "evals_per_individual": 1,
    "max_generations": 100,
    "time_scale": 16,
    "parallel_count": 10
}

# Paths
GODOT_PATH = "/Applications/Godot.app/Contents/MacOS/Godot"
PROJECT_PATH = os.path.expanduser("~/Projects/evolve")
GODOT_USER_DIR = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/evolve")
METRICS_PATH = os.path.join(GODOT_USER_DIR, "metrics.json")
CONFIG_PATH = os.path.join(GODOT_USER_DIR, "sweep_config.json")

# Polling settings
POLL_INTERVAL = 5  # seconds between metrics checks
MAX_WAIT_FOR_START = 30  # seconds to wait for training to start


def write_config(config):
    """Write config for Godot to read"""
    os.makedirs(GODOT_USER_DIR, exist_ok=True)
    with open(CONFIG_PATH, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Config written to {CONFIG_PATH}")


def read_metrics():
    """Read current metrics from Godot's JSON file"""
    try:
        if not os.path.exists(METRICS_PATH):
            return None
        with open(METRICS_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def launch_godot(visible=False):
    """Launch Godot training process"""
    # Clear old metrics
    if os.path.exists(METRICS_PATH):
        os.remove(METRICS_PATH)
        print("Cleared old metrics")

    # Build command
    cmd = [GODOT_PATH, "--path", PROJECT_PATH]

    if not visible:
        cmd.extend(["--headless", "--rendering-driver", "dummy"])

    cmd.extend(["--", "--auto-train"])

    print(f"Launching Godot: {' '.join(cmd)}")
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )

    return process


def wait_for_training_start(timeout=MAX_WAIT_FOR_START):
    """Wait for metrics.json to appear (training started)"""
    print(f"Waiting for training to start (timeout: {timeout}s)...")
    start = time.time()

    while time.time() - start < timeout:
        if os.path.exists(METRICS_PATH):
            print("✓ Training started!")
            return True
        time.sleep(1)

    print("✗ Training didn't start in time")
    return False


def monitor_training(wandb_run, process):
    """Poll metrics.json and log to W&B as generations complete"""
    last_gen = -1

    while True:
        # Check if process is still running
        if process.poll() is not None:
            print(f"\nGodot process exited with code {process.returncode}")
            break

        # Read current metrics
        metrics = read_metrics()
        if not metrics:
            time.sleep(POLL_INTERVAL)
            continue

        current_gen = metrics.get("generation", -1)

        # Log new generation
        if current_gen > last_gen:
            last_gen = current_gen

            # Log all metrics for this generation
            log_data = {
                "generation": current_gen,
                "best_fitness": metrics.get("best_fitness", 0),
                "avg_fitness": metrics.get("avg_fitness", 0),
                "all_time_best": metrics.get("all_time_best", 0),
                "min_fitness": metrics.get("min_fitness", 0),
                "elite_avg_fitness": metrics.get("elite_avg_fitness", 0),
                "fitness_std_dev": metrics.get("fitness_std_dev", 0),
                "improvement_rate": metrics.get("improvement_rate", 0),
                "generations_without_improvement": metrics.get("generations_without_improvement", 0),
                "avg_kill_score": metrics.get("avg_kill_score", 0),
                "avg_powerup_score": metrics.get("avg_powerup_score", 0),
                "avg_survival_score": metrics.get("avg_survival_score", 0),
                "map_elites_coverage": metrics.get("map_elites_coverage", 0),
                "map_elites_occupied": metrics.get("map_elites_occupied", 0),
                "map_elites_best": metrics.get("map_elites_best", 0),
                "curriculum_stage": metrics.get("curriculum_stage", 0),
            }

            wandb_run.log(log_data)

            # Console output
            print(f"Gen {current_gen:2d} | "
                  f"Best: {metrics.get('best_fitness', 0):8.1f} | "
                  f"Avg: {metrics.get('avg_fitness', 0):7.1f} | "
                  f"ATB: {metrics.get('all_time_best', 0):8.1f} | "
                  f"Stagnant: {metrics.get('generations_without_improvement', 0)}/{metrics.get('stagnation_limit', 20)}")

        # Check if training is complete
        if metrics.get("training_complete", False):
            print("\n✓ Training complete!")
            # Log final metrics one more time
            wandb_run.log(metrics)

            # Kill Godot (it doesn't exit on its own after training)
            print("Terminating Godot process...")
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                print("Force killing Godot...")
                process.kill()
                process.wait()

            break

        time.sleep(POLL_INTERVAL)

    return metrics


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Run single W&B-tracked training")
    parser.add_argument("--visible", action="store_true", help="Run with visible window (not headless)")
    parser.add_argument("--name", type=str, default="optimal-config-run", help="W&B run name")
    parser.add_argument("--tags", type=str, nargs="*", default=["manual", "optimal"], help="W&B tags")
    parser.add_argument("--config", type=str, help="Path to custom config JSON")
    args = parser.parse_args()

    # Load config
    config = DEFAULT_CONFIG.copy()
    if args.config:
        with open(args.config) as f:
            custom = json.load(f)
            config.update(custom)

    print("=" * 60)
    print("W&B-Tracked Evolve Training")
    print("=" * 60)
    print(f"Config: {json.dumps(config, indent=2)}")
    print(f"Visible: {args.visible}")
    print(f"Run name: {args.name}")
    print("=" * 60)

    # Write config for Godot
    write_config(config)

    # Initialize W&B
    print("\nInitializing W&B...", flush=True)
    run = wandb.init(
        project="evolve-neuroevolution",
        name=args.name,
        config=config,
        tags=args.tags
    )
    print(f"✓ W&B run: {run.url}", flush=True)

    try:
        # Launch Godot
        print("\nLaunching Godot...", flush=True)
        process = launch_godot(visible=args.visible)
        print(f"✓ Godot started (PID: {process.pid})", flush=True)

        # Wait for training to start
        if not wait_for_training_start():
            print("ERROR: Training failed to start")
            process.kill()
            return 1

        # Monitor and log generations
        final_metrics = monitor_training(run, process)

        # Process should already be terminated by monitor_training
        # But double-check
        if process.poll() is None:
            print("Warning: Process still running, killing...")
            process.kill()
            process.wait()

        print("\n" + "=" * 60)
        print("FINAL RESULTS")
        print("=" * 60)
        if final_metrics:
            print(f"Generations: {final_metrics.get('generation', 0)}")
            print(f"Best fitness: {final_metrics.get('all_time_best', 0):.1f}")
            print(f"Avg fitness: {final_metrics.get('avg_fitness', 0):.1f}")
            print(f"MAP-Elites coverage: {final_metrics.get('map_elites_coverage', 0)*100:.1f}%")
            print(f"Curriculum stage: {final_metrics.get('curriculum_stage', 0)}")
        print("=" * 60)

        return 0

    finally:
        run.finish()
        print("\n✓ W&B run finished")


if __name__ == "__main__":
    sys.exit(main())
