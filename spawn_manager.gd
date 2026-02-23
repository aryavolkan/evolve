extends RefCounted
class_name SpawnManager

## Manages enemy and powerup spawning for a game scene.

var scene: Node2D
var player: CharacterBody2D
var rng: RandomNumberGenerator

var enemy_scene: PackedScene = preload("res://enemy.tscn")
var powerup_scene: PackedScene = preload("res://powerup.tscn")
var obstacle_scene: PackedScene = preload("res://obstacle.tscn")

# Arena configuration references (set during setup)
var effective_arena_width: float = 3840.0
var effective_arena_height: float = 3840.0

# Per-frame cache to avoid repeated group lookups
var _cached_enemies: Array = []
var _cached_enemies_frame: int = -1


func setup(p_scene: Node2D, p_player: CharacterBody2D, p_rng: RandomNumberGenerator) -> void:
    scene = p_scene
    player = p_player
    rng = p_rng


func spawn_enemy(training_mode: bool, curriculum_config: Dictionary, difficulty_factor: float, enemy_speed: float, enemy_ai_network, freeze_active: bool, slow_active: bool) -> void:
    var enemy = enemy_scene.instantiate()
    enemy.speed = enemy_speed

    if training_mode and not curriculum_config.is_empty():
        var allowed: Array = curriculum_config.get("enemy_types", [0])
        enemy.type = allowed[rng.randi() % allowed.size()]
    elif training_mode:
        enemy.type = 0  # Pawn
    else:
        var type_roll = rng.randf()
        if type_roll < 0.5 - difficulty_factor * 0.3:
            enemy.type = 0  # Pawn
        elif type_roll < 0.7 - difficulty_factor * 0.1:
            enemy.type = 1  # Knight
        elif type_roll < 0.85:
            enemy.type = 2  # Bishop
        elif type_roll < 0.95:
            enemy.type = 3  # Rook
        else:
            enemy.type = 4  # Queen

    enemy.position = get_random_edge_spawn_position()
    enemy.rng = rng
    scene.add_child(enemy)

    if enemy_ai_network:
        enemy.setup_ai(enemy_ai_network)

    if freeze_active:
        enemy.apply_freeze()
    elif slow_active:
        enemy.apply_slow(0.5)


func spawn_enemy_at(pos: Vector2, enemy_type: int, enemy_speed: float, training_mode: bool, enemy_ai_network, freeze_active: bool, slow_active: bool) -> void:
    var enemy = enemy_scene.instantiate()
    enemy.speed = enemy_speed * (0.5 if training_mode else 1.0)
    enemy.type = enemy_type
    enemy.position = pos
    enemy.rng = rng
    scene.add_child(enemy)

    if enemy_ai_network:
        enemy.setup_ai(enemy_ai_network)

    if freeze_active:
        enemy.apply_freeze()
    elif slow_active:
        enemy.apply_slow(0.5)


func spawn_initial_enemies(training_mode: bool, base_speed: float, enemy_ai_network) -> void:
    var enemy_count = 3 if training_mode else 10
    for i in range(enemy_count):
        var enemy = enemy_scene.instantiate()
        enemy.speed = base_speed * (0.5 if training_mode else 1.0)
        enemy.type = 0  # Pawn
        enemy.position = get_random_edge_spawn_position()
        enemy.rng = rng
        scene.add_child(enemy)
        if enemy_ai_network:
            enemy.setup_ai(enemy_ai_network)


func spawn_powerup_at(pos: Vector2, powerup_type: int, max_powerups: int, collected_callback: Callable) -> void:
    if count_local_powerups() >= max_powerups:
        return
    var powerup = powerup_scene.instantiate()
    powerup.position = pos
    powerup.set_type(powerup_type)
    powerup.collected.connect(collected_callback)
    scene.add_child(powerup)


func spawn_powerup(max_powerups: int, collected_callback: Callable) -> bool:
    if count_local_powerups() >= max_powerups:
        return false

    var powerup = powerup_scene.instantiate()
    var pos = find_valid_powerup_position()
    if pos == Vector2.ZERO:
        powerup.queue_free()
        return false

    powerup.position = pos
    var type_index = rng.randi() % 10
    powerup.set_type(type_index)
    powerup.collected.connect(collected_callback)
    scene.add_child(powerup)
    return true


