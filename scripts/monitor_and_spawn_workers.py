#!/usr/bin/env python3
"""
Monitor evolve project workers and auto-spawn new ones if needed.

This script:
- Checks CPU utilization of running workers
- Displays a table of worker status
- Spawns new workers if utilization is low
- Can be run manually or scheduled via cron/systemd timer

Usage:
    python monitor_and_spawn_workers.py                          # Monitor only
    python monitor_and_spawn_workers.py --auto-spawn             # Spawn workers, auto-create shared sweep
    python monitor_and_spawn_workers.py --auto-spawn --max-workers 5
    python monitor_and_spawn_workers.py --auto-spawn --sweep-id abc123  # Join existing sweep
"""

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / 'shared-evolve-utils'))

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

GODOT_DATA = Path.home() / '.local/share/godot/app_userdata/Evolve'
EVOLVE_PROJECT = Path(__file__).parent.parent
WORKER_SCRIPT = EVOLVE_PROJECT / 'scripts' / 'overnight_sweep.py'

# CPU threshold below which we consider spawning new workers
CPU_THRESHOLD = 50.0  # If avg CPU < 50%, workers may be idle

# Maximum number of concurrent workers
DEFAULT_MAX_WORKERS = 3

# ═══════════════════════════════════════════════════════════════════════════
# Worker Detection
# ═══════════════════════════════════════════════════════════════════════════

