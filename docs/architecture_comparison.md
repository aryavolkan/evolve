# Architecture Comparison: Evolve vs Chess-Evolve

A side-by-side comparison of two neuroevolution game projects.

---

## Project Overview

| Aspect | **Evolve** | **Chess-Evolve** |
|--------|-----------|-----------------|
| **Genre** | Bullet-hell / Top-down shooter | Chess (turn-based strategy) |
| **Game Engine** | Godot 4.6 | Godot 4.6 |
| **Language** | GDScript | GDScript |
| **Test Count** | 560 tests | 40 tests |
| **Lines of Code** | ~15,000+ | ~1,664 |
| **Project Maturity** | Mature (Jan 2024 - Feb 2026) | MVP (created Feb 2026) |
| **Training Mode** | Real-time parallel (20 arenas) | Headless batch evaluation |

---

## Neural Network Architecture

### Evolve
```
Standard Mode (Feedforward):
  16 inputs (ray sensors, wall distances, etc.)
  ↓
  32 hidden neurons (tanh activation)
  ↓
  4 outputs (move_x, move_y, shoot_up/down/left/right)

Optional: Recurrent memory layer (hidden-to-hidden weights)

NEAT Mode (Topology Evolution):
  Variable architecture
  16 inputs → [evolving topology] → 4 outputs
  Speciation, innovation tracking, structural mutation
```

**Performance:** ~440 tests/sec, 560 tests in 1.27s

### Chess-Evolve
```
Feedforward Only:
  389 inputs (board state encoding)
  ↓
  64 hidden neurons (tanh activation, configurable 32-128)
  ↓
  128 outputs (move policy over legal moves)

No recurrent memory (stateless evaluation)
No NEAT (fixed topology for now)
```

**Performance (32 hidden):** 1,569 forwards/sec  
**Performance (64 hidden):** 792 forwards/sec

---

## Evolution Algorithms

| Algorithm | **Evolve** | **Chess-Evolve** |
|-----------|-----------|-----------------|
| **Genetic Algorithm (GA)** | ✅ Default | ✅ Default |
| **NEAT** | ✅ Full implementation | ❌ Planned |
| **NSGA-II** | ✅ Multi-objective | ❌ Not planned |
| **MAP-Elites** | ✅ Quality-diversity | ❌ Not planned |
| **Co-evolution** | ✅ Player vs Enemy AI | ✅ White vs Black (core feature) |

### Evolve GA Config
- Population: 120 (optimized via W&B sweeps)
- Hidden neurons: 80
- Elite count: 20
- Mutation rate: 0.27
- Mutation strength: 0.11
- Crossover rate: 0.704

### Chess-Evolve GA Config
- Population: 100 (default, not yet tuned)
- Hidden neurons: 32 or 64 (performance vs accuracy tradeoff)
- Elite count: 20
- Mutation rate: 0.1 (default)
- Mutation strength: 0.3 (default)
- Crossover rate: 0.5 (default)

---

## Fitness Functions

### Evolve
**Primary Objective:**
- Final score (survival time + kills + powerups)

**Multi-Objective (NSGA-II mode):**
- Score
- Survival time
- Kill count
- Exploration (distance traveled)

**Quality-Diversity (MAP-Elites):**
- Behavior characterization: (avg_speed, avg_aggression)
- Archives elite individuals across behavior space

### Chess-Evolve
**White (Player) Fitness:**
- Material captured: +100 per piece value
- Checkmate bonus: +10,000
- Stalemate penalty: -5,000
- Move count penalty: -1 per move (encourages efficiency)

**Black (Enemy) Fitness:**
- Damage dealt to white (material captured)
- Survival time bonus
- Proximity bonus (threatening white king)
- Direction changes penalty (encourages focused attacks)

---

## Training Infrastructure

### Evolve

**Visual Training (GUI mode):**
- 20 parallel arenas in SubViewport grid (5×4 layout)
- Real-time evaluation with visual feedback
- Fullscreen mode for individual inspection
- Stats overlay (generation, best fitness, etc.)

**Headless Training:**
- Same parallel arena system, rendering disabled
- Metrics written to `metrics.json` every generation
- W&B integration for experiment tracking
- Overnight workers with sweep support

**Curriculum Learning:**
- 5 progressive stages (nursery → final boss)
- Arena size scaling (0.25× → 1.0×)
- Enemy type introduction (pawn → queen)
- Powerup complexity increase

**Performance:**
- ~50 FPS with 20 arenas
- ~20ms frame time per generation
- Scales well to 25-30 arenas in headless mode

### Chess-Evolve

**Headless Only (current):**
- No visual training mode yet
- Batch position evaluation (100 positions per individual)
- Metrics written to `metrics.json` every generation
- W&B sweep infrastructure ready (`sweep_config.py`, `train_wandb.py`)

**Co-evolution:**
- Separate populations for white and black
- Hall of Fame archival of top enemies
- Evaluation interval: every N generations

**Performance:**
- 30 generations × 100 individuals × 100 positions = ~3.2 min with 32 hidden
- Network is bottleneck (~1.26ms per forward with 64 hidden)
- Headless-first design (no rendering overhead)

---

## Sensor Systems

### Evolve (Player AI Sensors)

**Ray-based:**
- 8 directional rays (360° coverage)
- Distance to nearest entity (enemy/powerup/wall)
- Entity type encoding (one-hot)

**Global:**
- 4 wall distances (up/down/left/right)
- Player velocity (x, y)
- Active powerup flags (invincible, shield, rapid fire, etc.)

**Total:** 16 inputs

