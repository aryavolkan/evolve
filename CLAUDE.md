# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Evolve is a 2D arcade survival game with an integrated neuroevolution AI system. Players dodge chess-piece enemies, collect power-ups, and compete for high scores. Neural network agents learn to play through multiple evolutionary algorithms (standard GA, NEAT, NSGA-II, MAP-Elites, co-evolution, rtNEAT).

## Tech Stack

- **Engine**: Godot 4.5+ (Forward Plus renderer)
- **Languages**: GDScript (primary), Rust (GPU-accelerated NN via gdext), Python (W&B integration)
- **Resolution**: 1280x720 viewport, 3840x3840 arena
- **Physics**: Custom "EvolvePhysics" at 120 ticks/second

## Build, Test, Lint, Run

```bash
# Run game
godot --path . --editor          # Open in editor
godot --path . --play            # Run directly
godot --path . --headless -- --auto-train  # Headless training

# Unit tests
godot --headless --script test/test_runner.gd

# Integration tests
godot --headless --path . -s test/integration/gameplay_test_runner.gd -- --scenario=all

# Lint
./scripts/lint_gdscript.sh      # GDScript (gdtoolkit)
./scripts/lint_python.sh        # Python (ruff)
cargo fmt --check --manifest-path rust/evolve-native/Cargo.toml  # Rust

# Rust backend build
cd rust/evolve-native && cargo build --release
```

## Architecture

### Core layers

| Directory | Purpose | Dependencies |
|-----------|---------|--------------|
| Root (`main.gd`, `player.gd`, `enemy.gd`, etc.) | Game entities and subsystem managers (GameStateManager, SpawnManager, ScoreManager, PowerupManager, UIManager, DifficultyScaler, InputCoordinator) | None |
| `ai/` | Neural networks, evolution algorithms, sensors, arena pool, training config, batch processing | Root entities |
| `modes/` | 12 game modes: human, standard training, sandbox training, NEAT, co-evolution, rtNEAT, teams, playback, generation/archive playback, comparison, sandbox | ai/, root |
| `ui/` | Training dashboard, network visualizer, sensor viz, MAP-Elites heatmap, phylogenetic tree, educational overlay, Pareto chart, comparison/sandbox panels | ai/ |
| `rust/evolve-native/` | Rust gdext backend for GPU-accelerated NN batch inference (`neural_network.rs`, `neat_genome.rs`, `nsga2.rs`, `genetic_ops.rs`) | Independent |
| `scripts/` | Python W&B bridge, overnight sweep, demo export, benchmarking | Independent |
| `overnight-agent/` | Headless W&B sweep workers and monitoring | scripts/ |

### AI training data flow

1. Mode (e.g. `standard_training_mode.gd`) manages training lifecycle
2. `arena_pool.gd` maintains 20 parallel SubViewports for simultaneous evaluation
3. Each arena: `sensor.gd` (86 inputs from 16 raycasts + player state) -> `neural_network.gd` forward pass -> `ai_controller.gd` (6 outputs: move_x/y, 4 shoot dirs) -> game actions
4. Fitness collected -> evolution algorithm (selection, crossover, mutation) -> next generation
5. `stats_tracker.gd` + `metrics_writer.gd` log metrics for W&B

### Evolution algorithms

- **Standard GA** (`evolution.gd`) — Fixed-topology, tournament selection. Also supports NSGA-II multi-objective Pareto optimization.
- **NEAT** (`neat_evolution.gd`, `neat_genome.gd`, `neat_network.gd`, `neat_species.gd`) — Variable topology via mutation/complexification
- **MAP-Elites** (`map_elites.gd`) — 20x20 behavioral diversity archive
- **Co-evolution** (`coevolution.gd`) — Dual populations (player + enemy NNs)
- **rtNEAT** (`rtneat_manager.gd`, `rtneat_population.gd`) — Continuous real-time evolution
- **Curriculum** (`curriculum_manager.gd`) — 5-stage auto-advancing difficulty

