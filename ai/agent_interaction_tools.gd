extends RefCounted

## Shared interaction tools for rtNEAT and team battle modes:
## speed control, obstacle placement/removal, wave spawning, bless/curse, logging.

enum Tool { INSPECT, PLACE_OBSTACLE, REMOVE_OBSTACLE, SPAWN_WAVE, BLESS, CURSE }

const BLESS_FITNESS: float = 2000.0
const CURSE_FITNESS: float = 2000.0
const WAVE_SIZE: int = 5
const WAVE_SPREAD: float = 200.0
const OBSTACLE_REMOVE_RADIUS: float = 80.0
const MAX_LOG_ENTRIES: int = 5
const SPEED_STEPS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0]

var main_scene: Node2D = null
var current_tool: int = Tool.INSPECT
var player_obstacles: Array = []
var replacement_log: Array = []
var time_scale: float = 1.0
var _total_time: float = 0.0

var _bless_fn: Callable = Callable()
var _curse_fn: Callable = Callable()
var _tool_changed_fn: Callable = Callable()


func setup(scene: Node2D, config: Dictionary = {}) -> void:
    main_scene = scene

    if config.has("player_obstacles") and config["player_obstacles"] != null:
        player_obstacles = config["player_obstacles"]
    elif player_obstacles == null:
        player_obstacles = []

    if config.has("replacement_log") and config["replacement_log"] != null:
        replacement_log = config["replacement_log"]
    elif replacement_log == null:
        replacement_log = []

    _bless_fn = config.get("bless_fn", _bless_fn)
    _curse_fn = config.get("curse_fn", _curse_fn)
    _tool_changed_fn = config.get("on_tool_changed", _tool_changed_fn)


func reset_time(value: float = 0.0) -> void:
    _total_time = value


func update_time(delta: float) -> void:
    if delta <= 0.0:
        return
    _total_time += delta


# ============================================================
# Speed control
# ============================================================

func adjust_speed(direction: float) -> void:
    var current_idx: int = SPEED_STEPS.find(time_scale)
    if current_idx == -1:
        current_idx = 2  # Default to 1.0x
    if direction > 0 and current_idx < SPEED_STEPS.size() - 1:
        current_idx += 1
    elif direction < 0 and current_idx > 0:
        current_idx -= 1
    time_scale = SPEED_STEPS[current_idx]
    Engine.time_scale = time_scale


# ============================================================
# Tool dispatch
# ============================================================

func set_tool(tool: int) -> void:
    if current_tool == tool:
        return
    current_tool = tool
    _notify_tool_change()


func get_tool_name() -> String:
    match current_tool:
        Tool.INSPECT:
            return "INSPECT"
        Tool.PLACE_OBSTACLE:
            return "PLACE"
        Tool.REMOVE_OBSTACLE:
            return "REMOVE"
        Tool.SPAWN_WAVE:
            return "SPAWN"
        Tool.BLESS:
            return "BLESS"
        Tool.CURSE:
            return "CURSE"
    return "INSPECT"


func handle_click(world_pos: Vector2) -> bool:
    ## Dispatch click to active tool. Returns true if handled (non-inspect).
    match current_tool:
        Tool.INSPECT:
            return false
        Tool.PLACE_OBSTACLE:
            _place_obstacle(world_pos)
        Tool.REMOVE_OBSTACLE:
            _remove_obstacle(world_pos)
        Tool.SPAWN_WAVE:
            _spawn_wave(world_pos)
        Tool.BLESS:
            _invoke_callable(_bless_fn, world_pos)
        Tool.CURSE:
            _invoke_callable(_curse_fn, world_pos)
    return true


func _invoke_callable(fn: Callable, arg: Vector2) -> void:
    if fn and fn.is_valid():
        fn.call(arg)


func _notify_tool_change() -> void:
    if _tool_changed_fn and _tool_changed_fn.is_valid():
        _tool_changed_fn.call(current_tool)


# ============================================================
# Tool implementations
# ============================================================

func _place_obstacle(pos: Vector2) -> void:
    if not main_scene:
        return
    var obstacle_scene: PackedScene = load("res://obstacle.tscn")
    var obstacle = obstacle_scene.instantiate()
    obstacle.position = pos
    main_scene.add_child(obstacle)
    player_obstacles.append(obstacle)
    if main_scene and main_scene.spawned_obstacle_positions != null:
        main_scene.spawned_obstacle_positions.append(pos)
    log_event("Placed obstacle at (%.0f, %.0f)" % [pos.x, pos.y])


func _remove_obstacle(pos: Vector2) -> void:
    var nearest_obs = null
    var nearest_dist: float = OBSTACLE_REMOVE_RADIUS
    for obs in player_obstacles:
        if not is_instance_valid(obs):
            continue
        var dist: float = obs.position.distance_to(pos)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest_obs = obs
    if nearest_obs:
        var obs_pos: Vector2 = nearest_obs.position
        player_obstacles.erase(nearest_obs)
        if main_scene and main_scene.spawned_obstacle_positions != null:
            var pos_idx: int = main_scene.spawned_obstacle_positions.find(obs_pos)
            if pos_idx >= 0:
                main_scene.spawned_obstacle_positions.remove_at(pos_idx)
        nearest_obs.queue_free()
        log_event("Removed obstacle at (%.0f, %.0f)" % [obs_pos.x, obs_pos.y])


func _spawn_wave(pos: Vector2) -> void:
    if not main_scene:
        return
    var weights: Array[int] = [0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3]
    for i in WAVE_SIZE:
        var angle: float = TAU * i / WAVE_SIZE
        var spawn_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * WAVE_SPREAD
        var enemy_type: int = weights[randi() % weights.size()]
        main_scene.spawn_enemy_at(spawn_pos, enemy_type)
    log_event("Spawned wave of %d enemies" % WAVE_SIZE)


# ============================================================
# Logging
# ============================================================

func log_event(text: String) -> void:
    if replacement_log == null:
        replacement_log = []
    replacement_log.push_front({"text": text, "time": _total_time})
    if replacement_log.size() > MAX_LOG_ENTRIES:
        replacement_log.pop_back()


# ============================================================
# Cleanup
# ============================================================

func cleanup() -> void:
    for obs in player_obstacles:
        if is_instance_valid(obs):
            obs.queue_free()
    player_obstacles.clear()
    current_tool = Tool.INSPECT
    time_scale = 1.0
    Engine.time_scale = 1.0
    _total_time = 0.0
    _notify_tool_change()