### Chess-Evolve (Board State Encoding)

**Piece-centric:**
- 64 squares × 6 piece types = 384 binary flags (one-hot per square)
- 1 turn indicator (white/black to move)
- 4 castling rights (KQkq)

**Total:** 389 inputs

**Key Difference:** Chess uses full board state (Markov), Evolve uses local sensors (partial observability)

---

## Testing Strategy

### Evolve (560 tests)

**Coverage:**
- Unit tests: Neural network, evolution, NEAT, MAP-Elites, NSGA-II
- Integration tests: Curriculum, co-evolution, training manager
- Regression tests: PR gatekeeper scenarios (13 scenarios)
- Performance tests: Sensor caching, parallel arenas

**Test Runtime:** 1.27 seconds (~440 tests/sec)

**CI/CD:**
- GitHub Actions on every PR
- Automated performance regression detection
- Compare reports for scenario validation

### Chess-Evolve (40 tests)

**Coverage:**
- Unit tests: Board state, move generation, neural network, evolution
- Integration tests: Training loop, W&B integration
- Chess logic: Move validation, checkmate detection, stalemate

**Test Runtime:** ~0.5 seconds (estimated)

**CI/CD:**
- Not yet configured
- Manual testing via `test/test_runner.gd`

---

## Key Architectural Differences

| Dimension | **Evolve** | **Chess-Evolve** |
|-----------|-----------|-----------------|
| **State Space** | Continuous (positions, velocities) | Discrete (board squares) |
| **Action Space** | Continuous (movement vector + shoot direction) | Discrete (128 legal move slots) |
| **Evaluation** | Real-time simulation (physics, collisions) | Position scoring (no physics) |
| **Parallelism** | In-process concurrent arenas | Batch sequential evaluation |
| **Visual Feedback** | Core feature (20-arena grid) | Not yet implemented |
| **Observability** | Partial (ray sensors) | Full (complete board state) |
| **Stochasticity** | High (enemy spawns, powerups, bullets) | None (deterministic chess rules) |

---

## Shared Design Patterns

### 1. **Neuroevolution Core**
Both use feedforward neural networks evolved via genetic algorithms with:
- Tournament selection
- Elite preservation
- Weight mutation + crossover
- Fitness-based ranking

### 2. **Training Loop**
```
Initialize population
Loop:
  Evaluate all individuals (fitness)
  Select elite
  Create offspring (mutation + crossover)
  Replace population
  Track best/avg fitness
```

### 3. **W&B Integration**
Both use:
- `metrics.json` polling for real-time logging
- Sweep infrastructure for hyperparameter search
- Generation-level metric tracking (best/avg fitness)

### 4. **GDScript Implementation**
Both leverage:
- `PackedFloat32Array` for efficient weight storage
- `RefCounted` base class for memory management
- Godot's scene system for game instances
- Headless mode for training (`--headless` flag)

---

## Lessons Learned (Cross-Project)

### From Evolve → Chess-Evolve

✅ **Adopted:**
- W&B sweep infrastructure pattern
- Metrics polling instead of stdout buffering
- Headless-first training approach
- Test-driven development (write tests before features)
- Neural network architecture (inputs → hidden → outputs)

✅ **Improved:**
- Network size benchmarking upfront (avoided 64-hidden bottleneck)
- Simpler architecture (no NEAT/MAP-Elites initially)
- Stateless evaluation (no memory layer needed for chess)

❌ **Not Yet Adopted:**
- Visual training grid (20 parallel arenas)
- Curriculum learning (progressive difficulty)
- Multiple evolution algorithms (NEAT, NSGA-II, MAP-Elites)
- Extensive test coverage (560 vs 40 tests)

### From Chess-Evolve → Evolve

⚠️ **Could Benefit:**
- Network size benchmarking (test 16, 24, 32, 48, 64 hidden neurons)
- Simpler default configs (fewer hyperparameters to tune)
- Smaller initial scope (Evolve started with full features)

---

## Future Convergence Opportunities

### 1. **Shared Neural Network Library**
Extract common code:
- `neural_network.gd` (both projects have near-identical implementations)
- `evolution.gd` (genetic algorithm core)
- Benchmark utilities

### 2. **Unified Training Infrastructure**
- Shared W&B sweep configuration patterns
- Common metrics format
- Reusable headless training script template

### 3. **Cross-Domain Experiments**
- Run Evolve's NEAT on chess (evolve topology)
- Run chess's co-evolution on Evolve (player vs enemy)
- Compare MAP-Elites vs co-evolution for diversity

### 4. **Performance Optimizations**
If chess-evolve needs faster inference:
- Apply Evolve's sensor caching pattern
- Consider GDExtension for neural network (C++ implementation)
- Batch evaluation strategies

---

## Recommendations

### For Evolve
- ✅ Well-optimized, no major changes needed
- Consider network size benchmarking (like chess-evolve did)
- Document optimal hyperparameters in README

### For Chess-Evolve
- Add visual training mode (learn from Evolve's arena pool)
- Implement curriculum learning (progressive position difficulty)
- Expand test coverage (target 100+ tests)
- Add NEAT support (topology evolution for chess)
- Create GitHub Actions CI/CD

### For Both Projects
- Extract shared neural network code to common library
- Standardize W&B metrics format
- Cross-pollinate features (visual grid ↔ co-evolution refinements)

---

**Last Updated:** 2026-02-14  
**Evolve Version:** Main branch (560 tests, 15k+ LOC)  
**Chess-Evolve Version:** Main branch (40 tests, 1,664 LOC)
