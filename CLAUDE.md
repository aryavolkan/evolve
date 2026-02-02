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
└── icon.svg           # Project icon
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
- Camera follows player (infinite world)
- Gray obstacles procedurally generated around player
- Multiple enemy types with different behaviors
- Score +10 per second
- Enemy spawn rate increases with score
- Power-up spawns every 40 points at random position
- Collision = lose a life, respawn at center with 2s invincibility
- Game over when lives reach 0, SPACE to restart

## Chess Piece Enemies

Enemies are chess pieces with chess-like movement patterns. Kill points are 10× chess values:

| Piece | Symbol | Kill Points | Size | Movement Pattern |
|-------|--------|-------------|------|------------------|
| Pawn | ♟ | 10 | 28 | One tile toward player (straight lines) |
| Knight | ♞ | 30 | 32 | L-shaped jumps (2+1 tiles), hops over obstacles |
| Bishop | ♝ | 30 | 32 | Diagonal movement (1-2 tiles) |
| Rook | ♜ | 50 | 36 | Straight lines (1-3 tiles horizontal/vertical) |
| Queen | ♛ | 90 | 40 | Combines bishop and rook movement |

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

Four power-up types spawn during gameplay (5 second duration each):

| Type | Color | Effect |
|------|-------|--------|
| Speed Boost | Cyan-green | Player speed 300 → 500 |
| Invincibility | Gold | Immune to enemy collision |
| Slow Enemies | Purple | All enemies move at 50% speed |
| Screen Clear | Red-orange | Destroys all enemies (+25 bonus points) |

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
├── sensor.gd           # Raycast-based perception (16 rays × 4 values)
├── ai_controller.gd    # Converts network outputs to game actions
├── evolution.gd        # Population management and selection
└── trainer.gd          # Training loop orchestration
training_manager.gd     # Main scene integration
```

### Network Architecture

- **Inputs (70 total):**
  - 16 rays × 4 values each = 64 ray inputs
    - Enemy distance (normalized 0-1, closer = higher)
    - Enemy type (pawn=0.2 to queen=1.0)
    - Obstacle distance
    - Power-up distance
  - 6 player state inputs (velocity, power-up flags, can_shoot)

- **Hidden Layer:** 32 neurons with tanh activation
- **Outputs (6):** move_x, move_y, shoot_up, shoot_down, shoot_left, shoot_right

### Controls

| Key | Action |
|-----|--------|
| T | Start/Stop training |
| P | Start/Stop playback (watch best AI) |
| H | Return to human control |

### Fitness Function

Uses game score directly:
- +10 points per second survived
- +N×10 points per enemy killed (pawn=10, knight/bishop=30, rook=50, queen=90)
- +50 points per power-up collected
- +100 bonus for screen clear (plus scaled enemy values)

### Evolution Parameters

| Parameter | Value |
|-----------|-------|
| Population size | 50 |
| Elite count | 5 (top performers kept unchanged) |
| Selection | Tournament (best of 3 random) |
| Crossover rate | 70% |
| Mutation rate | 15% per weight |
| Mutation strength | σ = 0.3 |
| Max eval time | 60 seconds per individual |

### Saved Files

- `user://best_network.nn` - Best performing network
- `user://population.evo` - Full population state for resuming

### Headless Training

Run training without GUI for faster evolution:

```bash
./train.sh                           # Default: 50 pop, 100 gen, 10 parallel
./train.sh -p 100 -g 200 -j 20       # Larger population, more parallel
./train.sh -t 30                     # Shorter evaluation time (30s)
```

Options:
- `-p, --population N` - Population size (default: 50)
- `-g, --generations N` - Max generations (default: 100)
- `-j, --parallel N` - Parallel evaluations (default: 10)
- `-t, --eval-time N` - Max eval time per individual in seconds (default: 60)

Progress auto-saves every generation. Press Ctrl+C to stop safely.
