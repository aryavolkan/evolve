extends "res://test/test_base.gd"
## Tests for enemy AI controller logic.
## Tests move selection from network outputs without requiring scene instantiation.

var EnemyAIControllerScript = preload("res://ai/enemy_ai_controller.gd")

const TILE_SIZE := 50.0
const NUM_OUTPUTS := 8

# Direction indices (from enemy_ai_controller.gd)
const DIR_N := 0
const DIR_NE := 1
const DIR_E := 2
const DIR_SE := 3
const DIR_S := 4
const DIR_SW := 5
const DIR_W := 6
const DIR_NW := 7

# Piece types (from Enemy.Type enum)
const TYPE_PAWN := 0
const TYPE_KNIGHT := 1
const TYPE_BISHOP := 2
const TYPE_ROOK := 3
const TYPE_QUEEN := 4


func _run_tests() -> void:
	print("\n[Enemy AI Controller Tests]")

	_test("pawn_picks_cardinal_only", _test_pawn_picks_cardinal_only)
	_test("pawn_picks_highest_cardinal", _test_pawn_picks_highest_cardinal)
	_test("pawn_ignores_diagonals", _test_pawn_ignores_diagonals)
	_test("knight_returns_l_shaped_move", _test_knight_returns_l_shaped_move)
	_test("knight_move_is_tile_scaled", _test_knight_move_is_tile_scaled)
	_test("bishop_picks_diagonal_only", _test_bishop_picks_diagonal_only)
	_test("bishop_ignores_cardinals", _test_bishop_ignores_cardinals)
	_test("rook_picks_cardinal_only", _test_rook_picks_cardinal_only)
	_test("queen_can_pick_any_direction", _test_queen_can_pick_any_direction)
	_test("move_offset_nonzero", _test_move_offset_nonzero)
	_test("direction_vector_count", _test_direction_vector_count)
	_test("knight_moves_precomputed", _test_knight_moves_precomputed)


# ============================================================
# Helpers
# ============================================================

func _make_controller():
	return EnemyAIControllerScript.new()


func _make_outputs_with_peak(peak_idx: int, peak_val: float = 0.9, base_val: float = -0.5) -> PackedFloat32Array:
	## Create outputs array with one peak direction and low values elsewhere.
	var outputs := PackedFloat32Array()
	outputs.resize(NUM_OUTPUTS)
	outputs.fill(base_val)
	outputs[peak_idx] = peak_val
	return outputs


func _make_seeded_rng(seed_val: int = 42) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	return rng


# ============================================================
# Pawn Tests
# ============================================================

func _test_pawn_picks_cardinal_only() -> void:
	var ctrl = _make_controller()

	# Test each cardinal direction
	for dir_idx in [DIR_N, DIR_E, DIR_S, DIR_W]:
		var outputs := _make_outputs_with_peak(dir_idx)
		var move := ctrl.select_move_from_outputs(outputs, TYPE_PAWN)
		assert_approx(move.length(), TILE_SIZE, 0.01, "Pawn move should be exactly 1 tile")


func _test_pawn_picks_highest_cardinal() -> void:
	var ctrl = _make_controller()

	# South has highest output
	var outputs := PackedFloat32Array()
	outputs.resize(NUM_OUTPUTS)
	outputs[DIR_N] = 0.1
	outputs[DIR_NE] = 0.99  # High diagonal — should be ignored
	outputs[DIR_E] = 0.3
	outputs[DIR_SE] = 0.8  # High diagonal — should be ignored
	outputs[DIR_S] = 0.5   # Highest cardinal
	outputs[DIR_SW] = 0.7  # Diagonal
	outputs[DIR_W] = 0.2
	outputs[DIR_NW] = 0.6  # Diagonal

	var move := ctrl.select_move_from_outputs(outputs, TYPE_PAWN)
	# Should pick South (0, 1) * 50
	assert_approx(move.x, 0.0, 0.01, "Pawn should move south: x=0")
	assert_approx(move.y, TILE_SIZE, 0.01, "Pawn should move south: y=50")


func _test_pawn_ignores_diagonals() -> void:
	var ctrl = _make_controller()

	# All diagonals are very high, but all cardinals are low
	var outputs := PackedFloat32Array()
	outputs.resize(NUM_OUTPUTS)
	outputs[DIR_N] = -0.9
	outputs[DIR_NE] = 0.99
	outputs[DIR_E] = -0.8
	outputs[DIR_SE] = 0.99
	outputs[DIR_S] = -0.7  # Highest cardinal (least negative)
	outputs[DIR_SW] = 0.99
	outputs[DIR_W] = -0.95
	outputs[DIR_NW] = 0.99

	var move := ctrl.select_move_from_outputs(outputs, TYPE_PAWN)
	# Should pick south (highest cardinal = -0.7)
	assert_approx(move.y, TILE_SIZE, 0.01, "Pawn should pick best cardinal despite high diagonals")


# ============================================================
# Knight Tests
# ============================================================

func _test_knight_returns_l_shaped_move() -> void:
	var ctrl = _make_controller()
	var outputs := _make_outputs_with_peak(DIR_NE)
	var move := ctrl.select_move_from_outputs(outputs, TYPE_KNIGHT)

	# Knight moves are L-shaped: one component is 2*TILE, other is 1*TILE
	var ax := absf(move.x) / TILE_SIZE
	var ay := absf(move.y) / TILE_SIZE

	# Should be a valid L-shape: (2,1) or (1,2)
	var is_l_shape := (is_equal_approx(ax, 2.0) and is_equal_approx(ay, 1.0)) or \
					  (is_equal_approx(ax, 1.0) and is_equal_approx(ay, 2.0))
	assert_true(is_l_shape, "Knight move should be L-shaped (2+1 tiles)")


