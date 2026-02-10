extends RefCounted

## Enemy AI controller.
## Takes 8 neural network outputs (directional preferences for N, NE, E, SE,
## S, SW, W, NW) and selects the best legal move for the enemy's chess piece
## type. Each piece type has restricted legal directions matching its movement
## pattern from enemy.gd.

var EnemySensorScript = preload("res://ai/enemy_sensor.gd")

var network = null
var sensor = null
var enemy = null  # CharacterBody2D (enemy.gd)

# Direction indices matching network output positions
const DIR_N := 0
const DIR_NE := 1
const DIR_E := 2
const DIR_SE := 3
const DIR_S := 4
const DIR_SW := 5
const DIR_W := 6
const DIR_NW := 7

const NUM_OUTPUTS := 8
const TILE_SIZE := 50.0

# Cardinal direction indices (used by pawn, rook)
const CARDINAL_DIRS: Array = [DIR_N, DIR_E, DIR_S, DIR_W]

# Diagonal direction indices (used by bishop)
const DIAGONAL_DIRS: Array = [DIR_NE, DIR_SE, DIR_SW, DIR_NW]

# Direction unit vectors (Y-down coordinate system)
# Indexed by DIR_N..DIR_NW
var _dir_vectors: Array = []

# Knight L-moves pre-mapped to their closest direction index
# Each entry: {"offset": Vector2, "dir_idx": int}
var _knight_moves: Array = []


func _init(p_network = null) -> void:
	sensor = EnemySensorScript.new()
	network = p_network

	# Pre-compute direction vectors
	_dir_vectors = [
		Vector2(0, -1),                      # N
		Vector2(1, -1).normalized(),          # NE
		Vector2(1, 0),                        # E
		Vector2(1, 1).normalized(),           # SE
		Vector2(0, 1),                        # S
		Vector2(-1, 1).normalized(),          # SW
		Vector2(-1, 0),                       # W
		Vector2(-1, -1).normalized(),         # NW
	]

	# Pre-compute knight L-move → closest direction mappings
	var knight_offsets: Array = [
		Vector2(2, 1), Vector2(2, -1), Vector2(-2, 1), Vector2(-2, -1),
		Vector2(1, 2), Vector2(1, -2), Vector2(-1, 2), Vector2(-1, -2)
	]
	for offset in knight_offsets:
		var best_dir := 0
		var best_dot := -INF
		var offset_norm: Vector2 = offset.normalized()
		for d in NUM_OUTPUTS:
			var dot_val: float = offset_norm.dot(_dir_vectors[d])
			if dot_val > best_dot:
				best_dot = dot_val
				best_dir = d
		_knight_moves.append({"offset": offset, "dir_idx": best_dir})


func set_enemy(e) -> void:
	enemy = e
	sensor.set_enemy(e)


func set_network(net) -> void:
	network = net


func get_move() -> Vector2:
	## Run the full sensor → network → move selection pipeline.
	## Returns the move offset vector for the enemy.
	if not network or not enemy:
		return Vector2.ZERO

	var inputs: PackedFloat32Array = sensor.get_inputs()
	var outputs: PackedFloat32Array = network.forward(inputs)
	return select_move_from_outputs(outputs, enemy.type, enemy.rng)


func select_move_from_outputs(outputs: PackedFloat32Array, piece_type: int, rng_instance = null) -> Vector2:
	## Select the best legal move based on network outputs and piece type.
	## Exposed for testing without scene tree.
	##
	## piece_type: Enemy.Type enum value (PAWN=0, KNIGHT=1, BISHOP=2, ROOK=3, QUEEN=4)
	match piece_type:
		0: return _select_pawn_move(outputs)
		1: return _select_knight_move(outputs)
		2: return _select_bishop_move(outputs, rng_instance)
		3: return _select_rook_move(outputs, rng_instance)
		4: return _select_queen_move(outputs, rng_instance)
	return Vector2.ZERO


func _select_pawn_move(outputs: PackedFloat32Array) -> Vector2:
	## Pawn: one tile in any cardinal direction (N, E, S, W).
	var best_idx := _best_direction(outputs, CARDINAL_DIRS)
	return _dir_vectors[best_idx] * TILE_SIZE


func _select_knight_move(outputs: PackedFloat32Array) -> Vector2:
	## Knight: L-shaped moves (2+1 tiles). Each L-move is scored by
	## the network output of its closest cardinal/intercardinal direction.
	var best_score := -INF
	var best_offset := Vector2.ZERO
	for move in _knight_moves:
		var score: float = outputs[move.dir_idx]
		if score > best_score:
			best_score = score
			best_offset = move.offset
	return best_offset * TILE_SIZE


func _select_bishop_move(outputs: PackedFloat32Array, rng_instance = null) -> Vector2:
	## Bishop: diagonal movement (NE, SE, SW, NW), 1-2 tiles.
	var best_idx := _best_direction(outputs, DIAGONAL_DIRS)
	# Diagonal direction vectors are normalized (length ~0.707 each component).
	# Use the raw component signs for tile-based movement.
	var dir: Vector2 = _dir_vectors[best_idx]
	var dx := signf(dir.x)
	var dy := signf(dir.y)
	var tiles: int = 1 + (_randi(rng_instance) % 2)  # 1-2 tiles
	return Vector2(dx, dy) * TILE_SIZE * tiles


func _select_rook_move(outputs: PackedFloat32Array, rng_instance = null) -> Vector2:
	## Rook: straight line movement (N, E, S, W), 1-3 tiles.
	var best_idx := _best_direction(outputs, CARDINAL_DIRS)
	var tiles: int = 1 + (_randi(rng_instance) % 3)  # 1-3 tiles
	return _dir_vectors[best_idx] * TILE_SIZE * tiles


func _select_queen_move(outputs: PackedFloat32Array, rng_instance = null) -> Vector2:
	## Queen: any of 8 directions. Cardinal 1-3 tiles, diagonal 1-2 tiles.
	var all_dirs: Array = [DIR_N, DIR_NE, DIR_E, DIR_SE, DIR_S, DIR_SW, DIR_W, DIR_NW]
	var best_idx := _best_direction(outputs, all_dirs)
	var is_diagonal: bool = best_idx % 2 == 1  # Odd indices are diagonals
	var max_tiles: int = 2 if is_diagonal else 3
	var tiles: int = 1 + (_randi(rng_instance) % max_tiles)
	var dir: Vector2 = _dir_vectors[best_idx]
	if is_diagonal:
		# Use integer signs for tile-based diagonal movement
		return Vector2(signf(dir.x), signf(dir.y)) * TILE_SIZE * tiles
	else:
		return dir * TILE_SIZE * tiles


func _best_direction(outputs: PackedFloat32Array, legal_dirs: Array) -> int:
	## Find the direction index with the highest output among legal directions.
	var best_score := -INF
	var best_idx: int = legal_dirs[0]
	for idx in legal_dirs:
		if outputs[idx] > best_score:
			best_score = outputs[idx]
			best_idx = idx
	return best_idx


func _randi(rng_instance) -> int:
	## Get a random integer using the arena's RNG or global fallback.
	if rng_instance:
		return rng_instance.randi()
	return randi()
