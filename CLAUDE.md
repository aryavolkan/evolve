# Evolve

A 2D arcade survival game built with Godot 4.5+. Player avoids enemy entities to achieve the highest score.

## Tech Stack

- **Engine**: Godot 4.5+ (Forward Plus renderer)
- **Language**: GDScript
- **Resolution**: 1280x720

## Project Structure

```
├── project.godot      # Godot project config
├── main.tscn/gd       # Main scene - game manager, UI, spawning
├── player.tscn/gd     # Player entity - movement, collision, shooting
├── enemy.tscn/gd      # Enemy entity - AI pathfinding
├── powerup.tscn/gd    # Power-up collectibles
├── projectile.tscn/gd # Player projectiles
├── obstacle.tscn      # Static obstacles
├── training_manager.gd # AI training orchestration
├── ai/                # Neural network and evolution
├── scripts/           # Python W&B integration + demo export scripts
├── models/            # Temp dir for .pck export (gitignored)
└── test/              # Test suite (run via test_runner.gd)
```

## Running the Project

```bash
godot --path . --editor   # Open in editor
godot --path . --play     # Run directly
```

## Architecture Patterns

### Signal-Based Communication
```gdscript
signal hit                           # Define signal
player.hit.connect(_on_player_hit)   # Connect in parent
hit.emit()                           # Emit when triggered
```

### Group-Based Entity Identification
- `player` group - Player node
- `enemy` group - Enemy nodes
- Check with: `collider.is_in_group("enemy")`

### Physics
- Entities use `CharacterBody2D`
- Movement via `move_and_slide()`
- Collision detection via `get_slide_collision_count()`

### Scene Instantiation
```gdscript
var enemy_scene = preload("res://enemy.tscn")
var enemy = enemy_scene.instantiate()
add_child(enemy)
```

## Code Conventions

- Use `@export` for editor-configurable properties
- Type hints on function signatures: `func _ready() -> void:`
- `_ready()` for initialization
- `_physics_process(delta)` for movement/physics
- `_process(delta)` for non-physics updates (UI, scoring)
- Use `@onready` for node references: `@onready var label = $ScoreLabel`

## Game Mechanics

- Player (blue, 40x40) moves with arrow keys at speed 300
- Player starts with 3 lives
- WASD to shoot projectiles in four directions (0.3s cooldown)
- Projectiles destroy enemies on contact
- Multiple enemy types with different behaviors
- Score +5 per second
- Enemy spawn rate increases with score
- Power-up spawns every 80 points at random position
- Collision = lose a life, respawn at center with 2s invincibility
- Game over when lives reach 0, SPACE to restart

## Arena System

- **Fixed Arena Size:** 3840x3840 pixels (square arena, zoomed out to fit)
- **Static Camera:** Centered on arena, dynamic zoom to show entire arena
- **Arena Walls:** Solid boundaries prevent player/enemies from leaving
- **Permanent Obstacles:** 40 obstacles placed randomly at game start (fixed layout per run)
- **Safe Zone:** 300px radius around center kept clear for player spawn
- **Enemy Spawning:** Enemies spawn along arena edges
- **Grid Floor:** Visual grid lines (160px) for spatial reference

## Chess Piece Enemies

Enemies are chess pieces with chess-like movement patterns. Kill points are 1000× chess values:

| Piece | Symbol | Kill Points | Size | Movement Pattern |
|-------|--------|-------------|------|------------------|
| Pawn | ♟ | 1000 | 28 | One tile toward player (straight lines) |
| Knight | ♞ | 3000 | 32 | L-shaped jumps (2+1 tiles), hops over obstacles |
| Bishop | ♝ | 3000 | 32 | Diagonal movement (1-2 tiles) |
| Rook | ♜ | 5000 | 36 | Straight lines (1-3 tiles horizontal/vertical) |
| Queen | ♛ | 9000 | 40 | Combines bishop and rook movement |

**Movement System:**
- Pieces move on a virtual 50px grid
- Each piece waits between moves (cooldown varies by type)
- Movement is animated with smooth interpolation
- Knights have a hop animation when moving

**Spawn Weights:**
- Early game: Mostly pawns
- Higher difficulty: More knights, bishops, rooks, and rare queens

## Difficulty Scaling

Difficulty increases linearly from score 0 to 500, then maxes out:

| Metric | Start | Max (500+ pts) |
|--------|-------|----------------|
| Enemy speed | 150 | 300 |
| Spawn interval | 50 pts | 20 pts |

Scaling uses linear interpolation: `lerp(base, max, score / 500)`

## Power-Up System

Ten power-up types spawn during gameplay (5 second duration each):

| Type | Color | Effect |
|------|-------|--------|
| Speed Boost | Cyan-green | Player speed 300 → 500 |
| Invincibility | Gold | Immune to enemy collision |
| Slow Enemies | Purple | All enemies move at 50% speed |
| Screen Clear | Red-orange | Destroys all enemies |
| Rapid Fire | Orange | 70% faster shooting |
| Piercing | Light blue | Projectiles pass through enemies |
| Shield | Light purple | Absorbs one hit |
| Freeze | Ice blue | Completely stops enemies |
| Double Points | Bright green | 2× score multiplier |
| Bomb | Bright red | Kills enemies within 600px radius |