func _test_knight_move_is_tile_scaled() -> void:
	var ctrl = _make_controller()

	# Try all 8 directions
	for dir_idx in NUM_OUTPUTS:
		var outputs := _make_outputs_with_peak(dir_idx)
		var move := ctrl.select_move_from_outputs(outputs, TYPE_KNIGHT)

		# All components should be multiples of TILE_SIZE
		var ax := absf(move.x)
		var ay := absf(move.y)
		var is_tile_multiple_x := is_equal_approx(fmod(ax, TILE_SIZE), 0.0) or is_equal_approx(ax, 0.0)
		var is_tile_multiple_y := is_equal_approx(fmod(ay, TILE_SIZE), 0.0) or is_equal_approx(ay, 0.0)
		assert_true(is_tile_multiple_x, "Knight x should be tile-aligned")
		assert_true(is_tile_multiple_y, "Knight y should be tile-aligned")


# ============================================================
# Bishop Tests
# ============================================================

func _test_bishop_picks_diagonal_only() -> void:
	var ctrl = _make_controller()
	var rng := _make_seeded_rng()

	for dir_idx in [DIR_NE, DIR_SE, DIR_SW, DIR_NW]:
		var outputs := _make_outputs_with_peak(dir_idx)
		var move := ctrl.select_move_from_outputs(outputs, TYPE_BISHOP, rng)

		# Bishop moves diagonally: |x| should equal |y|
		assert_approx(absf(move.x), absf(move.y), 0.01,
			"Bishop move should be diagonal (|x| == |y|)")
		assert_gt(absf(move.x), 0.0, "Bishop move should not be zero")


func _test_bishop_ignores_cardinals() -> void:
	var ctrl = _make_controller()
	var rng := _make_seeded_rng()

	# North (cardinal) is highest, but bishop can't go cardinal
	var outputs := PackedFloat32Array()
	outputs.resize(NUM_OUTPUTS)
	outputs.fill(-1.0)
	outputs[DIR_N] = 0.99   # Highest but illegal for bishop
	outputs[DIR_SE] = -0.5  # Highest legal diagonal

	var move := ctrl.select_move_from_outputs(outputs, TYPE_BISHOP, rng)
	# Should pick SE (diagonal) despite N being higher
	assert_gt(move.x, 0.0, "Bishop should go SE: positive x")
	assert_gt(move.y, 0.0, "Bishop should go SE: positive y")


# ============================================================
# Rook Tests
# ============================================================

func _test_rook_picks_cardinal_only() -> void:
	var ctrl = _make_controller()
	var rng := _make_seeded_rng()

	# SE (diagonal) is highest, but rook can only go cardinal
	var outputs := PackedFloat32Array()
	outputs.resize(NUM_OUTPUTS)
	outputs.fill(-1.0)
	outputs[DIR_SE] = 0.99  # Highest but illegal for rook
	outputs[DIR_E] = 0.3    # Highest legal cardinal

	var move := ctrl.select_move_from_outputs(outputs, TYPE_ROOK, rng)
	# Should pick East
	assert_gt(move.x, 0.0, "Rook should go east: positive x")
	assert_approx(move.y, 0.0, 0.01, "Rook should go east: y=0")


# ============================================================
# Queen Tests
# ============================================================

func _test_queen_can_pick_any_direction() -> void:
	var ctrl = _make_controller()
	var rng := _make_seeded_rng()

	# Test that queen can pick both cardinal and diagonal
	var cardinal_outputs := _make_outputs_with_peak(DIR_N)
	var move_n := ctrl.select_move_from_outputs(cardinal_outputs, TYPE_QUEEN, rng)
	assert_lt(move_n.y, 0.0, "Queen should be able to go north")

	var diagonal_outputs := _make_outputs_with_peak(DIR_SE)
	var move_se := ctrl.select_move_from_outputs(diagonal_outputs, TYPE_QUEEN, rng)
	assert_gt(move_se.x, 0.0, "Queen should be able to go SE: positive x")
	assert_gt(move_se.y, 0.0, "Queen should be able to go SE: positive y")


# ============================================================
# General Tests
# ============================================================

func _test_move_offset_nonzero() -> void:
	var ctrl = _make_controller()
	var rng := _make_seeded_rng()

	# All piece types should produce non-zero moves
	for piece_type in [TYPE_PAWN, TYPE_KNIGHT, TYPE_BISHOP, TYPE_ROOK, TYPE_QUEEN]:
		var outputs := _make_outputs_with_peak(DIR_E)
		var move := ctrl.select_move_from_outputs(outputs, piece_type, rng)
		assert_gt(move.length(), 0.0, "Move should be non-zero for type %d" % piece_type)


func _test_direction_vector_count() -> void:
	var ctrl = _make_controller()
	assert_eq(ctrl._dir_vectors.size(), 8, "Should have 8 direction vectors")


func _test_knight_moves_precomputed() -> void:
	var ctrl = _make_controller()
	assert_eq(ctrl._knight_moves.size(), 8, "Should have 8 pre-computed knight L-moves")

	# Each should have offset and dir_idx
	for move in ctrl._knight_moves:
		assert_true(move.has("offset"), "Knight move should have offset")
		assert_true(move.has("dir_idx"), "Knight move should have dir_idx")
		assert_gte(float(move.dir_idx), 0.0, "dir_idx should be >= 0")
		assert_lt(float(move.dir_idx), 8.0, "dir_idx should be < 8")
