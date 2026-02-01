extends RefCounted

## Raycast-based perception system for the AI agent.
## Casts rays around the player to detect enemies, obstacles, and power-ups.

const NUM_RAYS: int = 16
const RAY_LENGTH: float = 500.0
const INPUTS_PER_RAY: int = 4  # (enemy_dist, enemy_type, obstacle_dist, powerup_dist)

# Total inputs: rays + player state
# 16 rays × 4 values = 64 ray inputs
# + 6 player state inputs = 70 total
const PLAYER_STATE_INPUTS: int = 6
const TOTAL_INPUTS: int = NUM_RAYS * INPUTS_PER_RAY + PLAYER_STATE_INPUTS

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
	## Returns normalized values in [-1, 1] or [0, 1] range.

	var inputs := PackedFloat32Array()
	inputs.resize(TOTAL_INPUTS)

	if not player or not is_instance_valid(player):
		return inputs  # Return zeros if no player

	var player_pos := player.global_position

	# Get all entities once
	var enemies := player.get_tree().get_nodes_in_group("enemy")
	var obstacles := player.get_tree().get_nodes_in_group("obstacle")
	var powerups := player.get_tree().get_nodes_in_group("powerup")

	# Cast rays
	var input_idx := 0
	for ray_idx in NUM_RAYS:
		var angle: float = ray_angles[ray_idx]
		var ray_dir := Vector2(cos(angle), sin(angle))

		# Find closest entity of each type along this ray
		var enemy_result := cast_ray_to_group(player_pos, ray_dir, enemies, 50.0)
		var obstacle_result := cast_ray_to_group(player_pos, ray_dir, obstacles, 40.0)
		var powerup_result := cast_ray_to_group(player_pos, ray_dir, powerups, 30.0)

		# Enemy distance (normalized, 1.0 = far/none, 0.0 = touching)
		inputs[input_idx] = 1.0 - (enemy_result.distance / RAY_LENGTH) if enemy_result.hit else 0.0
		input_idx += 1

		# Enemy type (normalized: pawn=0.2, knight=0.4, bishop=0.6, rook=0.8, queen=1.0)
		inputs[input_idx] = enemy_result.type_value if enemy_result.hit else 0.0
		input_idx += 1

		# Obstacle distance
		inputs[input_idx] = 1.0 - (obstacle_result.distance / RAY_LENGTH) if obstacle_result.hit else 0.0
		input_idx += 1

		# Power-up distance
		inputs[input_idx] = 1.0 - (powerup_result.distance / RAY_LENGTH) if powerup_result.hit else 0.0
		input_idx += 1

	# Player state inputs
	# Velocity (normalized by max speed)
	var max_speed := 500.0  # Boosted speed
	inputs[input_idx] = clampf(player.velocity.x / max_speed, -1.0, 1.0)
	input_idx += 1
	inputs[input_idx] = clampf(player.velocity.y / max_speed, -1.0, 1.0)
	input_idx += 1

	# Power-up states (0 or 1)
	inputs[input_idx] = 1.0 if player.is_invincible else 0.0
	input_idx += 1
	inputs[input_idx] = 1.0 if player.is_speed_boosted else 0.0
	input_idx += 1
	inputs[input_idx] = 1.0 if player.is_slow_active else 0.0
	input_idx += 1

	# Can shoot (0 or 1)
	inputs[input_idx] = 1.0 if player.can_shoot else 0.0

	return inputs


func cast_ray_to_group(origin: Vector2, direction: Vector2, entities: Array, hit_radius: float) -> Dictionary:
	## Cast a ray and find the closest entity from a group.
	## Uses simple geometric ray-circle intersection.

	var result := {"hit": false, "distance": RAY_LENGTH, "entity": null, "type_value": 0.0}

	for entity in entities:
		if not is_instance_valid(entity):
			continue

		var entity_pos: Vector2 = entity.global_position
		var to_entity := entity_pos - origin

		# Project entity position onto ray
		var projection := to_entity.dot(direction)
		if projection < 0 or projection > RAY_LENGTH:
			continue  # Behind us or too far

		# Distance from ray to entity center
		var closest_point := origin + direction * projection
		var dist_to_ray := closest_point.distance_to(entity_pos)

		if dist_to_ray < hit_radius:
			# Hit! Check if it's closer than previous hits
			if projection < result.distance:
				result.hit = true
				result.distance = projection
				result.entity = entity

				# Get type value for enemies
				if entity.has_method("get_point_value"):
					# Normalize by max point value (queen = 9)
					result.type_value = float(entity.get_point_value()) / 9.0

	return result
