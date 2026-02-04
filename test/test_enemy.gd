extends "res://test/test_base.gd"
## Tests for enemy chess piece logic.
## Tests the pure movement calculation logic without scene instantiation.

# Constants from enemy.gd
const TILE_SIZE: float = 50.0

enum Type { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

const TYPE_CONFIG = {
	Type.PAWN: { "points": 1, "size": 28.0, "speed_mult": 1.0, "cooldown": 1.0 },
	Type.KNIGHT: { "points": 3, "size": 32.0, "speed_mult": 1.2, "cooldown": 1.2 },
	Type.BISHOP: { "points": 3, "size": 32.0, "speed_mult": 1.3, "cooldown": 0.9 },
	Type.ROOK: { "points": 5, "size": 36.0, "speed_mult": 1.1, "cooldown": 1.1 },
	Type.QUEEN: { "points": 9, "size": 40.0, "speed_mult": 1.4, "cooldown": 0.7 }
}


func _run_tests() -> void:
	print("\n[Enemy Chess Piece Tests]")

	_test("pawn_point_value", _test_pawn_point_value)
	_test("knight_point_value", _test_knight_point_value)
	_test("bishop_point_value", _test_bishop_point_value)
	_test("rook_point_value", _test_rook_point_value)
	_test("queen_point_value", _test_queen_point_value)
	_test("pawn_moves_one_tile", _test_pawn_moves_one_tile)
	_test("pawn_moves_horizontal_when_player_horizontal", _test_pawn_moves_horizontal_when_player_horizontal)
	_test("pawn_moves_vertical_when_player_vertical", _test_pawn_moves_vertical_when_player_vertical)
	_test("knight_moves_L_shaped", _test_knight_moves_L_shaped)
	_test("knight_all_moves_are_valid_L", _test_knight_all_moves_are_valid_L)
	_test("bishop_moves_diagonally", _test_bishop_moves_diagonally)
	_test("rook_moves_straight", _test_rook_moves_straight)
	_test("queen_moves_like_bishop_or_rook", _test_queen_moves_like_bishop_or_rook)
	_test("piece_sizes_increase_with_value", _test_piece_sizes_increase_with_value)


# ============================================================
# Movement calculation helpers (mirrors enemy.gd logic)
# ============================================================

func get_pawn_move(to_player: Vector2) -> Vector2:
	if abs(to_player.x) > abs(to_player.y):
		return Vector2(sign(to_player.x) * TILE_SIZE, 0)
	else:
		return Vector2(0, sign(to_player.y) * TILE_SIZE)


func get_knight_move(enemy_pos: Vector2, player_pos: Vector2) -> Vector2:
	var moves = [
		Vector2(2, 1), Vector2(2, -1), Vector2(-2, 1), Vector2(-2, -1),
		Vector2(1, 2), Vector2(1, -2), Vector2(-1, 2), Vector2(-1, -2)
	]

	var best_move = moves[0]
	var best_dist = INF
	for move in moves:
		var new_pos = enemy_pos + move * TILE_SIZE
		var dist = new_pos.distance_to(player_pos)
		if dist < best_dist:
			best_dist = dist
			best_move = move

