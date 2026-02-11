extends "res://test/test_base.gd"
## Tests for enemy AI sensor logic.
## Tests the pure computation functions without requiring scene instantiation.

var EnemySensorScript = preload("res://ai/enemy_sensor.gd")

const TOTAL_INPUTS: int = 16
const ARENA_SIZE: float = 3840.0
const WALL_MARGIN: float = 40.0
var bounds: Rect2 = Rect2(WALL_MARGIN, WALL_MARGIN, ARENA_SIZE - 2 * WALL_MARGIN, ARENA_SIZE - 2 * WALL_MARGIN)


func _run_tests() -> void:
	print("\n[Enemy Sensor Tests]")

	_test("total_inputs_is_16", _test_total_inputs_is_16)
	_test("player_direction_encoding", _test_player_direction_encoding)
	_test("player_distance_encoding", _test_player_distance_encoding)
	_test("player_at_same_position", _test_player_at_same_position)
	_test("wall_distances_from_center", _test_wall_distances_from_center)
	_test("wall_distances_near_corner", _test_wall_distances_near_corner)
	_test("type_encoding_all_types", _test_type_encoding_all_types)
	_test("player_velocity_encoding", _test_player_velocity_encoding)
	_test("player_powerup_flags", _test_player_powerup_flags)
	_test("obstacle_directions", _test_obstacle_directions)
	_test("no_obstacles_returns_zeros", _test_no_obstacles_returns_zeros)
	_test("output_size_always_16", _test_output_size_always_16)


# ============================================================
# Helpers
# ============================================================

func _make_sensor():
	return EnemySensorScript.new()


func _compute(
	enemy_pos: Vector2,
	enemy_type: int = 0,
	player_pos: Vector2 = Vector2(1920, 1920),
	player_velocity: Vector2 = Vector2.ZERO,
	player_invincible: bool = false,
	player_speed_boosted: bool = false,
	player_slow_active: bool = false,
	obstacle_positions: Array = [],
	p_bounds: Rect2 = Rect2()
) -> PackedFloat32Array:
	var sensor = _make_sensor()
	if p_bounds == Rect2():
		p_bounds = bounds
	return sensor.compute_inputs(
		enemy_pos, enemy_type, player_pos, player_velocity,
		player_invincible, player_speed_boosted, player_slow_active,
		obstacle_positions, p_bounds
	)


# ============================================================
# Tests
# ============================================================

func _test_total_inputs_is_16() -> void:
	var sensor = _make_sensor()
	assert_eq(sensor.TOTAL_INPUTS, 16, "Enemy sensor should have 16 inputs")


func _test_player_direction_encoding() -> void:
	# Enemy at center, player to the right
	var enemy_pos := Vector2(1920, 1920)
	var player_pos := Vector2(2920, 1920)  # 1000px to the right
	var inputs := _compute(enemy_pos, 0, player_pos)

	# Player direction inputs (indices 0-1)
	# Direction should be positive x, zero y
	assert_gt(inputs[0], 0.0, "Player x direction should be positive (right)")
	assert_approx(inputs[1], 0.0, 0.01, "Player y direction should be ~0")


func _test_player_distance_encoding() -> void:
	var enemy_pos := Vector2(1920, 1920)

	# Close player: higher magnitude
	var close_inputs := _compute(enemy_pos, 0, Vector2(2020, 1920))  # 100px away
	# Far player: lower magnitude
	var far_inputs := _compute(enemy_pos, 0, Vector2(3820, 1920))  # 1900px away

	var close_magnitude := Vector2(close_inputs[0], close_inputs[1]).length()
	var far_magnitude := Vector2(far_inputs[0], far_inputs[1]).length()

	assert_gt(close_magnitude, far_magnitude, "Close player should have higher magnitude")


func _test_player_at_same_position() -> void:
	var pos := Vector2(1920, 1920)
	var inputs := _compute(pos, 0, pos)

	# When player is at same position, direction should be zero
	assert_approx(inputs[0], 0.0, 0.001, "Direction x should be 0 when overlapping")
	assert_approx(inputs[1], 0.0, 0.001, "Direction y should be 0 when overlapping")


func _test_wall_distances_from_center() -> void:
	var center := Vector2(1920, 1920)
	var inputs := _compute(center)

	# Wall distance inputs are at indices 6-9 (after 2 player + 4 obstacle)
	# From center, all wall distances should be roughly equal (~0.49)
	var expected := (1920.0 - WALL_MARGIN) / ARENA_SIZE

	assert_approx(inputs[6], expected, 0.01, "North wall distance from center")
	assert_approx(inputs[7], expected, 0.01, "East wall distance from center")
	assert_approx(inputs[8], expected, 0.01, "South wall distance from center")
	assert_approx(inputs[9], expected, 0.01, "West wall distance from center")


