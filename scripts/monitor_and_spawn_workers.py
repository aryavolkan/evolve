#!/usr/bin/env python3
"""
Monitor evolve project workers and auto-spawn new ones if needed.

Usage:
    python monitor_and_spawn_workers.py                          # Monitor only
    python monitor_and_spawn_workers.py --notify                 # Monitor + WhatsApp report
    python monitor_and_spawn_workers.py --auto-spawn             # Spawn if idle/none running
    python monitor_and_spawn_workers.py --fill --max-workers 5   # Fill all slots
    python monitor_and_spawn_workers.py --auto-spawn --sweep-id abc123
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "shared-evolve-utils"))

from godot_wandb import create_or_join_sweep, godot_user_dir  # noqa: E402
from worker_monitor import WorkerConfig, add_monitor_args, monitor_once  # noqa: E402

_HERE = Path(__file__).parent
EVOLVE_PROJECT = _HERE.parent
WANDB_PROJECT = "evolve-neuroevolution"
APP_NAME = "Evolve"


def _make_config() -> WorkerConfig:
    return WorkerConfig(
        godot_data_dir=godot_user_dir(APP_NAME),
        worker_script=EVOLVE_PROJECT / "scripts" / "overnight_sweep.py",
        worker_script_names=["overnight_evolve.py", "overnight_sweep.py"],
        project_dir=EVOLVE_PROJECT,
        wandb_project=WANDB_PROJECT,
        sweep_flag="--join",
        display_name="Evolve",
    )


def _make_sweep_fn(cfg: WorkerConfig, sweep_id: str | None) -> callable:
    """Return a factory that creates a sweep if sweep_id is None."""
    if sweep_id:
        return lambda: sweep_id

    def _create():
        from overnight_sweep import SWEEP_CONFIG  # type: ignore[import]
        return create_or_join_sweep(SWEEP_CONFIG, cfg.wandb_project)

    return _create


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Monitor and auto-spawn evolve project workers",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    add_monitor_args(parser)
    parser.add_argument("--project", type=str, default=WANDB_PROJECT,
                        help=f"W&B project name (default: {WANDB_PROJECT})")
    parser.add_argument("--count", type=int, default=5,
                        help="Runs per spawned worker (default: 5)")
    args = parser.parse_args()

    cfg = _make_config()
    cfg.wandb_project = args.project

    monitor_once(
        cfg,
        auto_spawn=args.auto_spawn,
        fill=args.fill,
        max_workers=args.max_workers,
        sweep_id=args.sweep_id,
        cpu_threshold=args.cpu_threshold,
        notify=args.notify,
        notify_host=args.notify_host,
        as_json=args.as_json,
        count_per_worker=args.count,
        create_sweep_fn=_make_sweep_fn(cfg, args.sweep_id),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