Power-ups use `Area2D` with `body_entered` signal for collection detection.

## High Score System

- Top 5 scores saved to `user://highscores.save`
- Displayed on right side during gameplay
- On game over, if score qualifies:
  - Prompts for name entry (max 10 characters)
  - Press ENTER to submit
- Scores persist between sessions using `FileAccess`

## Key Node References

- `$Player` - Player CharacterBody2D
- `$CanvasLayer/UI/ScoreLabel` - Score display
- `$CanvasLayer/UI/LivesLabel` - Lives counter
- `$CanvasLayer/UI/GameOverLabel` - Game over message
- `$CanvasLayer/UI/PowerUpLabel` - Power-up notification
- `$CanvasLayer/UI/ScoreboardLabel` - High scores display
- `$CanvasLayer/UI/NameEntry` - Name input field
- `$CanvasLayer/UI/NamePrompt` - Name entry prompt

## Neuroevolution AI System

Neural network agents that learn to play the game through evolutionary algorithms.

### Architecture

```
ai/
├── neural_network.gd   # Feedforward network with evolvable weights
├── sensor.gd           # Raycast-based perception (16 rays × 5 values)
├── ai_controller.gd    # Converts network outputs to game actions
├── evolution.gd        # Population management and selection
└── trainer.gd          # Training loop orchestration
training_manager.gd     # Main scene integration
```

### Network Architecture

- **Inputs (86 total):**
  - 16 rays × 5 values each = 80 ray inputs
    - Enemy distance (normalized 0-1, closer = higher)
    - Enemy type (pawn=0.2 to queen=1.0)
    - Obstacle distance
    - Power-up distance
    - Wall distance (arena boundary)
  - 6 player state inputs (velocity, power-up flags, can_shoot)

- **Hidden Layer:** 80 neurons with tanh activation
- **Outputs (6):** move_x, move_y, shoot_up, shoot_down, shoot_left, shoot_right

### Controls

| Key | Action |
|-----|--------|
| T | Start/Stop training |
| P | Start/Stop playback (watch best AI) |
| H | Return to human control |
| [ or - | Slow down training (min 0.25x) |
| ] or + | Speed up training (max 16x) |
| Y | Toggle phylogenetic lineage tree |
| 8 | Team Battle (from title screen) |

### Fitness Function

Kills and powerups dominate scoring (survival is secondary):
- +5 points per second survived
- +100 points survival milestone every 15 seconds (increasing)
- +1000× enemy chess value per kill (pawn=1000, queen=9000)
- +5000 points per power-up collected
- +8000 bonus for screen clear
- +50 points for shooting toward enemies (training shaping)
- Proximity bonus for being near powerups (continuous reward)

### Evolution Parameters

| Parameter | Value |
|-----------|-------|
| Population size | 150 |
| Parallel arenas | 20 (5x4 grid) |
| Evals per individual | 2 (multi-seed for robustness) |
| Elite count | 20 (preserve good solutions) |
| Selection | Tournament (best of 3 random) |
| Crossover | Two-point (73% rate) |
| Mutation rate | 30% per weight |
| Mutation strength | σ = 0.09 (adaptive: increases when stagnating) |
| Hidden layer size | 80 neurons |
| Max eval time | 60 seconds per individual |
| Early stopping | 10 generations without improvement |

### Training Mode Adjustments

Training mode makes the game easier to accelerate learning:
- Enemies spawn closer and slower (50% speed)
- Only 3 initial enemies (vs 10 in normal play)
- Powerups spawn within 300-1000 units of player
- Powerups every 3 seconds (vs every 80 points in normal play)
- Projectiles faster (900) and longer range (1200)

### Saved Files

- `user://best_network.nn` - Best performing network
- `user://population.evo` - Full population state
- `user://metrics.json` - Training metrics for W&B integration
- `user://sweep_config.json` - Hyperparameters from W&B sweep

### W&B Integration

Python scripts in `scripts/` provide Weights & Biases integration:

**Real-time logging during training:**
```bash
source .venv/bin/activate
python scripts/wandb_bridge.py --project evolve-neuroevolution
# Then press T in Godot to start training
```

**Overnight hyperparameter sweep:**
```bash
python scripts/overnight_sweep.py --hours 8 --project evolve-neuroevolution
```

The sweep searches over:
- Population size: 50, 100, 150
- Hidden neurons: 24, 32, 48, 64
- Elite count: 5-20
- Mutation rate: 0.10-0.35
- Crossover rate: 0.5-0.85

**Headless training:**
```bash
godot --path . --headless -- --auto-train
```

## Research Roadmap

### Completed

All phases through co-evolution and sandbox are implemented. See `ROADMAP.md` for full history.

