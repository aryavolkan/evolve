extends RefCounted

## Raycast-based perception system for the AI agent.
## Casts rays around the player to detect enemies, obstacles, and power-ups.
##
## Performance: Entity lists are cached per-arena per-physics-frame via a static
## registry. With 20 parallel arenas, this avoids 60 get_nodes_in_group() calls
## per frame (20 arenas × 3 groups) and replaces them with 3 calls total plus
## one O(entities) partitioning pass.

const NUM_RAYS: int = 16
const RAY_LENGTH: float = 2800.0  # Long enough to span 3840x3840 square arena diagonal
const INPUTS_PER_RAY: int = 5  # (enemy_dist, enemy_type, obstacle_dist, powerup_dist, wall_dist)

# Total inputs: rays + player state
# 16 rays × 5 values = 80 ray inputs
# + 6 player state inputs = 86 total
const PLAYER_STATE_INPUTS: int = 6
const TOTAL_INPUTS: int = NUM_RAYS * INPUTS_PER_RAY + PLAYER_STATE_INPUTS

# Team mode: extended inputs with teammate/opponent detection
const TEAM_INPUTS_PER_RAY: int = 7  # Standard 5 + teammate_dist + opponent_dist
const TEAM_STATE_INPUTS: int = 7  # Standard 6 + team_id
const TEAM_TOTAL_INPUTS: int = NUM_RAYS * TEAM_INPUTS_PER_RAY + TEAM_STATE_INPUTS  # 119

# Arena bounds
const ARENA_WIDTH: float = 3840.0
const ARENA_HEIGHT: float = 3840.0
var arena_bounds: Rect2 = Rect2(40, 40, ARENA_WIDTH - 80, ARENA_HEIGHT - 80)

var player: CharacterBody2D
var ray_angles: PackedFloat32Array

# Team mode settings
var team_mode: bool = false
var owner_team_id: int = -1

# ============================================================
# Per-frame entity cache (static — shared across all sensors)
# ============================================================
# Built once per physics frame, maps parent_scene → Array of entities.
# Reduces get_nodes_in_group() from O(arenas × groups) to O(groups) per frame.

static var _cache_frame: int = -1
static var _arena_enemies: Dictionary = {}   # Node → Array[Node]
static var _arena_obstacles: Dictionary = {}  # Node → Array[Node]
static var _arena_powerups: Dictionary = {}   # Node → Array[Node]
static var _arena_agents: Dictionary = {}    # Node → Array[Node]


static func _build_cache(tree: SceneTree) -> void:
	## Rebuild the per-arena entity cache for the current physics frame.
	## Called at most once per frame (skipped if already current).
	var frame := Engine.get_physics_frames()
	if frame == _cache_frame:
		return
	_cache_frame = frame
	_arena_enemies.clear()
	_arena_obstacles.clear()
	_arena_powerups.clear()
	_arena_agents.clear()

	for e in tree.get_nodes_in_group("enemy"):
		var parent := e.get_parent()
		if not _arena_enemies.has(parent):
			_arena_enemies[parent] = []
		_arena_enemies[parent].append(e)

	for o in tree.get_nodes_in_group("obstacle"):
		var parent := o.get_parent()
		if not _arena_obstacles.has(parent):
			_arena_obstacles[parent] = []
		_arena_obstacles[parent].append(o)

	for p in tree.get_nodes_in_group("powerup"):
		var parent := p.get_parent()
		if not _arena_powerups.has(parent):
			_arena_powerups[parent] = []
		_arena_powerups[parent].append(p)

	for a in tree.get_nodes_in_group("agent"):
		var parent := a.get_parent()
		if not _arena_agents.has(parent):
			_arena_agents[parent] = []
		_arena_agents[parent].append(a)


static func invalidate_cache() -> void:
	## Force cache rebuild on next query (e.g. after bulk entity changes).
	_cache_frame = -1


func _init() -> void:
	# Pre-compute ray angles (evenly distributed around player)
	ray_angles.resize(NUM_RAYS)
	for i in NUM_RAYS:
		ray_angles[i] = (float(i) / NUM_RAYS) * TAU


func set_player(p: CharacterBody2D) -> void:
	player = p


func get_total_inputs() -> int:
	return TEAM_TOTAL_INPUTS if team_mode else TOTAL_INPUTS


