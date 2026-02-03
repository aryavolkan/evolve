extends RefCounted

## Raycast-based perception system for the AI agent.
## Casts rays around the player to detect enemies, obstacles, and power-ups.

const NUM_RAYS: int = 16
const RAY_LENGTH: float = 1500.0  # Long enough to span most of 2560x1440 arena
const INPUTS_PER_RAY: int = 5  # (enemy_dist, enemy_type, obstacle_dist, powerup_dist, wall_dist)

# Total inputs: rays + player state
# 16 rays × 5 values = 80 ray inputs
# + 6 player state inputs = 86 total
const PLAYER_STATE_INPUTS: int = 6
const TOTAL_INPUTS: int = NUM_RAYS * INPUTS_PER_RAY + PLAYER_STATE_INPUTS

# Arena bounds
const ARENA_WIDTH: float = 2560.0
const ARENA_HEIGHT: float = 1440.0
var arena_bounds: Rect2 = Rect2(40, 40, ARENA_WIDTH - 80, ARENA_HEIGHT - 80)

var player: CharacterBody2D
var ray_angles: PackedFloat32Array


func _init() -> void:
	# Pre-compute ray angles (evenly distributed around player)
	ray_angles.resize(NUM_RAYS)
	for i in NUM_RAYS:
		ray_angles[i] = (float(i) / NUM_RAYS) * TAU


func set_player(p: CharacterBody2D) -> void:
	player = p


func get_inputs() -> PackedFloat32Array:
	## Gather all sensor inputs for the neural network.

	var inputs := PackedFloat32Array()
	inputs.resize(TOTAL_INPUTS)
	inputs.fill(0.0)

	if not player or not is_instance_valid(player):
		return inputs

	var player_pos := player.global_position
	var player_scene := player.get_parent()

	# Collect entities from player's scene only
	var enemies: Array = []
	var obstacles: Array = []
	var powerups: Array = []

	for e in player.get_tree().get_nodes_in_group("enemy"):
		if e.get_parent() == player_scene:
			enemies.append(e)
	for o in player.get_tree().get_nodes_in_group("obstacle"):
		if o.get_parent() == player_scene:
			obstacles.append(o)
	for p in player.get_tree().get_nodes_in_group("powerup"):
		if p.get_parent() == player_scene:
			powerups.append(p)

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

	# Player state inputs
	var max_speed := 500.0
	inputs[input_idx] = clampf(player.velocity.x / max_speed, -1.0, 1.0)
	inputs[input_idx + 1] = clampf(player.velocity.y / max_speed, -1.0, 1.0)
	inputs[input_idx + 2] = 1.0 if player.is_invincible else 0.0
	inputs[input_idx + 3] = 1.0 if player.is_speed_boosted else 0.0
	inputs[input_idx + 4] = 1.0 if player.is_slow_active else 0.0
	inputs[input_idx + 5] = 1.0 if player.can_shoot else 0.0

	return inputs


func cast_ray_to_entities(origin: Vector2, direction: Vector2, entities: Array, hit_radius: float) -> Dictionary:
	## Cast a ray and find the closest entity.
	var result := {"hit": false, "distance": RAY_LENGTH, "type_value": 0.0}

	for entity in entities:
		if not is_instance_valid(entity):
			continue

		var to_entity: Vector2 = entity.global_position - origin
		var projection: float = to_entity.dot(direction)

		if projection < 0 or projection > RAY_LENGTH:
			continue

		var closest_point: Vector2 = origin + direction * projection
		var dist_to_ray: float = closest_point.distance_to(entity.global_position)

		if dist_to_ray < hit_radius and projection < result.distance:
			result.hit = true
			result.distance = projection
			if entity.has_method("get_point_value"):
				var points: int = entity.get_point_value()
				match points:
					1: result.type_value = 0.2
					3: result.type_value = 0.5
					5: result.type_value = 0.8
					9: result.type_value = 1.0

	return result


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
