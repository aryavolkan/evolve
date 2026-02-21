#!/usr/bin/env python3
"""
Overnight W&B Sweep for Godot Neuroevolution

Runs hyperparameter search using W&B sweeps, launching Godot in headless mode
for each configuration.

Usage:
    python overnight_sweep.py --hours 8 --project evolve-neuroevolution
    python overnight_sweep.py --join <sweep_id> --project evolve-neuroevolution
"""

import argparse
import os
import sys
import time
from pathlib import Path

import wandb

sys.path.insert(0, os.path.expanduser("~/shared-evolve-utils"))
import platform as _platform  # noqa: E402

from godot_wandb import (  # noqa: E402
    SweepWorker,
    calc_training_timeout,
    compute_derived_metrics,
    create_or_join_sweep,
    define_step_metric,
    godot_user_dir,
    launch_godot,
    log_final_summary,
    read_metrics,
    run_sweep_agent,
)

# ---------------------------------------------------------------------------
# Sweep config
# ---------------------------------------------------------------------------

SWEEP_CONFIG = {
    "method": "bayes",
    "metric": {"name": "avg_fitness", "goal": "maximize"},
    "parameters": {
        # Population (120-150 dominated top runs)
        "population_size": {"values": [120, 150]},
        # Selection
        "elite_count": {"values": [15, 20, 25]},
        # Mutation
        "mutation_rate": {"distribution": "uniform", "min": 0.22, "max": 0.35},
        "mutation_strength": {"distribution": "uniform", "min": 0.06, "max": 0.15},
        # Crossover
        "crossover_rate": {"distribution": "uniform", "min": 0.65, "max": 0.80},
        # NEAT topology evolution
        "use_neat": {"value": True},
        # Training
        "max_generations": {"value": 50},
        "evals_per_individual": {"value": 2},
        # Parallel arenas per Godot instance
        "parallel_count": {"value": 5},
    },
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

if _platform.system() == "Linux":
    GODOT_PATH = os.getenv("GODOT_PATH", "/home/aryasen/.local/bin/godot")
else:
    GODOT_PATH = os.getenv("GODOT_PATH", "/Applications/Godot.app/Contents/MacOS/Godot")

PROJECT_PATH = str(Path.home() / "evolve")
USER_DIR = godot_user_dir("Evolve")

# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

# Module-level worker so signal handler can clean up
_worker: SweepWorker = None


def run_godot_training(config: dict, timeout_minutes: int = 20):
    """Launch Godot in headless training mode and monitor progress."""
    global _worker
    _worker = SweepWorker(USER_DIR)
    _worker.clear_metrics()
    _worker.write_config(config)

    proc = launch_godot(
        PROJECT_PATH,
        godot_path=GODOT_PATH,
        visible=False,
        metrics_path=_worker.metrics_path,
        worker_id=_worker.worker_id,
    )

    start_time = time.time()
    last_gen = -1
    best_fitness = 0
    last_avg_fitness = 0
    best_history: list[float] = []
    avg_history: list[float] = []

    try:
        while time.time() - start_time < timeout_minutes * 60:
            if proc.poll() is not None:
                print("  Godot process ended")
                break

            data = read_metrics(_worker.metrics_path)
            if data and "generation" in data:
                gen = data.get("generation", 0)
                if gen > last_gen:
                    last_gen = gen
                    best_fitness = data.get("all_time_best", 0)
                    gen_best = data.get("best_fitness", 0)
                    gen_avg = data.get("avg_fitness", 0)
                    last_avg_fitness = gen_avg

                    best_history.append(gen_best)
                    avg_history.append(gen_avg)
                    derived = compute_derived_metrics(best_history, avg_history)

                    # Calculate generations per hour
                    elapsed_hours = (time.time() - start_time) / 3600.0
                    gen_per_hour = gen / elapsed_hours if elapsed_hours > 0 else 0

                    wandb.log({
                        # Core fitness
                        "generation": gen,
                        "best_fitness": gen_best,
                        "avg_fitness": gen_avg,
                        "min_fitness": data.get("min_fitness", 0),
                        "all_time_best": best_fitness,
                        # Performance
                        "generations_per_hour": gen_per_hour,
                        # Score breakdown
                        "avg_kill_score": data.get("avg_kill_score", 0),
                        "avg_powerup_score": data.get("avg_powerup_score", 0),
                        "avg_survival_score": data.get("avg_survival_score", 0),
                        # Evolution state
                        "stagnation": data.get("generations_without_improvement", 0),
                        "population_size": data.get("population_size", 0),
                        "evals_per_individual": data.get("evals_per_individual", 0),
                        # Curriculum
                        "curriculum_stage": data.get("curriculum_stage", 0),
                        "curriculum_label": data.get("curriculum_label", ""),
                        # Training config
                        "time_scale": data.get("time_scale", 0),
                        "parallel_count": int(wandb.config.get("parallel_count", 5)),
                        # MAP-Elites
                        "map_elites_best": data.get("map_elites_best", 0),
                        "map_elites_coverage": data.get("map_elites_coverage", 0),
                        "map_elites_occupied": data.get("map_elites_occupied", 0),
                        # NSGA-II / NEAT
                        "pareto_front_size": data.get("pareto_front_size", 0),
                        "neat_species_count": data.get("neat_species_count", 0),
                        "neat_compatibility_threshold": data.get("neat_compatibility_threshold", 0),
                        "hypervolume": data.get("hypervolume", 0),
                        # Derived aggregates
                        **derived,
                    })

                    print(f"    Gen {gen:3d}: best={best_fitness:.1f}, avg={gen_avg:.1f}")

                    if data.get("training_complete", False):
                        print("  Training complete (early stop or max gen)")
                        break

                    if gen >= wandb.config.max_generations:
                        print("  Max generations reached")
                        break

                    # Check for stagnation (no improvement for too long)
                    stagnation = data.get("generations_without_improvement", 0)
                    stagnation_limit = data.get("stagnation_limit", 20)
                    if stagnation >= stagnation_limit:
                        print(f"  Early stopping: No improvement for {stagnation} generations (limit: {stagnation_limit})")
                        break

            time.sleep(3)

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except Exception:
            proc.kill()
        _worker.cleanup()

    return best_fitness, last_avg_fitness, last_gen


def train():
    """Single training run with W&B sweep config."""
    run = wandb.init()
    define_step_metric()
    config = dict(wandb.config)

    # Ensure required fields always present regardless of sweep config
    config.setdefault("time_scale", 16)
    config.setdefault("parallel_count", 5)

    print(f"\n{'=' * 60}")
    print(f"Starting sweep run: {run.name} (worker: {_worker.worker_id if _worker else '?'})")
    print(f"Config: pop={config.get('population_size')}, neat={config.get('use_neat', False)}, "
          f"elite={config.get('elite_count')}, mut={config.get('mutation_rate', 0):.2f}")
    print(f"{'=' * 60}")

    parallel = int(config.get("parallel_count", 5))
    timeout = calc_training_timeout(
        population_size=int(config.get("population_size", 100)),
        evals_per_individual=int(config.get("evals_per_individual", 2)),
        parallel_count=parallel,
        max_generations=int(config.get("max_generations", 50)),
    )

    best, final_avg, total_gens = run_godot_training(config, timeout_minutes=timeout)

    log_final_summary(run, {
        "final_best_fitness": best,
        "final_avg_fitness": final_avg,
        "total_generations": total_gens,
        "parallel_count": parallel,
    }, key_map={
        "final_best_fitness": "final_best_fitness",
        "final_avg_fitness": "final_avg_fitness",
        "total_generations": "total_generations",
        "parallel_count": "parallel_count",
    })

    print(f"  Final best fitness: {best:.1f}")
    wandb.finish()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Overnight W&B sweep for Godot neuroevolution")
    parser.add_argument("--hours", type=float, default=8, help="Hours to run sweep")
    parser.add_argument("--project", default="evolve-neuroevolution", help="W&B project name")
    parser.add_argument("--count", type=int, default=None, help="Max runs (default: unlimited)")
    parser.add_argument("--join", type=str, default=None, help="Join existing sweep by ID")
    args = parser.parse_args()

    if not Path(GODOT_PATH).exists():
        print(f"Error: Godot not found at {GODOT_PATH}")
        sys.exit(1)

    if not Path(PROJECT_PATH).exists():
        print(f"Error: Project not found at {PROJECT_PATH}")
        sys.exit(1)

    print("🧬 Evolve overnight sweep")
    print(f"   Project:  {args.project}")
    print(f"   Duration: {args.hours} hours")
    print(f"   Godot:    {GODOT_PATH}")
    print(f"   Repo:     {PROJECT_PATH}")

    sweep_id = create_or_join_sweep(SWEEP_CONFIG, args.project, sweep_id=args.join)
    run_sweep_agent(
        sweep_id, args.project, train,
        count=args.count,
        cleanup_fn=lambda: _worker.cleanup() if _worker else None,
    )


if __name__ == "__main__":
    main()
