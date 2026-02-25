extends RefCounted

## Raycast-free sensor for enemy AI.
## Provides 16 float inputs computed directly from game state.
##
## Unlike the player sensor (16 rays × 5 values = 86 inputs), this uses
## compact vector inputs since enemies don't need 360° vision:
##   - Player direction/distance (2)
##   - Nearest obstacle directions (4) — 2 nearest, each as dir × proximity
##   - Wall distances (4) — N, E, S, W normalized
##   - Own type encoding (1)
##   - Player velocity (2)
##   - Player power-up state flags (3)

const TOTAL_INPUTS: int = 16
const MAX_DETECT_RANGE: float = 3840.0  # Arena diagonal
const ARENA_SIZE: float = 3840.0
const WALL_MARGIN: float = 40.0
const MAX_OBSTACLE_RANGE: float = 800.0  # Only care about nearby obstacles
const MAX_SPEED: float = 500.0  # Player max speed for normalization

# Type encoding: evenly spaced in [0.2, 1.0]
const TYPE_ENCODING: Dictionary = {
    0: 0.2,  # PAWN
    1: 0.4,  # KNIGHT
    2: 0.6,  # BISHOP
    3: 0.8,  # ROOK
    4: 1.0,  # QUEEN
}

var sensor_cache = preload("res://ai/sensor.gd")

# Default arena bounds (matches Sensor.arena_bounds)
var arena_bounds: Rect2 = Rect2(
    WALL_MARGIN, WALL_MARGIN,
    ARENA_SIZE - 2 * WALL_MARGIN, ARENA_SIZE - 2 * WALL_MARGIN
)

var enemy = null  # CharacterBody2D (enemy.gd)


func set_enemy(e) -> void:
    enemy = e


func get_inputs() -> PackedFloat32Array:
    ## Gather sensor inputs from the live game state.
    ## Uses the player sensor's per-frame cache for obstacle positions.
    var inputs := PackedFloat32Array()
    inputs.resize(TOTAL_INPUTS)
    inputs.fill(0.0)

    if not enemy or not is_instance_valid(enemy):
        return inputs

    var player = enemy.player
    if not player or not is_instance_valid(player):
        return inputs

    # Gather obstacle positions from cached arena data
    var obstacle_positions: Array = []
    sensor_cache._build_cache(enemy.get_tree())
    var parent: Node = enemy.get_parent()
    var obstacles: Array = sensor_cache._arena_obstacles.get(parent, [])
    for obs in obstacles:
        if is_instance_valid(obs):
            obstacle_positions.append(obs.global_position)

    return compute_inputs(
        enemy.global_position,
        enemy.type,
        player.global_position,
        player.velocity,
        player.is_invincible,
        player.is_speed_boosted,
        player.is_slow_active,
        obstacle_positions,
        arena_bounds
    )


func compute_inputs(
    enemy_pos: Vector2,
    enemy_type: int,
    player_pos: Vector2,
    player_velocity: Vector2,
    player_invincible: bool,
    player_speed_boosted: bool,
    player_slow_active: bool,
    obstacle_positions: Array,
    bounds: Rect2
) -> PackedFloat32Array:
    ## Pure computation — testable without scene tree.
    ## All 16 inputs normalized to roughly [-1, 1] or [0, 1] range.
    var inputs := PackedFloat32Array()
    inputs.resize(TOTAL_INPUTS)
    inputs.fill(0.0)
    var idx := 0

    # --- Player direction/distance (2 inputs) ---
    # Direction vector scaled by proximity: close player → large magnitude
    var to_player := player_pos - enemy_pos
    var dist := to_player.length()
    var closeness := 1.0 - clampf(dist / MAX_DETECT_RANGE, 0.0, 1.0)
    if dist > 0.001:
        var dir := to_player / dist  # normalized
        inputs[idx] = dir.x * closeness
        inputs[idx + 1] = dir.y * closeness
    idx += 2

    # --- Nearest obstacle directions (4 inputs) ---
    # 2 nearest obstacles, each encoded as direction × proximity (2 floats each)
    var nearest := _find_nearest_obstacles(enemy_pos, obstacle_positions, 2)
    for i in 2:
        if i < nearest.size():
            var to_obs: Vector2 = nearest[i] - enemy_pos
            var obs_dist := to_obs.length()
            var obs_closeness := 1.0 - clampf(obs_dist / MAX_OBSTACLE_RANGE, 0.0, 1.0)
            if obs_dist > 0.001:
                var obs_dir := to_obs / obs_dist
                inputs[idx] = obs_dir.x * obs_closeness
                inputs[idx + 1] = obs_dir.y * obs_closeness
        idx += 2

    # --- Wall distances (4 inputs: N, E, S, W) ---
    # Normalized by arena size; closer to wall → smaller value
    inputs[idx] = clampf((enemy_pos.y - bounds.position.y) / ARENA_SIZE, 0.0, 1.0)
    inputs[idx + 1] = clampf((bounds.end.x - enemy_pos.x) / ARENA_SIZE, 0.0, 1.0)
    inputs[idx + 2] = clampf((bounds.end.y - enemy_pos.y) / ARENA_SIZE, 0.0, 1.0)
    inputs[idx + 3] = clampf((enemy_pos.x - bounds.position.x) / ARENA_SIZE, 0.0, 1.0)
    idx += 4

    # --- Own type encoding (1 input) ---
    inputs[idx] = TYPE_ENCODING.get(enemy_type, 0.0)
    idx += 1

    # --- Player velocity (2 inputs) ---
    inputs[idx] = clampf(player_velocity.x / MAX_SPEED, -1.0, 1.0)
    inputs[idx + 1] = clampf(player_velocity.y / MAX_SPEED, -1.0, 1.0)
    idx += 2

    # --- Player power-up state flags (3 inputs) ---
    inputs[idx] = 1.0 if player_invincible else 0.0
    inputs[idx + 1] = 1.0 if player_speed_boosted else 0.0
    inputs[idx + 2] = 1.0 if player_slow_active else 0.0
    idx += 3

    return inputs


func _find_nearest_obstacles(pos: Vector2, obstacle_positions: Array, count: int) -> Array:
    ## Return positions of the nearest `count` obstacles.
    if obstacle_positions.is_empty():
        return []

    var sorted_obs := obstacle_positions.duplicate()
    sorted_obs.sort_custom(func(a, b):
        return pos.distance_squared_to(a) < pos.distance_squared_to(b)
    )

    return sorted_obs.slice(0, count)
