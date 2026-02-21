# Evolve Documentation

## Quick Start

- **[README.md](../README.md)** - Quick start, features, architecture overview
- **[CLAUDE.md](../CLAUDE.md)** - AI assistant context and coding patterns

## Development

- **[CONTRIBUTING.md](../CONTRIBUTING.md)** - How to contribute
- **[KNOWN_ISSUES.md](../KNOWN_ISSUES.md)** - Current issues and limitations

## Results & Performance

- **[RESULTS.md](../RESULTS.md)** - Training results and benchmarks
- **[PERF_REPORT.md](../PERF_REPORT.md)** - Performance optimization findings

## Architecture

- **[ROADMAP.md](../ROADMAP.md)** - Future plans and priorities
- **[WANDB.md](../WANDB.md)** - Weights & Biases integration, sweep runner

## Deep Dives (docs/)

| File | Description |
|------|-------------|
| `lessons_learned.md` | Key learnings from development |
| `architecture_comparison.md` | Architecture decisions and tradeoffs |
| `performance_bottleneck_analysis.md` | Detailed performance analysis |
| `parallel_arena_analysis.md` | Parallel training analysis |
| `NSGA2_DESIGN.md` | NSGA-II implementation |
| `rust-performance-investigation.md` | Rust backend performance |

## Training Guide

### Running Sweeps

```bash
# On worker machine
cd ~/projects/evolve
source .venv/bin/activate
python scripts/overnight_sweep.py --hours 168 --project evolve-neuroevolution --join <sweep_id>
```

### Configuration Options

Key sweep parameters:
- `population_size`: 100-200
- `max_generations`: 50-100
- `parallel_count`: 10 (threads per worker)
- `time_scale`: 16 (game speed)
- `use_neat`: true/false
- `use_elite_reservoir`: true (inject elites from previous runs)
- `elite_injection_count`: 5

### Monitoring

- W&B dashboard: https://wandb.ai/aryavolkan-personal/evolve-neuroevolution
- Local metrics: `~/.local/share/godot/app_userdata/Evolve/metrics_*.json`
- Worker logs: `~/evolve/logs/worker_*.log`

## Project Structure

```
evolve/
├── main.tscn/gd          # Game manager, UI, spawning
├── player.tscn/gd        # Player entity
├── enemy.tscn/gd        # Chess-piece enemies
├── powerup.tscn/gd      # Power-ups
├── training_manager.gd   # Training orchestration
├── elite_reservoir.gd   # Global elite population storage
├── ai/
│   ├── training_config.gd    # Configuration
│   ├── evolution.gd          # Standard evolution
│   └── neat/                # NEAT implementation
├── evolve-core/          # Core algorithms
├── modes/               # Game modes (training, playback, etc.)
├── scripts/             # Python automation
└── overnight-agent/    # Sweep runner
```
