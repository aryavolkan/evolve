#!/usr/bin/env python3
"""
Benchmark Suite for Evolve Neuroevolution Algorithm Comparison

Runs controlled A/B experiments comparing algorithm configurations with
matched hyperparameters, multiple seeds, and structured reports.

Usage:
    python scripts/benchmark.py                          # full-comparison, 3 seeds, 50 gens
    python scripts/benchmark.py --preset neat-vs-fixed   # specific preset
    python scripts/benchmark.py --generations 30 --seeds 5
    python scripts/benchmark.py --parallel 4             # concurrent Godot instances
    python scripts/benchmark.py --wandb                  # log to W&B
"""

import argparse
import json
import math
import signal
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from statistics import mean, stdev

import platform as _platform

# ---------------------------------------------------------------------------
# Paths — auto-detect OS (same pattern as overnight_sweep.py)
# ---------------------------------------------------------------------------
GODOT_PATH = (
    "/usr/local/bin/godot"
    if _platform.system() == "Linux"
    else "/Applications/Godot.app/Contents/MacOS/Godot"
)
PROJECT_PATH = Path.home() / "Projects/evolve"
if _platform.system() == "Linux":
    GODOT_USER_DATA = Path.home() / ".local/share/godot/app_userdata/Evolve"
else:
    GODOT_USER_DATA = Path.home() / "Library/Application Support/Godot/app_userdata/Evolve"

REPORTS_DIR = PROJECT_PATH / "reports" / "benchmarks"
POLL_INTERVAL = 3  # seconds between metrics checks

# ---------------------------------------------------------------------------
# Base config — shared across all presets
# ---------------------------------------------------------------------------
BASE_CONFIG = {
    "population_size": 150,
    "hidden_size": 80,
    "elite_count": 20,
    "mutation_rate": 0.27,
    "mutation_strength": 0.09,
    "crossover_rate": 0.73,
    "evals_per_individual": 2,
    "parallel_count": 5,
    "time_scale": 16.0,
    # Defaults — presets override these
    "use_neat": False,
    "use_nsga2": False,
    "use_memory": False,
    "use_map_elites": True,
    "curriculum_enabled": True,
}