func find_valid_powerup_position() -> Vector2:
    const POWERUP_OBSTACLE_MIN_DIST: float = 80.0
    const POWERUP_PLAYER_MIN_DIST: float = 150.0
    const ARENA_PADDING: float = 100.0

    for attempt in range(20):
        var pos = Vector2(
            rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING),
            rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING)
        )
        var player_dist = pos.distance_to(player.position)
        if player_dist < POWERUP_PLAYER_MIN_DIST:
            continue

        var valid = true
        for obstacle_pos in scene.spawned_obstacle_positions:
            if pos.distance_to(obstacle_pos) < POWERUP_OBSTACLE_MIN_DIST:
                valid = false
                break
        if valid:
            return pos

    return Vector2.ZERO


func spawn_arena_obstacles(use_preset_events: bool, preset_obstacles: Array) -> void:
    scene.spawned_obstacle_positions.clear()
    const ARENA_PADDING: float = 100.0
    const OBSTACLE_COUNT: int = 40
    const OBSTACLE_MIN_DISTANCE: float = 150.0
    const OBSTACLE_PLAYER_SAFE_ZONE: float = 300.0

    if use_preset_events and preset_obstacles.size() > 0:
        for obstacle_data in preset_obstacles:
            var obstacle = obstacle_scene.instantiate()
            obstacle.position = obstacle_data.pos
            scene.add_child(obstacle)
            scene.spawned_obstacle_positions.append(obstacle_data.pos)
        return

    var arena_center = Vector2(effective_arena_width / 2, effective_arena_height / 2)
    for i in range(OBSTACLE_COUNT):
        var placed = false
        for attempt in range(50):
            var pos = Vector2(
                rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING),
                rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING)
            )
            if pos.distance_to(arena_center) < OBSTACLE_PLAYER_SAFE_ZONE:
                continue
            var too_close = false
            for existing_pos in scene.spawned_obstacle_positions:
                if pos.distance_to(existing_pos) < OBSTACLE_MIN_DISTANCE:
                    too_close = true
                    break
            if not too_close:
                var obstacle = obstacle_scene.instantiate()
                obstacle.position = pos
                scene.add_child(obstacle)
                scene.spawned_obstacle_positions.append(pos)
                placed = true
                break
        if not placed:
            print("Warning: Could not place obstacle %d" % i)


func get_random_edge_spawn_position() -> Vector2:
    const ARENA_PADDING: float = 100.0
    var edge = rng.randi() % 4
    var pos: Vector2
    match edge:
        0: pos = Vector2(rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING), ARENA_PADDING)
        1: pos = Vector2(rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING), effective_arena_height - ARENA_PADDING)
        2: pos = Vector2(ARENA_PADDING, rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING))
        3: pos = Vector2(effective_arena_width - ARENA_PADDING, rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING))
    return pos


var _cached_powerup_count: int = 0
var _cached_powerup_frame: int = -1

func count_local_powerups() -> int:
    var frame := Engine.get_process_frames()
    if frame == _cached_powerup_frame:
        return _cached_powerup_count
    _cached_powerup_count = 0
    for p in scene.get_tree().get_nodes_in_group("powerup"):
        if is_instance_valid(p) and not p.is_queued_for_deletion() and p.get_parent() == scene:
            _cached_powerup_count += 1
    _cached_powerup_frame = frame
    return _cached_powerup_count


func get_local_enemies() -> Array:
    ## Returns enemies local to this scene, cached per frame.
    var frame = Engine.get_process_frames()
    if frame == _cached_enemies_frame:
        return _cached_enemies
    _cached_enemies.clear()
    for child in scene.get_children():
        if child.is_in_group("enemy"):
            if is_instance_valid(child) and not child.is_queued_for_deletion():
                _cached_enemies.append(child)
    _cached_enemies_frame = frame
    return _cached_enemies