def get_running_workers():
    """Get list of running Python worker processes with CPU/memory stats."""
    try:
        ps = subprocess.run(['ps', 'aux'], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError:
        print("Error: Failed to run 'ps' command", file=sys.stderr)
        return []

    workers = []
    for line in ps.stdout.splitlines():
        # Look for overnight_evolve.py or overnight_sweep.py
        if ('overnight_evolve.py' in line or 'overnight_sweep.py' in line) and 'grep' not in line:
            parts = line.split()
            if len(parts) < 11:
                continue

            try:
                worker = {
                    'pid': int(parts[1]),
                    'cpu': float(parts[2]),
                    'mem': float(parts[3]),
                    'start_time': parts[8],
                    'command': ' '.join(parts[10:])
                }
                workers.append(worker)
            except (ValueError, IndexError):
                continue

    return workers


def get_godot_instances():
    """Get list of running Godot headless instances."""
    try:
        ps = subprocess.run(['ps', 'aux'], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError:
        return []

    instances = []
    for line in ps.stdout.splitlines():
        if 'godot' in line.lower() and '--headless' in line and 'grep' not in line:
            parts = line.split()
            if len(parts) < 11:
                continue

            try:
                # Extract worker ID if present
                worker_id = 'unknown'
                for part in parts:
                    if '--worker-id=' in part:
                        worker_id = part.split('=')[1]
                        break

                instance = {
                    'pid': int(parts[1]),
                    'cpu': float(parts[2]),
                    'mem': float(parts[3]),
                    'start_time': parts[8],
                    'worker_id': worker_id
                }
                instances.append(instance)
            except (ValueError, IndexError):
                continue

    return instances


def get_active_metrics():
    """Get recently updated metrics files (updated in last 5 minutes)."""
    if not GODOT_DATA.exists():
        return []

    cutoff_time = time.time() - 300  # 5 minutes
    metrics_files = []

    for mf in GODOT_DATA.glob('metrics*.json'):
        mtime = mf.stat().st_mtime
        if mtime > cutoff_time:
            try:
                data = json.loads(mf.read_text())
                metrics_files.append({
                    'file': mf.name,
                    'age_seconds': int(time.time() - mtime),
                    'generation': data.get('generation', '?'),
                    'best_fitness': data.get('best_fitness', '?'),
                    'avg_fitness': data.get('avg_fitness', '?'),
                    'training_complete': data.get('training_complete', False)
                })
            except Exception:
                pass

    return metrics_files


# ═══════════════════════════════════════════════════════════════════════════
# Display Functions
# ═══════════════════════════════════════════════════════════════════════════

def print_table_header():
    """Print table header for worker status."""
    print("\n" + "=" * 100)
    print(f"{'WORKER STATUS':^100}")
    print("=" * 100)
    print(f"{'PID':<8} {'CPU %':<8} {'MEM %':<8} {'START':<10} {'TYPE':<15} {'COMMAND/INFO':<47}")
    print("-" * 100)


def print_worker_row(worker):
    """Print a row for a Python worker."""
    cmd = worker['command']
    # Shorten command for display
    if 'overnight_evolve.py' in cmd:
        cmd_short = 'overnight_evolve.py'
    elif 'overnight_sweep.py' in cmd:
        cmd_short = 'overnight_sweep.py'
    else:
        cmd_short = cmd[:47]

    print(f"{worker['pid']:<8} {worker['cpu']:<8.1f} {worker['mem']:<8.1f} "
          f"{worker['start_time']:<10} {'Python Worker':<15} {cmd_short:<47}")


def print_godot_row(instance):
    """Print a row for a Godot instance."""
    info = f"Worker ID: {instance['worker_id']}"
    print(f"{instance['pid']:<8} {instance['cpu']:<8.1f} {instance['mem']:<8.1f} "
          f"{instance['start_time']:<10} {'Godot Instance':<15} {info:<47}")


def print_metrics_summary(metrics):
    """Print summary of active training metrics."""
    if not metrics:
        return

    print("\n" + "=" * 100)
    print(f"{'ACTIVE TRAINING SESSIONS':^100}")
    print("=" * 100)

    for m in metrics:
        status = "COMPLETE" if m['training_complete'] else "TRAINING"
        age_str = f"{m['age_seconds']}s ago"
        print(f"  {m['file']:<25} [{status:<10}] Updated: {age_str:<12} "
              f"Gen: {m['generation']:<5} Best: {m['best_fitness']:<10} Avg: {m['avg_fitness']:<10}")


def print_summary(workers, godot_instances, metrics):
    """Print overall summary and recommendations."""
    print("\n" + "=" * 100)
    print(f"{'SUMMARY':^100}")
    print("=" * 100)

    avg_cpu = sum(w['cpu'] for w in workers) / len(workers) if workers else 0
    total_godot_cpu = sum(g['cpu'] for g in godot_instances)

    print(f"  Python Workers:       {len(workers)}")
    print(f"  Godot Instances:      {len(godot_instances)}")
    print(f"  Active Training:      {len([m for m in metrics if not m['training_complete']])}")
    print(f"  Completed Training:   {len([m for m in metrics if m['training_complete']])}")

    if workers:
        print(f"  Avg Worker CPU:       {avg_cpu:.1f}%")
    if godot_instances:
        print(f"  Total Godot CPU:      {total_godot_cpu:.1f}%")

    return avg_cpu


# ═══════════════════════════════════════════════════════════════════════════
# Worker Management
# ═══════════════════════════════════════════════════════════════════════════

def spawn_new_worker(project='evolve-neuroevolution', sweep_id=None, count=5):
    """Spawn a new sweep worker in the background."""
    if not WORKER_SCRIPT.exists():
        print(f"Error: Worker script not found at {WORKER_SCRIPT}", file=sys.stderr)
        return False

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    log_file = EVOLVE_PROJECT / 'overnight-agent' / f'worker_{timestamp}.log'
    log_file.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        'nohup',
        sys.executable,
        str(WORKER_SCRIPT),
        '--project', project,
        '--count', str(count),
    ]

    if sweep_id:
        cmd.extend(['--join', sweep_id])

    try:
        with open(log_file, 'w') as f:
            proc = subprocess.Popen(
                cmd,
                stdout=f,
                stderr=subprocess.STDOUT,
                start_new_session=True,  # Detach from parent
                cwd=EVOLVE_PROJECT
            )

        print(f"\n✓ Spawned new worker (PID: {proc.pid})")
        print(f"  Log file: {log_file}")
        return True

    except Exception as e:
        print(f"Error spawning worker: {e}", file=sys.stderr)
        return False


def ensure_sweep_id(sweep_id, project):
    """Return sweep_id as-is, or create a new sweep if none provided."""
    if sweep_id:
        return sweep_id
    from godot_wandb import create_or_join_sweep
    from overnight_sweep import SWEEP_CONFIG
    return create_or_join_sweep(SWEEP_CONFIG, project)


def check_and_spawn(workers, max_workers, avg_cpu, auto_spawn=False, sweep_id=None, project='evolve-neuroevolution'):
    """Check if we should spawn new workers and do so if needed."""
    if not auto_spawn:
        return sweep_id, False

    if len(workers) >= max_workers:
        print(f"\n→ Already running {len(workers)}/{max_workers} workers. No spawn needed.")
        return sweep_id, False

    # Create/resolve sweep once before spawning
    sweep_id = ensure_sweep_id(sweep_id, project)

    if len(workers) == 0:
        print(f"\n→ No workers running. Spawning first worker...")
        return sweep_id, spawn_new_worker(project=project, sweep_id=sweep_id)

    if avg_cpu < CPU_THRESHOLD:
        available_slots = max_workers - len(workers)
        print(f"\n→ Low CPU utilization ({avg_cpu:.1f}% < {CPU_THRESHOLD}%).")
        print(f"  {available_slots} worker slot(s) available. Spawning new worker...")
        return sweep_id, spawn_new_worker(project=project, sweep_id=sweep_id)
    else:
        print(f"\n→ Workers are active (avg CPU: {avg_cpu:.1f}%). No spawn needed.")
        return sweep_id, False


# ═══════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════

def main():
    global CPU_THRESHOLD
    parser = argparse.ArgumentParser(
        description='Monitor and auto-spawn evolve project workers',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('--auto-spawn', action='store_true',
                        help='Automatically spawn new workers if needed')
    parser.add_argument('--max-workers', type=int, default=DEFAULT_MAX_WORKERS,
                        help=f'Maximum concurrent workers (default: {DEFAULT_MAX_WORKERS})')
    parser.add_argument('--sweep-id', type=str,
                        help='W&B sweep ID for all workers to share (created automatically if omitted)')
    parser.add_argument('--project', type=str, default='evolve-neuroevolution',
                        help='W&B project name (default: evolve-neuroevolution)')
    parser.add_argument('--cpu-threshold', type=float, default=CPU_THRESHOLD,
                        help=f'CPU threshold for spawning (default: {CPU_THRESHOLD}%%)')
    parser.add_argument('--json', action='store_true',
                        help='Output in JSON format (for automation)')

    args = parser.parse_args()

    # Override global threshold if specified
    CPU_THRESHOLD = args.cpu_threshold

    # Gather data
    workers = get_running_workers()
    godot_instances = get_godot_instances()
    metrics = get_active_metrics()

    if args.json:
        # JSON output for automation/parsing
        output = {
            'timestamp': datetime.now().isoformat(),
            'workers': workers,
            'godot_instances': godot_instances,
            'metrics': metrics,
            'summary': {
                'worker_count': len(workers),
                'godot_count': len(godot_instances),
                'active_training': len([m for m in metrics if not m['training_complete']]),
                'avg_cpu': sum(w['cpu'] for w in workers) / len(workers) if workers else 0
            }
        }
        print(json.dumps(output, indent=2))
    else:
        # Human-readable table output
        print(f"\nEvolve Worker Monitor - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

        print_table_header()

        for worker in workers:
            print_worker_row(worker)

        for instance in godot_instances:
            print_godot_row(instance)

        if not workers and not godot_instances:
            print(f"{'No workers or Godot instances running':<100}")

        print("-" * 100)

        print_metrics_summary(metrics)

        avg_cpu = print_summary(workers, godot_instances, metrics)

        # Check if we should spawn new workers
        sweep_id, spawned = check_and_spawn(workers, args.max_workers, avg_cpu,
                                            args.auto_spawn, args.sweep_id, args.project)

        if spawned:
            print(f"\n✓ Worker spawn complete (sweep: {sweep_id})")
            print(f"  To add more workers: --sweep-id {sweep_id}")

        print("\n" + "=" * 100 + "\n")


if __name__ == '__main__':
    main()
