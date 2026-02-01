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
- Enemies (red, 30x30) chase player at speed 150
- Score +10 per second
- New enemy spawns every 50 points at random screen edge
- Power-up spawns every 40 points at random position
- Collision = game over, SPACE to restart

## Power-Up System

Four power-up types spawn during gameplay (5 second duration each):

| Type | Color | Effect |
|------|-------|--------|
| Speed Boost | Cyan-green | Player speed 300 → 500 |
| Invincibility | Gold | Immune to enemy collision |
| Slow Enemies | Purple | All enemies move at 50% speed |
| Screen Clear | Red-orange | Destroys all enemies (+25 bonus points) |

Power-ups use `Area2D` with `body_entered` signal for collection detection.

## Key Node References

- `$Player` - Player CharacterBody2D
- `$CanvasLayer/UI/ScoreLabel` - Score display
- `$CanvasLayer/UI/GameOverLabel` - Game over message
- `$CanvasLayer/UI/PowerUpLabel` - Power-up notification
