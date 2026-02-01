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
```

## Running the Project

```bash
godot --path /Users/aryasen/Projects/evolve        # Open in editor
godot --path /Users/aryasen/Projects/evolve --play # Run directly
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

## Code Conventions

- Use `@export` for editor-configurable properties
- Type hints on function signatures: `func _ready() -> void:`
- `_ready()` for initialization
- `_physics_process(delta)` for movement/physics
- `_process(delta)` for non-physics updates (UI, scoring)

## Game Mechanics

- Player (blue, 40x40) moves with arrow keys at speed 300
- Enemies (red, 30x30) chase player at speed 150
- Score +10 per second
- New enemy spawns every 50 points at random screen edge
- Collision = game over, SPACE to restart