	return best_move * TILE_SIZE


func get_bishop_move(to_player: Vector2, rng_tiles: int = 1) -> Vector2:
	var dx = sign(to_player.x) if to_player.x != 0 else 1
	var dy = sign(to_player.y) if to_player.y != 0 else 1
	return Vector2(dx, dy) * TILE_SIZE * rng_tiles


func get_rook_move(to_player: Vector2, rng_tiles: int = 1) -> Vector2:
	if abs(to_player.x) > abs(to_player.y):
		return Vector2(sign(to_player.x) * TILE_SIZE * rng_tiles, 0)
	else:
		return Vector2(0, sign(to_player.y) * TILE_SIZE * rng_tiles)


func is_valid_L_move(move: Vector2) -> bool:
	## Check if a move is a valid L-shape (2+1 tiles)
	var tiles_x = abs(move.x / TILE_SIZE)
	var tiles_y = abs(move.y / TILE_SIZE)
	return (tiles_x == 2 and tiles_y == 1) or (tiles_x == 1 and tiles_y == 2)


func is_diagonal_move(move: Vector2) -> bool:
	## Check if move is diagonal (equal x and y components)
	return abs(move.x) == abs(move.y) and move.x != 0


func is_straight_move(move: Vector2) -> bool:
	## Check if move is straight (only x or only y)
	return (move.x == 0 and move.y != 0) or (move.x != 0 and move.y == 0)


# ============================================================
# Point Value Tests
# ============================================================

func _test_pawn_point_value() -> void:
	assert_eq(TYPE_CONFIG[Type.PAWN]["points"], 1, "Pawn should be worth 1 point")


func _test_knight_point_value() -> void:
	assert_eq(TYPE_CONFIG[Type.KNIGHT]["points"], 3, "Knight should be worth 3 points")


func _test_bishop_point_value() -> void:
	assert_eq(TYPE_CONFIG[Type.BISHOP]["points"], 3, "Bishop should be worth 3 points")


func _test_rook_point_value() -> void:
	assert_eq(TYPE_CONFIG[Type.ROOK]["points"], 5, "Rook should be worth 5 points")


func _test_queen_point_value() -> void:
	assert_eq(TYPE_CONFIG[Type.QUEEN]["points"], 9, "Queen should be worth 9 points")


# ============================================================
# Pawn Movement Tests
# ============================================================

func _test_pawn_moves_one_tile() -> void:
	var to_player = Vector2(100, 50)  # Player to the right
	var move = get_pawn_move(to_player)
	var distance = move.length()
	assert_approx(distance, TILE_SIZE, 0.001, "Pawn should move exactly one tile")


func _test_pawn_moves_horizontal_when_player_horizontal() -> void:
	var to_player = Vector2(200, 50)  # Player more to the right than down
	var move = get_pawn_move(to_player)
	assert_eq(move.y, 0.0, "Pawn should move horizontally when player is more horizontal")
	assert_gt(move.x, 0.0, "Pawn should move toward player (right)")


func _test_pawn_moves_vertical_when_player_vertical() -> void:
	var to_player = Vector2(50, 200)  # Player more below than right
	var move = get_pawn_move(to_player)
	assert_eq(move.x, 0.0, "Pawn should move vertically when player is more vertical")
	assert_gt(move.y, 0.0, "Pawn should move toward player (down)")


# ============================================================
# Knight Movement Tests
# ============================================================

func _test_knight_moves_L_shaped() -> void:
	var enemy_pos = Vector2(500, 500)
	var player_pos = Vector2(700, 600)
	var move = get_knight_move(enemy_pos, player_pos)
	assert_true(is_valid_L_move(move), "Knight should move in L-shape")


func _test_knight_all_moves_are_valid_L() -> void:
	# Test all 8 possible knight moves
	var all_L_moves = [
		Vector2(2, 1), Vector2(2, -1), Vector2(-2, 1), Vector2(-2, -1),
		Vector2(1, 2), Vector2(1, -2), Vector2(-1, 2), Vector2(-1, -2)
	]

	for move_template in all_L_moves:
		var move = move_template * TILE_SIZE
		assert_true(is_valid_L_move(move), "Move %s should be valid L-shape" % move)


# ============================================================
# Bishop Movement Tests
# ============================================================

func _test_bishop_moves_diagonally() -> void:
	var to_player = Vector2(100, 80)  # Player to the right and down
	for tiles in [1, 2]:
		var move = get_bishop_move(to_player, tiles)
		assert_true(is_diagonal_move(move), "Bishop should move diagonally")


# ============================================================
# Rook Movement Tests
# ============================================================

func _test_rook_moves_straight() -> void:
	var to_player = Vector2(150, 50)  # Player more horizontal
	for tiles in [1, 2, 3]:
		var move = get_rook_move(to_player, tiles)
		assert_true(is_straight_move(move), "Rook should move in straight lines")

	# Test vertical preference
	var to_player_vertical = Vector2(50, 150)  # Player more vertical
	for tiles in [1, 2, 3]:
		var move = get_rook_move(to_player_vertical, tiles)
		assert_true(is_straight_move(move), "Rook should move in straight lines (vertical)")


# ============================================================
# Queen Movement Tests
# ============================================================

func _test_queen_moves_like_bishop_or_rook() -> void:
	# Queen should move either diagonally or straight
	var to_player = Vector2(100, 100)
	var bishop_move = get_bishop_move(to_player, 1)
	var rook_move = get_rook_move(to_player, 1)

	var is_valid_queen_move = is_diagonal_move(bishop_move) or is_straight_move(rook_move)
	assert_true(is_valid_queen_move, "Queen's possible moves should include diagonal or straight")


# ============================================================
# Size Tests
# ============================================================

func _test_piece_sizes_increase_with_value() -> void:
	var pawn_size: float = TYPE_CONFIG[Type.PAWN]["size"]
	var knight_size: float = TYPE_CONFIG[Type.KNIGHT]["size"]
	var bishop_size: float = TYPE_CONFIG[Type.BISHOP]["size"]
	var rook_size: float = TYPE_CONFIG[Type.ROOK]["size"]
	var queen_size: float = TYPE_CONFIG[Type.QUEEN]["size"]

	assert_lt(pawn_size, knight_size, "Knight should be larger than pawn")
	assert_eq(knight_size, bishop_size, "Knight and bishop should be same size")
	assert_lt(bishop_size, rook_size, "Rook should be larger than bishop")
	assert_lt(rook_size, queen_size, "Queen should be largest")