# ---------------------------------------------------------------------------
# Presets — each maps condition name → config overrides
# ---------------------------------------------------------------------------
PRESETS = {
    "neat-vs-fixed": {
        "neat": {"use_neat": True},
        "fixed": {"use_neat": False},
    },
    "curriculum-ablation": {
        "on": {"curriculum_enabled": True},
        "off": {"curriculum_enabled": False},
    },
    "memory-ablation": {
        "on": {"use_memory": True},
        "off": {"use_memory": False},
    },
    "nsga2-ablation": {
        "on": {"use_nsga2": True},
        "off": {"use_nsga2": False},
    },
    "full-comparison": {
        "baseline": {},
        "nsga2": {"use_nsga2": True},
        "map-elites": {"use_map_elites": True},
        "neat": {"use_neat": True},
        "memory": {"use_memory": True},
    },
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def get_config_path(worker_id: str) -> Path:
    return GODOT_USER_DATA / f"sweep_config_{worker_id}.json"


def get_metrics_path(worker_id: str) -> Path:
    return GODOT_USER_DATA / f"metrics_{worker_id}.json"


def write_config(config: dict, worker_id: str) -> None:
    GODOT_USER_DATA.mkdir(parents=True, exist_ok=True)
    with open(get_config_path(worker_id), "w") as f:
        json.dump(config, f, indent=2)


def cleanup_files(worker_id: str) -> None:
    for path in [get_config_path(worker_id), get_metrics_path(worker_id)]:
        try:
            if path.exists():
                path.unlink()
        except OSError:
            pass


def calculate_timeout(config: dict) -> int:
    """Minutes needed for a full run. Same formula as overnight_sweep.py."""
    parallel = config.get("parallel_count", 5)
    pop = config.get("population_size", 150)
    evals = config.get("evals_per_individual", 2)
    gens = config.get("max_generations", 50)
    evals_per_gen = pop * evals / parallel
    min_per_gen = 5 * evals_per_gen / 60
    return int(math.ceil(gens * min_per_gen))


# ---------------------------------------------------------------------------
# Core execution
# ---------------------------------------------------------------------------
def run_single_trial(
    config: dict, worker_id: str, timeout_min: int
) -> dict | None:
    """Launch Godot, poll metrics, return time-series data. Retry once on crash."""

    for attempt in range(2):
        cleanup_files(worker_id)
        write_config(config, worker_id)

        cmd = [
            GODOT_PATH,
            "--path", str(PROJECT_PATH),
            "--headless",
            "--",
            "--auto-train",
            f"--worker-id={worker_id}",
        ]

        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
        )

        start_time = time.time()
        last_gen = -1
        generations = []  # per-gen snapshots
        metrics_path = get_metrics_path(worker_id)
        crash_threshold = timeout_min * 60 * 0.8

        try:
            while time.time() - start_time < timeout_min * 60:
                if proc.poll() is not None:
                    elapsed = time.time() - start_time
                    if elapsed < crash_threshold and attempt == 0:
                        print(f"    [{worker_id}] Godot crashed early ({elapsed:.0f}s), retrying...")
                        break  # retry
                    # Either second attempt or ran long enough — accept what we have
                    break

                try:
                    if metrics_path.exists():
                        with open(metrics_path, "r") as f:
                            data = json.load(f)

                        gen = data.get("generation", 0)
                        if gen > last_gen:
                            last_gen = gen
                            generations.append({
                                "generation": gen,
                                "best_fitness": data.get("best_fitness", 0),
                                "avg_fitness": data.get("avg_fitness", 0),
                                "min_fitness": data.get("min_fitness", 0),
                                "all_time_best": data.get("all_time_best", 0),
                                "avg_kill_score": data.get("avg_kill_score", 0),
                                "avg_powerup_score": data.get("avg_powerup_score", 0),
                                "avg_survival_score": data.get("avg_survival_score", 0),
                                "curriculum_stage": data.get("curriculum_stage", 0),
                                "neat_species_count": data.get("neat_species_count", 0),
                                "map_elites_coverage": data.get("map_elites_coverage", 0),
                                "hypervolume": data.get("hypervolume", 0),
                                "pareto_front_size": data.get("pareto_front_size", 0),
                            })

                            if data.get("training_complete", False):
                                break
                            if gen >= config.get("max_generations", 50):
                                break
                except (json.JSONDecodeError, FileNotFoundError, KeyError):
                    pass

                time.sleep(POLL_INTERVAL)

        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
            cleanup_files(worker_id)

        # If we got data, return it
        if generations:
            wall_time = time.time() - start_time
            return {
                "generations": generations,
                "wall_time_seconds": wall_time,
                "total_generations": len(generations),
            }

        # If first attempt crashed with no data, loop will retry
        if attempt == 0:
            continue

    # Both attempts failed
    return None


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------
def _safe_stdev(values: list[float]) -> float:
    return stdev(values) if len(values) >= 2 else 0.0


