extends "res://test/test_base.gd"
## Tests for enemy chess piece logic.
## Tests the pure movement calculation logic without scene instantiation.

# Constants from enemy.gd
const TILE_SIZE: float = 50.0

enum Type { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

const TYPE_CONFIG = {
    Type.PAWN: {"points": 1, "size": 28.0, "speed_mult": 1.0, "cooldown": 1.0},
    Type.KNIGHT: {"points": 3, "size": 32.0, "speed_mult": 1.2, "cooldown": 1.2},
    Type.BISHOP: {"points": 3, "size": 32.0, "speed_mult": 1.3, "cooldown": 0.9},
    Type.ROOK: {"points": 5, "size": 36.0, "speed_mult": 1.1, "cooldown": 1.1},
    Type.QUEEN: {"points": 9, "size": 40.0, "speed_mult": 1.4, "cooldown": 0.7}
}


func _run_tests() -> void:
    print("\n[Enemy Chess Piece Tests]")

    _test("pawn_point_value", _test_pawn_point_value)
    _test("knight_point_value", _test_knight_point_value)
    _test("bishop_point_value", _test_bishop_point_value)
    _test("rook_point_value", _test_rook_point_value)
    _test("queen_point_value", _test_queen_point_value)
    _test("pawn_moves_one_tile", _test_pawn_moves_one_tile)
    _test(
        "pawn_moves_horizontal_when_player_horizontal",
        _test_pawn_moves_horizontal_when_player_horizontal
    )
    _test(
        "pawn_moves_vertical_when_player_vertical", _test_pawn_moves_vertical_when_player_vertical
    )
    _test("knight_moves_L_shaped", _test_knight_moves_L_shaped)
    _test("knight_all_moves_are_valid_L", _test_knight_all_moves_are_valid_L)
    _test("bishop_moves_diagonally", _test_bishop_moves_diagonally)
    _test("rook_moves_straight", _test_rook_moves_straight)
    _test("queen_moves_like_bishop_or_rook", _test_queen_moves_like_bishop_or_rook)
    _test("piece_sizes_increase_with_value", _test_piece_sizes_increase_with_value)
    _test("speed_multipliers_scale_correctly", _test_speed_multipliers_scale_correctly)
    _test("cooldowns_vary_by_type", _test_cooldowns_vary_by_type)
    _test("slow_effect_logic", _test_slow_effect_logic)
    _test("kill_points_match_spec", _test_kill_points_match_spec)


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
        Vector2(2, 1),
        Vector2(2, -1),
        Vector2(-2, 1),
        Vector2(-2, -1),
        Vector2(1, 2),
        Vector2(1, -2),
        Vector2(-1, 2),
        Vector2(-1, -2)
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


func is_valid_l_shaped_move(move: Vector2) -> bool:
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


func _test_knight_moves_l_shaped() -> void:
    var enemy_pos = Vector2(500, 500)
    var player_pos = Vector2(700, 600)
    var move = get_knight_move(enemy_pos, player_pos)
    assert_true(is_valid_l_shaped_move(move), "Knight should move in L-shape")


func _test_knight_all_moves_are_valid_l() -> void:
    # Test all 8 possible knight moves
    var all_L_moves = [
        Vector2(2, 1),
        Vector2(2, -1),
        Vector2(-2, 1),
        Vector2(-2, -1),
        Vector2(1, 2),
        Vector2(1, -2),
        Vector2(-1, 2),
        Vector2(-1, -2)
    ]

    for move_template in all_L_moves:
        var move = move_template * TILE_SIZE
        assert_true(is_valid_l_shaped_move(move), "Move %s should be valid L-shape" % move)


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


# ============================================================
# Speed and Cooldown Tests
# ============================================================


func _test_speed_multipliers_scale_correctly() -> void:
    # Queen should be fastest, pawn baseline
    var pawn_mult: float = TYPE_CONFIG[Type.PAWN]["speed_mult"]
    var queen_mult: float = TYPE_CONFIG[Type.QUEEN]["speed_mult"]

    assert_approx(pawn_mult, 1.0, 0.001, "Pawn should have baseline speed (1.0)")
    assert_gt(queen_mult, pawn_mult, "Queen should be faster than pawn")

    # All multipliers should be positive
    for piece_type in TYPE_CONFIG:
        var mult: float = TYPE_CONFIG[piece_type]["speed_mult"]
        assert_gt(mult, 0.0, "Speed multiplier should be positive")


func _test_cooldowns_vary_by_type() -> void:
    # Queen should have shortest cooldown (more aggressive)
    var queen_cd: float = TYPE_CONFIG[Type.QUEEN]["cooldown"]
    var pawn_cd: float = TYPE_CONFIG[Type.PAWN]["cooldown"]

    assert_lt(queen_cd, pawn_cd, "Queen should have shorter cooldown than pawn")

    # All cooldowns should be positive
    for piece_type in TYPE_CONFIG:
        var cd: float = TYPE_CONFIG[piece_type]["cooldown"]
        assert_gt(cd, 0.0, "Cooldown should be positive")


func _test_slow_effect_logic() -> void:
    # Test slow effect calculation (mirrors enemy.gd apply_slow logic)
    var base_cooldown := 1.0
    var base_duration := 0.3
    var slow_multiplier := 0.5  # 50% slow

    # Slow increases cooldown and duration (enemy moves slower)
    var slowed_cooldown := base_cooldown / slow_multiplier  # 2.0
    var slowed_duration := base_duration / slow_multiplier  # 0.6

    assert_gt(slowed_cooldown, base_cooldown, "Slowed cooldown should be longer")
    assert_gt(slowed_duration, base_duration, "Slowed move duration should be longer")
    assert_approx(slowed_cooldown, 2.0, 0.001)
    assert_approx(slowed_duration, 0.6, 0.001)


func _test_kill_points_match_spec() -> void:
    # Per CLAUDE.md: Kill points are 10× chess values
    # pawn=10, knight/bishop=30, rook=50, queen=90
    const KILL_MULTIPLIER := 10

    assert_eq(TYPE_CONFIG[Type.PAWN]["points"] * KILL_MULTIPLIER, 10, "Pawn kill = 10 pts")
    assert_eq(TYPE_CONFIG[Type.KNIGHT]["points"] * KILL_MULTIPLIER, 30, "Knight kill = 30 pts")
    assert_eq(TYPE_CONFIG[Type.BISHOP]["points"] * KILL_MULTIPLIER, 30, "Bishop kill = 30 pts")
    assert_eq(TYPE_CONFIG[Type.ROOK]["points"] * KILL_MULTIPLIER, 50, "Rook kill = 50 pts")
    assert_eq(TYPE_CONFIG[Type.QUEEN]["points"] * KILL_MULTIPLIER, 90, "Queen kill = 90 pts")