### Network architecture

- **Inputs (86):** 16 raycasts x 5 values (enemy dist/type, obstacle dist, powerup dist, wall dist) + 6 player state (velocity, powerup flags, can_shoot)
- **Hidden:** 80 neurons, tanh (fixed-topology) or variable (NEAT). Optional Elman recurrent memory.
- **Outputs (6):** move_x, move_y, shoot_up, shoot_down, shoot_left, shoot_right
- **Team mode extends to 119 inputs** (adds teammate/opponent detection)

## Game Mechanics

- Player moves with arrow keys, WASD to shoot (0.3s cooldown)
- Chess-piece enemies: Pawn (1000 pts), Knight/Bishop (3000), Rook (5000), Queen (9000)
- Pieces move on a virtual 50px grid with chess-like movement patterns
- 10 power-up types (5s duration): Speed, Invincibility, Slow, Screen Clear, Rapid Fire, Piercing, Shield, Freeze, Double Points, Bomb
- Difficulty ramps linearly from score 0-500 (enemy speed 150->300, spawn interval 50->20 pts)
- 3840x3840 arena with 40 random obstacles, 300px safe spawn zone

### Fitness function

Kills and powerups dominate (survival is secondary):
- +5 pts/sec survived, +100 pts/milestone (every 15s)
- +1000x enemy chess value per kill
- +5000 per power-up, +8000 for screen clear
- +50 for shooting toward enemies (training shaping)
- Proximity bonus for being near powerups

### Evolution parameters (defaults)

Population 150, 20 parallel arenas, elite count 20, tournament selection (k=3), two-point crossover (73%), mutation rate 30% (σ=0.09 adaptive), 60s max eval time, early stopping after 10 stagnant generations.

## Controls

| Key | Action |
|-----|--------|
| T | Start/Stop training (20 parallel arenas) |
| P | Watch best AI play |
| S | Open sandbox mode |
| C | Compare strategies side-by-side |
| H | Return to human control |
| M | View MAP-Elites heatmap |
| V | Toggle sensor visualization |
| N | Show neural network topology |
| E | Toggle educational overlay (AI decision narration) |
| Y | Toggle phylogenetic lineage tree |
| [ / ] | Adjust training speed (0.25x-16x) |
| 8 | Team Battle mode (from title screen) |
| 0-5 | rtNEAT interaction tools (inspect, obstacles, waves, bless/curse) |
| Arrow Keys | Human player movement |
| WASD | Human player shooting |
| SPACE | Restart (on game over) |

## W&B Integration

```bash
# Real-time logging
python scripts/wandb_bridge.py --project evolve-neuroevolution
# Then press T in Godot

# Overnight sweep
cd overnight-agent && python overnight_evolve.py --project evolve-neuroevolution --hours 8

# Headless training
godot --path . --headless -- --auto-train
```

## Saved Files

- `user://best_network.nn` — Best performing network
- `user://population.evo` — Full population state
- `user://metrics.json` — Training metrics for W&B
- `user://sweep_config.json` — Hyperparameters from W&B sweep

## Testing

50+ test files in `test/` covering neural networks, evolution, sensors, controllers, difficulty, enemies, power-ups, rtNEAT, lineage, teams, educational overlay, and integration scenarios.

```bash
godot --headless --script test/test_runner.gd
```

GDScript tests extend `test_base.gd`, methods prefixed `test_`.

## CI

GitHub Actions (`.github/workflows/tests.yml`): GDScript lint (gdtoolkit), Python lint (ruff), Rust fmt+clippy, Godot unit tests, integration tests.

## Demo Export

```bash
python scripts/export_demo.py                    # Default: evolve_demo.pck
godot --main-pack evolve_demo.pck -- --demo      # Play exported model
```

## Research Roadmap

All phases complete. See `ROADMAP.md` for full history and `RESULTS.md` for hyperparameter sweep findings. Current best fitness: 189,512 (Bayesian-optimized).