func _test_wall_distances_near_corner() -> void:
	# Near top-left corner
	var pos := Vector2(100, 100)
	var inputs := _compute(pos)

	# North and West walls should be very close (small values)
	assert_lt(inputs[6], 0.05, "North wall should be very close")
	assert_lt(inputs[9], 0.05, "West wall should be very close")

	# South and East walls should be far (large values)
	assert_gt(inputs[7], 0.9, "East wall should be far")
	assert_gt(inputs[8], 0.9, "South wall should be far")


func _test_type_encoding_all_types() -> void:
	var pos := Vector2(1920, 1920)

	# PAWN=0 → 0.2, KNIGHT=1 → 0.4, BISHOP=2 → 0.6, ROOK=3 → 0.8, QUEEN=4 → 1.0
	# Type encoding is at index 10
	var pawn_inputs := _compute(pos, 0)
	var knight_inputs := _compute(pos, 1)
	var bishop_inputs := _compute(pos, 2)
	var rook_inputs := _compute(pos, 3)
	var queen_inputs := _compute(pos, 4)

	assert_approx(pawn_inputs[10], 0.2, 0.001, "Pawn type encoding")
	assert_approx(knight_inputs[10], 0.4, 0.001, "Knight type encoding")
	assert_approx(bishop_inputs[10], 0.6, 0.001, "Bishop type encoding")
	assert_approx(rook_inputs[10], 0.8, 0.001, "Rook type encoding")
	assert_approx(queen_inputs[10], 1.0, 0.001, "Queen type encoding")


func _test_player_velocity_encoding() -> void:
	var pos := Vector2(1920, 1920)
	# Player velocity inputs at indices 11-12
	var inputs := _compute(pos, 0, Vector2(2000, 2000), Vector2(250, -500))

	# vx=250 / 500 = 0.5, vy=-500 / 500 = -1.0
	assert_approx(inputs[11], 0.5, 0.01, "Player velocity x")
	assert_approx(inputs[12], -1.0, 0.01, "Player velocity y")


func _test_player_powerup_flags() -> void:
	var pos := Vector2(1920, 1920)
	# Power-up flags at indices 13-15

	var no_powerups := _compute(pos, 0, Vector2(2000, 2000), Vector2.ZERO, false, false, false)
	assert_approx(no_powerups[13], 0.0, 0.001, "No invincibility")
	assert_approx(no_powerups[14], 0.0, 0.001, "No speed boost")
	assert_approx(no_powerups[15], 0.0, 0.001, "No slow active")

	var all_powerups := _compute(pos, 0, Vector2(2000, 2000), Vector2.ZERO, true, true, true)
	assert_approx(all_powerups[13], 1.0, 0.001, "Invincibility active")
	assert_approx(all_powerups[14], 1.0, 0.001, "Speed boost active")
	assert_approx(all_powerups[15], 1.0, 0.001, "Slow active")


func _test_obstacle_directions() -> void:
	var enemy_pos := Vector2(1920, 1920)
	# Place one obstacle to the right
	var obstacles := [Vector2(2120, 1920)]  # 200px to the right
	var inputs := _compute(enemy_pos, 0, Vector2(3000, 3000), Vector2.ZERO, false, false, false, obstacles)

	# Nearest obstacle inputs at indices 2-5
	# First obstacle: direction (1, 0) × proximity
	assert_gt(inputs[2], 0.0, "Obstacle 1 x direction should be positive (right)")
	assert_approx(inputs[3], 0.0, 0.01, "Obstacle 1 y direction should be ~0")

	# Second obstacle doesn't exist: should be 0
	assert_approx(inputs[4], 0.0, 0.001, "No second obstacle x")
	assert_approx(inputs[5], 0.0, 0.001, "No second obstacle y")


func _test_no_obstacles_returns_zeros() -> void:
	var inputs := _compute(Vector2(1920, 1920), 0, Vector2(2000, 2000), Vector2.ZERO, false, false, false, [])

	# Indices 2-5 should all be 0
	assert_approx(inputs[2], 0.0, 0.001, "No obstacle 1 x")
	assert_approx(inputs[3], 0.0, 0.001, "No obstacle 1 y")
	assert_approx(inputs[4], 0.0, 0.001, "No obstacle 2 x")
	assert_approx(inputs[5], 0.0, 0.001, "No obstacle 2 y")


func _test_output_size_always_16() -> void:
	# Various states should all produce exactly 16 inputs
	var inputs1 := _compute(Vector2(100, 100), 0)
	var inputs2 := _compute(Vector2(3000, 3000), 4, Vector2(100, 100), Vector2(500, 500), true, true, true, [Vector2(500, 500), Vector2(1000, 1000), Vector2(2000, 2000)])

	assert_eq(inputs1.size(), 16, "Output should always be 16 floats")
	assert_eq(inputs2.size(), 16, "Output should always be 16 floats")