- **Curriculum Learning** — 5-stage automated difficulty (`ai/curriculum_manager.gd`)
- **NSGA-II** — Multi-objective Pareto optimization in `evolution.gd`
- **MAP-Elites** — 20×20 behavioral archive (`ai/map_elites.gd`, `ui/map_elites_heatmap.gd`)
- **Elman Recurrent Memory** — Previous hidden state fed back as input in `neural_network.gd`
- **NEAT** — Topology evolution (`ai/neat_genome.gd`, `ai/neat_evolution.gd`, `ai/neat_network.gd`)
- **Competitive Co-Evolution** — Dual populations, enemy neural networks, Hall of Fame (`ai/coevolution.gd`, `ai/enemy_sensor.gd`, `ai/enemy_ai_controller.gd`)
- **Live Sandbox** — Configurable arena (`ui/sandbox_panel.gd`), side-by-side comparison (`ui/comparison_panel.gd`), network topology viz (`ui/network_visualizer.gd`), archive playback
- **rtNEAT** — Continuous real-time evolution (`ai/rtneat_manager.gd`, `ai/rtneat_population.gd`, `ui/rtneat_overlay.gd`, `agent.gd`)
- **Live Player Interactions** — 6 interaction tools during rtNEAT mode (keys 0-5): inspect, place/remove obstacles, spawn enemy waves, bless/curse agents
- **Educational Mode** — Annotated AI decision narration (`ui/educational_overlay.gd`), auto-shows sensor rays + network viz, highlights most significant ray, E key toggle
- **Phylogenetic Tree** — Lineage tracking across all 3 evolution pipelines (`ai/lineage_tracker.gd`), champion ancestry DAG visualization (`ui/phylogenetic_tree.gd`), Y key toggle
- **Multi-Agent Team Battle** — Two AI teams evolve via rtNEAT and fight with projectiles (`ai/team_manager.gd`), extended 119-input sensors with teammate/opponent detection, PvP projectile damage, team fitness bonus, team-colored agents, key 8 from title screen

## Testing

Run tests with:
```bash
godot --headless --script test/test_runner.gd
```

### Test Coverage

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `test_neural_network.gd` | 16 | Network init, forward pass, cloning, mutation, crossover, save/load |
| `test_evolution.gd` | 17 | Population, fitness, elitism, selection, backup/restore, persistence |
| `test_difficulty.gd` | 11 | Difficulty factor, enemy speed, spawn interval scaling |
| `test_highscore.gd` | 9 | Score qualification, sorting, capping, persistence |
| `test_enemy.gd` | 18 | Chess piece points, movement patterns, slow/freeze effects |
| `test_sensor.gd` | 15 | Ray casting, wall distance, entity detection, type encoding |
| `test_ai_controller.gd` | 10 | Movement mapping, shoot direction, deadzone handling |
| `test_edge_cases.gd` | 10 | Zero weights, extreme values, minimal populations |
| `test_powerup.gd` | 12 | Type names, type count |
| `test_trainer.gd` | 9 | Path constants, config defaults, stats/action structure |
| `test_integration.gd` | 10 | Full Sensor → Network → Controller pipeline, data flow |
| `test_rtneat.gd` | 26 | Population, agents, targeting, interaction tools (bless/curse/log) |
| `test_educational.gd` | 9 | Educational overlay analysis: threats, shooting, state, narration |
| `test_lineage.gd` | 10 | Lineage tracker: birth recording, ancestry tracing, pruning, fitness |
| `test_teams.gd` | 15 | Team battle: TeamManager, PvP hits, team sensors, team colors, signals |
| `test_death_effects.gd` | 8 | Death effect: instantiation, setup, enemy die(), player/agent effects |
| `test_demo_export.gd` | 4 | Demo export: model fallback path, --demo flag, basename extraction |

### Visible Training Mode

Press **T** to enter training mode. The screen displays 20 parallel arenas in a 5x4 grid, each evaluating a different neural network simultaneously.

**Each arena shows:**
- Individual number (#0-19)
- Current score and lives

**Stats bar (top) shows:**
- Generation number and batch progress
- Best score in current batch
- All-time best score
- Stagnation counter (generations without improvement)
- Current speed multiplier

**Features:**
- Speed adjustable 0.25x-16x with `[-/+]` keys
- Early stopping after 10 generations without improvement
- Auto-saves best network every generation
- Press **T** again or **H** to stop and return to human mode

## Demo Export

Export a trained AI model as a standalone `.pck` file anyone with a Godot runtime can play.

**Export:**
```bash
python scripts/export_demo.py                          # Default output: evolve_demo.pck
python scripts/export_demo.py --output my_demo.pck     # Custom output name
python scripts/export_demo.py --network /path/to/nn    # Custom network file
```

**Play:**
```bash
godot --main-pack evolve_demo.pck -- --demo
```

**How it works:**
- The script copies `best_network.nn` into `res://models/` temporarily
- Runs `godot --export-pack` to create the `.pck` with the model embedded
- Cleans up `models/` after export (not committed to repo)
- The `--demo` flag skips the title screen and starts AI playback directly
- `neural_network.gd` has a `res://models/` fallback when `user://` path is missing
