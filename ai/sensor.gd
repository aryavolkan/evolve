extends RefCounted

## Grid-based perception system for the AI agent.
## Divides the entire arena into a grid and encodes entity positions.
## Optimized: O(entities) instead of O(cells × entities)

const GRID_COLS: int = 16
const GRID_ROWS: int = 9
const CHANNELS_PER_CELL: int = 4  # (enemy_type, obstacle, powerup_type, player)

# Total inputs: grid + player state
# 16x9 grid × 4 channels = 576 grid inputs
# + 6 player state inputs = 582 total
const PLAYER_STATE_INPUTS: int = 6
const TOTAL_INPUTS: int = GRID_COLS * GRID_ROWS * CHANNELS_PER_CELL + PLAYER_STATE_INPUTS

# Arena dimensions (matches main.gd ARENA_WIDTH/HEIGHT)
const ARENA_WIDTH: float = 2560.0
const ARENA_HEIGHT: float = 1440.0
const CELL_WIDTH: float = ARENA_WIDTH / GRID_COLS   # 80px
const CELL_HEIGHT: float = ARENA_HEIGHT / GRID_ROWS  # 80px

var player: CharacterBody2D


func set_player(p: CharacterBody2D) -> void:
	player = p


func pos_to_cell(pos: Vector2) -> int:
	## Convert world position to cell index. Returns -1 if out of bounds.
	var col := int(pos.x / CELL_WIDTH)
	var row := int(pos.y / CELL_HEIGHT)
	if col < 0 or col >= GRID_COLS or row < 0 or row >= GRID_ROWS:
		return -1
	return (row * GRID_COLS + col) * CHANNELS_PER_CELL


func get_inputs() -> PackedFloat32Array:
	## Gather all sensor inputs for the neural network.
	## Optimized: directly maps entity positions to grid cells.

	var inputs := PackedFloat32Array()
	inputs.resize(TOTAL_INPUTS)
	inputs.fill(0.0)

	if not player or not is_instance_valid(player):
		return inputs

	var player_scene := player.get_parent()

	# Place player in grid (channel 3)
	var player_cell := pos_to_cell(player.global_position)
	if player_cell >= 0:
		inputs[player_cell + 3] = 1.0

	# Place enemies in grid (channel 0)
	for enemy in player.get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get_parent() != player_scene:
			continue
		var cell := pos_to_cell(enemy.global_position)
		if cell >= 0:
			var value := 0.3  # Default
			if enemy.has_method("get_point_value"):
				var points: int = enemy.get_point_value()
				match points:
					1: value = 0.2   # Pawn
					3: value = 0.5   # Knight/Bishop
					5: value = 0.8   # Rook
					9: value = 1.0   # Queen
			# Keep highest value if multiple enemies in cell
			if value > inputs[cell]:
				inputs[cell] = value

	# Place obstacles in grid (channel 1)
	for obstacle in player.get_tree().get_nodes_in_group("obstacle"):
		if not is_instance_valid(obstacle) or obstacle.get_parent() != player_scene:
			continue
		var cell := pos_to_cell(obstacle.global_position)
		if cell >= 0:
			inputs[cell + 1] = 1.0

	# Place powerups in grid (channel 2)
	for powerup in player.get_tree().get_nodes_in_group("powerup"):
		if not is_instance_valid(powerup) or powerup.get_parent() != player_scene:
			continue
		var cell := pos_to_cell(powerup.global_position)
		if cell >= 0:
			var value := 0.5  # Default
			if powerup.has_method("get_type_name"):
				match powerup.get_type_name():
					"SPEED BOOST": value = 0.25
					"INVINCIBILITY": value = 0.5
					"SLOW ENEMIES": value = 0.75
					"SCREEN CLEAR": value = 1.0
			inputs[cell + 2] = value

	# Player state inputs (after grid)
	var state_idx := GRID_COLS * GRID_ROWS * CHANNELS_PER_CELL
	var max_speed := 500.0

	inputs[state_idx] = clampf(player.velocity.x / max_speed, -1.0, 1.0)
	inputs[state_idx + 1] = clampf(player.velocity.y / max_speed, -1.0, 1.0)
	inputs[state_idx + 2] = 1.0 if player.is_invincible else 0.0
	inputs[state_idx + 3] = 1.0 if player.is_speed_boosted else 0.0
	inputs[state_idx + 4] = 1.0 if player.is_slow_active else 0.0
	inputs[state_idx + 5] = 1.0 if player.can_shoot else 0.0

	return inputs