def aggregate_trials(trials: list[dict | None]) -> dict:
    """Compute summary statistics across seeds for one condition."""
    valid = [t for t in trials if t is not None]
    n = len(valid)

    if n == 0:
        return {"valid_trials": 0}

    final_bests = [t["generations"][-1]["all_time_best"] for t in valid]
    final_avgs = [t["generations"][-1]["avg_fitness"] for t in valid]
    wall_times = [t["wall_time_seconds"] for t in valid]

    # Convergence generation: first gen where all_time_best >= 50% of final value
    convergence_gens = []
    for t in valid:
        final_val = t["generations"][-1]["all_time_best"]
        threshold = final_val * 0.5
        conv_gen = t["generations"][-1]["generation"]  # default: last gen
        for snap in t["generations"]:
            if snap["all_time_best"] >= threshold:
                conv_gen = snap["generation"]
                break
        convergence_gens.append(conv_gen)

    # Per-generation averaged learning curve (aligned by gen index)
    max_gens = max(t["total_generations"] for t in valid)
    per_gen_avg_best = []
    for i in range(max_gens):
        values = [
            t["generations"][i]["all_time_best"]
            for t in valid
            if i < t["total_generations"]
        ]
        per_gen_avg_best.append(mean(values) if values else 0)

    result = {
        "valid_trials": n,
        "final_best_fitness": {
            "mean": mean(final_bests),
            "std": _safe_stdev(final_bests),
            "min": min(final_bests),
            "max": max(final_bests),
        },
        "final_avg_fitness": {
            "mean": mean(final_avgs),
            "std": _safe_stdev(final_avgs),
        },
        "convergence_generation": {
            "mean": mean(convergence_gens),
            "std": _safe_stdev(convergence_gens),
        },
        "wall_time_seconds": {
            "mean": mean(wall_times),
            "std": _safe_stdev(wall_times),
        },
        "per_generation_avg_best": per_gen_avg_best,
    }

    # Algorithm-specific metrics (only include when non-zero across trials)
    for key in ("neat_species_count", "map_elites_coverage", "hypervolume"):
        values = [
            t["generations"][-1].get(key, 0)
            for t in valid
            if t["generations"][-1].get(key, 0) != 0
        ]
        if values:
            result[key] = {"mean": mean(values), "std": _safe_stdev(values)}

    return result


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def print_summary_table(report: dict) -> None:
    """Print a formatted comparison table to terminal."""
    conditions = report["conditions"]
    names = list(conditions.keys())

    # Header
    print(f"\n{'='*78}")
    print(f"  BENCHMARK: {report['preset']}  |  {report['seeds']} seeds × {report['max_generations']} gens")
    print(f"{'='*78}")
    print(
        f"  {'Condition':<16} {'Best (mean±std)':>20} {'Avg Fit':>12} "
        f"{'Conv Gen':>10} {'Wall (s)':>10} {'N':>4}"
    )
    print(f"  {'-'*72}")

    for name in names:
        agg = conditions[name]["summary"]
        n = agg.get("valid_trials", 0)
        if n == 0:
            print(f"  {name:<16} {'(all trials failed)':>20}")
            continue

        fb = agg["final_best_fitness"]
        fa = agg["final_avg_fitness"]
        cg = agg["convergence_generation"]
        wt = agg["wall_time_seconds"]

        best_str = f"{fb['mean']:,.0f} ± {fb['std']:,.0f}"
        avg_str = f"{fa['mean']:,.0f}"
        conv_str = f"{cg['mean']:.1f}"
        wall_str = f"{wt['mean']:.0f}"

        print(f"  {name:<16} {best_str:>20} {avg_str:>12} {conv_str:>10} {wall_str:>10} {n:>4}")

    # Winner
    winner = report.get("winner")
    if winner:
        print(f"\n  Winner: {winner} (highest mean final best fitness)")
    print()


def save_report(report: dict) -> Path:
    """Save JSON report to reports/benchmarks/."""
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = REPORTS_DIR / f"{report['preset']}_{timestamp}.json"
    with open(path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"Report saved: {path}")
    return path


def log_to_wandb(report: dict, project: str) -> None:
    """Log benchmark results to W&B (lazy import)."""
    try:
        import wandb
    except ImportError:
        print("Warning: wandb not installed, skipping W&B logging")
        return

    run = wandb.init(
        project=project,
        job_type="benchmark",
        config={
            "preset": report["preset"],
            "seeds": report["seeds"],
            "max_generations": report["max_generations"],
            "base_config": report["base_config"],
        },
    )

    # Log summary table as W&B table
    columns = ["condition", "mean_best", "std_best", "mean_avg", "convergence_gen", "valid_trials"]
    table = wandb.Table(columns=columns)
    for name, cond in report["conditions"].items():
        agg = cond["summary"]
        if agg.get("valid_trials", 0) == 0:
            continue
        table.add_data(
            name,
            agg["final_best_fitness"]["mean"],
            agg["final_best_fitness"]["std"],
            agg["final_avg_fitness"]["mean"],
            agg["convergence_generation"]["mean"],
            agg["valid_trials"],
        )
    wandb.log({"benchmark_summary": table})

    # Log per-gen learning curves
    for name, cond in report["conditions"].items():
        curve = cond["summary"].get("per_generation_avg_best", [])
        for i, val in enumerate(curve):
            wandb.log({f"{name}/avg_best": val, "generation": i})

    wandb.summary["winner"] = report.get("winner", "none")
    wandb.finish()


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------
_active_processes: list[subprocess.Popen] = []
_active_workers: list[str] = []