func get_inputs() -> PackedFloat32Array:
	## Gather all sensor inputs for the neural network.

	var total := get_total_inputs()
	var inputs := PackedFloat32Array()
	inputs.resize(total)
	inputs.fill(0.0)

	if not player or not is_instance_valid(player):
		return inputs

	var player_pos := player.global_position
	var player_scene := player.get_parent()

	# Look up cached per-arena entity lists (built once per physics frame)
	_build_cache(player.get_tree())
	var enemies: Array = _arena_enemies.get(player_scene, [])
	var obstacles: Array = _arena_obstacles.get(player_scene, [])
	var powerups: Array = _arena_powerups.get(player_scene, [])

	# In team mode, split agents into teammates and opponents
	var teammates: Array = []
	var opponents: Array = []
	if team_mode:
		var all_agents: Array = _arena_agents.get(player_scene, [])
		for a in all_agents:
			if not is_instance_valid(a) or a == player:
				continue
			var a_team: int = a.get("team_id") if a.get("team_id") != null else -1
			if a_team == owner_team_id:
				teammates.append(a)
			else:
				opponents.append(a)

	# Cast rays
	var input_idx := 0
	for ray_idx in NUM_RAYS:
		var angle: float = ray_angles[ray_idx]
		var ray_dir := Vector2(cos(angle), sin(angle))

		# Find closest entity of each type along this ray
		var enemy_result := cast_ray_to_entities(player_pos, ray_dir, enemies, 50.0)
		var obstacle_result := cast_ray_to_entities(player_pos, ray_dir, obstacles, 40.0)
		var powerup_result := cast_ray_to_entities(player_pos, ray_dir, powerups, 30.0)

		# Enemy distance (normalized, 1.0 = close, 0.0 = far/none)
		inputs[input_idx] = 1.0 - (enemy_result.distance / RAY_LENGTH) if enemy_result.hit else 0.0
		input_idx += 1

		# Enemy type (pawn=0.2, knight/bishop=0.5, rook=0.8, queen=1.0)
		inputs[input_idx] = enemy_result.type_value if enemy_result.hit else 0.0
		input_idx += 1

		# Obstacle distance
		inputs[input_idx] = 1.0 - (obstacle_result.distance / RAY_LENGTH) if obstacle_result.hit else 0.0
		input_idx += 1

		# Power-up distance
		inputs[input_idx] = 1.0 - (powerup_result.distance / RAY_LENGTH) if powerup_result.hit else 0.0
		input_idx += 1

		# Wall distance
		var wall_dist := get_wall_distance(player_pos, ray_dir)
		inputs[input_idx] = 1.0 - (wall_dist / RAY_LENGTH) if wall_dist < RAY_LENGTH else 0.0
		input_idx += 1

		# Team mode: teammate and opponent distances
		if team_mode:
			var teammate_result := cast_ray_to_entities(player_pos, ray_dir, teammates, 40.0)
			var opponent_result := cast_ray_to_entities(player_pos, ray_dir, opponents, 40.0)
			inputs[input_idx] = 1.0 - (teammate_result.distance / RAY_LENGTH) if teammate_result.hit else 0.0
			input_idx += 1
			inputs[input_idx] = 1.0 - (opponent_result.distance / RAY_LENGTH) if opponent_result.hit else 0.0
			input_idx += 1

	# Player state inputs
	var max_speed := 500.0
	inputs[input_idx] = clampf(player.velocity.x / max_speed, -1.0, 1.0)
	inputs[input_idx + 1] = clampf(player.velocity.y / max_speed, -1.0, 1.0)
	inputs[input_idx + 2] = 1.0 if player.is_invincible else 0.0
	inputs[input_idx + 3] = 1.0 if player.is_speed_boosted else 0.0
	inputs[input_idx + 4] = 1.0 if player.is_slow_active else 0.0
	inputs[input_idx + 5] = 1.0 if player.can_shoot else 0.0

	# Team mode: append team_id
	if team_mode:
		inputs[input_idx + 6] = float(owner_team_id)

	return inputs


# Reusable result dict to avoid per-call allocation (16 rays × 3-5 casts = 48-80 dicts/frame/agent)
var _ray_result: Dictionary = {"hit": false, "distance": RAY_LENGTH, "type_value": 0.0}


func cast_ray_to_entities(origin: Vector2, direction: Vector2, entities: Array, hit_radius: float) -> Dictionary:
	## Cast a ray and find the closest entity.
	## Returns a reusable dict — caller must read values before next call.
	_ray_result.hit = false
	_ray_result.distance = RAY_LENGTH
	_ray_result.type_value = 0.0

	var hit_radius_sq := hit_radius * hit_radius

	for entity in entities:
		if not is_instance_valid(entity):
			continue

		var to_entity: Vector2 = entity.global_position - origin
		var projection: float = to_entity.dot(direction)

		if projection < 0 or projection > RAY_LENGTH:
			continue

		# Use squared distance to avoid sqrt (closest_point.distance_to)
		var perp_x: float = to_entity.x - direction.x * projection
		var perp_y: float = to_entity.y - direction.y * projection
		var dist_sq: float = perp_x * perp_x + perp_y * perp_y

		if dist_sq < hit_radius_sq and projection < _ray_result.distance:
			_ray_result.hit = true
			_ray_result.distance = projection
			if entity.has_method("get_point_value"):
				var points: int = entity.get_point_value()
				match points:
					1: _ray_result.type_value = 0.2
					3: _ray_result.type_value = 0.5
					5: _ray_result.type_value = 0.8
					9: _ray_result.type_value = 1.0

	return _ray_result


func get_wall_distance(origin: Vector2, direction: Vector2) -> float:
	## Calculate distance to arena wall in the given direction.
	var min_dist := RAY_LENGTH

	if direction.x > 0.001:
		var dist := (arena_bounds.end.x - origin.x) / direction.x
		if dist > 0 and dist < min_dist:
			min_dist = dist
	elif direction.x < -0.001:
		var dist := (arena_bounds.position.x - origin.x) / direction.x
		if dist > 0 and dist < min_dist:
			min_dist = dist

	if direction.y > 0.001:
		var dist := (arena_bounds.end.y - origin.y) / direction.y
		if dist > 0 and dist < min_dist:
			min_dist = dist
	elif direction.y < -0.001:
		var dist := (arena_bounds.position.y - origin.y) / direction.y
		if dist > 0 and dist < min_dist:
			min_dist = dist

	return min_dist
