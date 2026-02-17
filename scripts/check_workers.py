#!/usr/bin/env python3
"""Check status of W&B sweep worker processes and Godot training instances."""

import json
import re
import subprocess
import time
from pathlib import Path

GODOT_DATA = Path.home() / '.local/share/godot/app_userdata/Evolve'

# ── 1. Python worker processes ──
print('=== Python Workers ===')
ps = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
py_workers = []
for l in ps.stdout.splitlines():
    if ('overnight_evolve.py' in l or 'overnight_sweep.py' in l) and 'grep' not in l:
        parts = l.split()
        cmd = ' '.join(parts[10:])
        if cmd.startswith('python') or cmd.startswith('/usr/bin/python') or cmd.startswith('/home/'):
            if 'python' in cmd.split()[0]:
                py_workers.append(l)
if py_workers:
    for w in py_workers:
        parts = w.split()
        pid, cpu, mem, start_time = parts[1], parts[2], parts[3], parts[8]
        cmd = ' '.join(parts[10:])
        short_cmd = re.sub(r'.*/scripts/', 'scripts/', cmd)
        short_cmd = re.sub(r'.*/overnight_', 'overnight_', short_cmd)
        print(f'  PID {pid:>6} | CPU {cpu:>5}% | MEM {mem:>5}% | Start {start_time} | {short_cmd}')
else:
    print('  No Python workers running')

# ── 2. Godot headless processes ──
print()
print('=== Godot Instances ===')
godot_procs = [l for l in ps.stdout.splitlines() if 'godot' in l.lower() and '--headless' in l and 'grep' not in l and '/bin/bash' not in l]
if godot_procs:
    for g in godot_procs:
        parts = g.split()
        pid, cpu, mem, start_time = parts[1], parts[2], parts[3], parts[8]
        wid = 'none'
        for p in parts:
            if '--worker-id=' in p:
                wid = p.split('=')[1]
        print(f'  PID {pid:>6} | CPU {cpu:>5}% | MEM {mem:>5}% | Start {start_time} | Worker ID: {wid}')
else:
    print('  No Godot headless instances running')

# ── 3. Metrics files ──
print()
print('=== Training Progress (metrics files) ===')
metrics_files = sorted(GODOT_DATA.glob('metrics*.json'), key=lambda f: f.stat().st_mtime, reverse=True) if GODOT_DATA.exists() else []
if metrics_files:
    for mf in metrics_files:
        age_s = time.time() - mf.stat().st_mtime
        age_str = f'{int(age_s)}s ago' if age_s < 60 else f'{int(age_s/60)}m ago' if age_s < 3600 else f'{int(age_s/3600)}h ago'
        try:
            data = json.loads(mf.read_text())
            gen = data.get('generation', '?')
            best = data.get('best_fitness', '?')
            avg = data.get('avg_fitness', '?')
            atb = data.get('all_time_best', '?')
            stag = data.get('generations_without_improvement', '?')
            curriculum_on = data.get('curriculum_enabled', True)
            stage = data.get('curriculum_stage', '?') if curriculum_on else 'off'
            complete = data.get('training_complete', False)
            status = 'COMPLETE' if complete else 'TRAINING'
            best_str = f'{best:,.0f}' if isinstance(best, (int, float)) else best
            avg_str = f'{avg:,.0f}' if isinstance(avg, (int, float)) else avg
            atb_str = f'{atb:,.0f}' if isinstance(atb, (int, float)) else atb
            print(f'  {mf.name} (updated {age_str}) [{status}]')
            print(f'    Gen {gen} | Best: {best_str} | Avg: {avg_str} | All-time: {atb_str} | Stagnation: {stag} | Stage: {stage}')
        except Exception as e:
            print(f'  {mf.name} (updated {age_str}) - parse error: {e}')
else:
    print('  No metrics files found')

# ── 4. Worker log files ──
print()
print('=== Worker Logs (latest 5) ===')
log_files = []
for pattern in [Path('overnight-agent') / 'worker*.log', Path('/tmp') / 'sweep_worker_*.log', Path('.') / 'worker*.log']:
    log_files.extend(pattern.parent.glob(pattern.name))
log_files = sorted(log_files, key=lambda f: f.stat().st_mtime, reverse=True)
if log_files:
    for lf in log_files[:5]:
        age_s = time.time() - lf.stat().st_mtime
        age_str = f'{int(age_s)}s ago' if age_s < 60 else f'{int(age_s/60)}m ago' if age_s < 3600 else f'{int(age_s/3600)}h ago'
        size_kb = lf.stat().st_size / 1024
        lines = lf.read_text().strip().splitlines()
        last_lines = [l for l in lines[-20:] if l.strip() and not any(x in l for x in ['wandb: Find logs', 'wandb: Synced', 'wandb: \u2b50'])][-3:]
        print(f'  {lf} ({size_kb:.0f}KB, updated {age_str})')
        for ll in last_lines:
            print(f'    | {ll[:120]}')
else:
    print('  No worker log files found')

# ── 5. Summary ──
active_metrics = [f for f in metrics_files if time.time() - f.stat().st_mtime < 300]
stale_metrics = [f for f in metrics_files if time.time() - f.stat().st_mtime >= 300]
print()
print('=== Summary ===')
print(f'  Python workers:       {len(py_workers)}')
print(f'  Godot instances:      {len(godot_procs)}')
print(f'  Active metrics files: {len(active_metrics)}')
if stale_metrics:
    print(f'  Stale metrics files:  {len(stale_metrics)} (>5min old)')
if log_files:
    print(f'  Log files found:      {len(log_files)}')

# ── 6. Warnings ──
warnings = []
if py_workers and not godot_procs:
    warnings.append('Python workers running but no Godot instances — workers may be idle or between runs')
if godot_procs and not py_workers:
    warnings.append('Orphaned Godot instances with no Python parent — consider killing them')
if godot_procs and not active_metrics:
    warnings.append('Godot running but no recent metrics — training may not have started yet')
if warnings:
    print()
    print('=== Warnings ===')
    for w in warnings:
        print(f'  ! {w}')
