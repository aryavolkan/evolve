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
├── player.tscn/gd     # Player entity - movement, collision
├── enemy.tscn/gd      # Enemy entity - AI pathfinding
├── powerup.tscn/gd    # Power-up collectibles
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
- Multiple enemy types with different behaviors
- Score +10 per second
- Enemy spawn rate increases with score
- Power-up spawns every 40 points at random position
- Collision = lose a life, respawn at center with 2s invincibility
- Game over when lives reach 0, SPACE to restart

## Enemy Types

| Type | Color | Size | Speed | Behavior |
|------|-------|------|-------|----------|
| Chaser | Red | 30 | 1.0x | Direct pursuit |
| Speedster | Orange | 20 | 1.5x | Fast, direct pursuit |
| Tank | Dark red | 45 | 0.6x | Slow but large |
| Zigzag | Magenta | 25 | 1.1x | Erratic side-to-side movement |

Enemy variety increases with difficulty - more special types spawn at higher scores.

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
