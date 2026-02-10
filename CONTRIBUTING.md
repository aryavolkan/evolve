# Contributing to Evolve

Thank you for your interest in contributing! This guide covers the development workflow, testing, and how to extend the project.

---

## Getting Started

### Prerequisites

- **Godot 4.5+** — [Download](https://godotengine.org/download)
- **Python 3.10+** — For W&B integration scripts
- **Git** — Version control

### Setup

```bash
git clone https://github.com/aryavolkan/evolve.git
cd evolve

# Open in Godot editor
godot --path . --editor

# Or play directly
godot --path . --play
```

### Running Tests

```bash
godot --headless --script test/test_runner.gd
```

All 137 tests must pass before submitting a PR. The test suite covers neural networks, evolution, sensors, AI controllers, curriculum learning, NEAT, MAP-Elites, and integration tests.

---

## Code Style

### GDScript Conventions

- **Type hints** on all function signatures: `func foo(x: int) -> void:`
- **`@export`** for editor-configurable properties
- **`@onready`** for node references: `@onready var label = $ScoreLabel`
- **`_ready()`** for initialization, **`_physics_process(delta)`** for movement
- **Signal-based communication** between components
- **Group-based entity identification** (`player`, `enemy`, etc.)

### Naming

- snake_case for variables and functions
- PascalCase for classes and scenes
- UPPER_CASE for constants
- Prefix private methods with `_`

### File Organization

```
ai/                 # Neural networks, evolution, sensors
test/               # Test suites (one per module)
scripts/            # Python W&B integration
overnight-agent/    # Headless sweep runner
ui/                 # UI components
docs/               # Extended documentation
```

---

## Testing

### Test Framework

Tests use a lightweight custom framework in `test/test_base.gd`:

```gdscript
extends "res://test/test_base.gd"

func _run_tests() -> void:
    _test("descriptive_test_name", _test_my_feature)

func _test_my_feature() -> void:
    assert_true(condition, "message if false")
    assert_eq(actual, expected, "optional message")
    assert_approx(float_val, expected, 0.001)
```

### Available Assertions

| Assertion | Description |
|-----------|-------------|
| `assert_true(cond, msg)` | Condition is true |
| `assert_false(cond, msg)` | Condition is false |
| `assert_eq(actual, expected)` | Equality check |
| `assert_ne(actual, not_expected)` | Inequality check |
| `assert_gt(a, b)` | a > b |
| `assert_gte(a, b)` | a ≥ b |
| `assert_lt(a, b)` | a < b |
| `assert_lte(a, b)` | a ≤ b |
| `assert_approx(a, b, eps)` | \|a - b\| ≤ epsilon |
| `assert_in_range(v, min, max)` | min ≤ v ≤ max |
| `assert_not_null(v)` | v is not null |
| `assert_array_eq(a, b)` | Arrays match element-wise |

### Adding a Test Suite

1. Create `test/test_my_feature.gd` extending `test_base.gd`
2. Add `preload("res://test/test_my_feature.gd")` to `test/test_runner.gd` in the `test_suites` array
3. Run and verify: `godot --headless --script test/test_runner.gd`

---

## Adding a New Evolution Algorithm

The evolution system is modular. To add a new algorithm:

### 1. Create the Algorithm File

Create `ai/my_algorithm.gd`:

```gdscript
extends RefCounted
## Brief description of the algorithm.

signal generation_complete(gen: int, best: float, avg: float, min_fit: float)

func _init(population_size: int, input_size: int, output_size: int) -> void:
    # Initialize population
    pass

func get_individual(index: int):
    # Return the neural network for individual at index
    pass

func get_network(index: int):
    # For NEAT-style: return executable network from genome
    pass

func set_fitness(index: int, fitness: float) -> void:
    # Set fitness score for individual
    pass

func evolve() -> void:
    # Run selection, crossover, mutation → emit generation_complete
    pass

func get_generation() -> int:
    pass

func get_stats() -> Dictionary:
    return {"current_max": 0.0, "current_avg": 0.0, "current_min": 0.0, "all_time_best": 0.0}

func get_all_time_best_fitness() -> float:
    pass

func save_best(path: String) -> void:
    pass

func save_population(path: String) -> void:
    pass
```

### 2. Wire It Into training_manager.gd

Add a flag and initialization branch in `start_training()`:

```gdscript
var use_my_algorithm: bool = false

# In start_training():
if use_my_algorithm:
    evolution = MyAlgorithmScript.new(population_size, input_size, 6)
```

### 3. Add Tests

Create `test/test_my_algorithm.gd` with at minimum:
- Population initialization
- Fitness assignment
- Evolution step
- Stats reporting
- Save/load roundtrip

### 4. Add to Sweep Config (Optional)

In `overnight-agent/overnight_evolve.py`, add your algorithm's parameters to `sweep_config['parameters']`.

---

## Running W&B Sweeps

### Setup

```bash
cd overnight-agent
python -m venv .venv
source .venv/bin/activate  # or .venv\Scripts\activate on Windows
pip install wandb

wandb login  # One-time authentication
```

### Environment Configuration

Set these environment variables to configure paths for your system:

```bash
# Godot executable path (defaults vary by OS)
export GODOT_PATH="/path/to/godot"

# Godot user data directory
export GODOT_USER_DIR="$HOME/Library/Application Support/Godot/app_userdata/evolve"
```

See the default paths in `overnight-agent/overnight_evolve.py` for OS-specific examples.

### Running a Sweep

```bash
# Create new sweep (runs for 8 hours by default)
python overnight_evolve.py --project evolve-neuroevolution --hours 8

# Join existing sweep
python overnight_evolve.py --project evolve-neuroevolution --sweep-id <id>

# Run with visible Godot window (for debugging)
python overnight_evolve.py --project evolve-neuroevolution --visible

# Limit number of runs
python overnight_evolve.py --project evolve-neuroevolution --count 5
```

### Real-Time Bridge (Interactive Training)

```bash
# Watch a manual training session in W&B
python scripts/wandb_bridge.py --project evolve-neuroevolution
# Then press T in Godot to start training
```

---

## PR Process

### Branch Naming

- `feature/<description>` — New features
- `fix/<description>` — Bug fixes
- `refactor/<description>` — Code restructuring
- `docs/<description>` — Documentation only

### PR Checklist

- [ ] All tests pass: `godot --headless --script test/test_runner.gd`
- [ ] New code has tests (for non-trivial logic)
- [ ] No unrelated changes (be surgical)
- [ ] Commit messages follow conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`)
- [ ] Updated relevant documentation if behavior changed

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add enemy neural network sensor
fix: prevent crash when population is empty
refactor: extract CurriculumManager from training_manager
docs: update README with architecture diagram
test: add MAP-Elites archive tests
```

---

## Project Architecture

See the [Architecture section in README.md](README.md#architecture) for a Mermaid diagram of the full data flow.

Key files:
- **`training_manager.gd`** — Training orchestration (parallel arenas, evaluation loop)
- **`ai/evolution.gd`** — Population management, selection, crossover, mutation
- **`ai/neural_network.gd`** — Fixed-topology feedforward network
- **`ai/neat_evolution.gd`** — NEAT topology evolution
- **`ai/sensor.gd`** — 16-ray perception system (86 inputs)
- **`ai/ai_controller.gd`** — Converts network outputs to game actions
- **`ai/curriculum_manager.gd`** — Progressive difficulty staging
- **`ai/stats_tracker.gd`** — Fitness accumulation and metric history

---

## Questions?

Open an issue on GitHub or check existing documentation:
- [ROADMAP.md](ROADMAP.md) — Development roadmap
- [RESULTS.md](RESULTS.md) — Training findings
- [LONG_TERM_PLAN.md](LONG_TERM_PLAN.md) — Track A/B feature plans