def run_benchmark(
    preset_name: str,
    seeds: int,
    max_gen: int,
    parallel: int,
    wandb_project: str | None,
) -> dict:
    """Run all conditions × seeds, aggregate, report."""
    preset = PRESETS[preset_name]
    condition_names = list(preset.keys())

    # Build work items: (condition_name, seed, config, worker_id)
    work_items = []
    for cond_name in condition_names:
        overrides = preset[cond_name]
        config = {**BASE_CONFIG, "max_generations": max_gen, **overrides}
        for seed in range(seeds):
            worker_id = uuid.uuid4().hex[:8]
            work_items.append((cond_name, seed, config, worker_id))

    total = len(work_items)
    print(f"\nBenchmark: {preset_name}")
    print(f"  Conditions: {', '.join(condition_names)}")
    print(f"  Seeds: {seeds}, Generations: {max_gen}, Parallel workers: {parallel}")
    print(f"  Total trials: {total}")
    print()

    # Collect results keyed by condition name
    results: dict[str, list[dict | None]] = {name: [] for name in condition_names}
    completed = 0

    def execute_trial(item):
        cond_name, seed, config, worker_id = item
        _active_workers.append(worker_id)
        timeout = calculate_timeout(config)
        print(f"  [{worker_id}] Starting {cond_name} seed={seed} (timeout={timeout}m)")
        trial = run_single_trial(config, worker_id, timeout)
        if worker_id in _active_workers:
            _active_workers.remove(worker_id)
        status = f"gens={trial['total_generations']}" if trial else "FAILED"
        return cond_name, seed, trial, status

    with ThreadPoolExecutor(max_workers=parallel) as pool:
        futures = {pool.submit(execute_trial, item): item for item in work_items}
        try:
            for future in as_completed(futures):
                cond_name, seed, trial, status = future.result()
                results[cond_name].append(trial)
                completed += 1
                print(f"  [{completed}/{total}] {cond_name} seed={seed}: {status}")
        except KeyboardInterrupt:
            print("\n\nInterrupted! Cleaning up...")
            pool.shutdown(wait=False, cancel_futures=True)
            raise

    # Aggregate
    conditions = {}
    best_mean = -1
    winner = None
    for cond_name in condition_names:
        summary = aggregate_trials(results[cond_name])
        conditions[cond_name] = {
            "flags": preset[cond_name],
            "summary": summary,
            "raw_trials": results[cond_name],
        }
        if summary.get("valid_trials", 0) > 0:
            m = summary["final_best_fitness"]["mean"]
            if m > best_mean:
                best_mean = m
                winner = cond_name

    report = {
        "preset": preset_name,
        "seeds": seeds,
        "max_generations": max_gen,
        "parallel": parallel,
        "base_config": BASE_CONFIG,
        "timestamp": datetime.now().isoformat(),
        "conditions": conditions,
        "winner": winner,
    }

    print_summary_table(report)
    save_report(report)

    if wandb_project:
        log_to_wandb(report, wandb_project)

    return report


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Benchmark suite for Evolve neuroevolution algorithm comparison"
    )
    parser.add_argument(
        "--preset",
        choices=list(PRESETS.keys()),
        default="full-comparison",
        help="Which comparison to run (default: full-comparison)",
    )
    parser.add_argument(
        "--seeds", type=int, default=3, help="Seeds per condition (default: 3)"
    )
    parser.add_argument(
        "--generations", type=int, default=50, help="Max generations per trial (default: 50)"
    )
    parser.add_argument(
        "--parallel", type=int, default=1, help="Concurrent Godot instances (default: 1)"
    )
    parser.add_argument(
        "--wandb", action="store_true", help="Log results to Weights & Biases"
    )
    parser.add_argument(
        "--project",
        default="evolve-benchmarks",
        help="W&B project name (default: evolve-benchmarks)",
    )
    args = parser.parse_args()

    # Validate environment
    if not Path(GODOT_PATH).exists():
        print(f"Error: Godot not found at {GODOT_PATH}")
        print("Please update GODOT_PATH in this script or set up a symlink.")
        sys.exit(1)
    if not PROJECT_PATH.exists():
        print(f"Error: Project not found at {PROJECT_PATH}")
        sys.exit(1)

    # Handle Ctrl+C — clean up all worker files and terminate Godot processes
    original_sigint = signal.getsignal(signal.SIGINT)

    def signal_handler(sig, frame):
        print("\n\nBenchmark interrupted. Cleaning up worker files...")
        for wid in list(_active_workers):
            cleanup_files(wid)
        signal.signal(signal.SIGINT, original_sigint)
        sys.exit(1)

    signal.signal(signal.SIGINT, signal_handler)

    run_benchmark(
        preset_name=args.preset,
        seeds=args.seeds,
        max_gen=args.generations,
        parallel=args.parallel,
        wandb_project=args.project if args.wandb else None,
    )


if __name__ == "__main__":
    main()
