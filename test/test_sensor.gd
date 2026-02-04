extends "res://test/test_base.gd"
## Tests for AI sensor logic.
## Tests the pure calculation functions without requiring scene instantiation.

# Constants from sensor.gd
const NUM_RAYS: int = 16
const RAY_LENGTH: float = 1500.0
const INPUTS_PER_RAY: int = 5
const PLAYER_STATE_INPUTS: int = 6
const TOTAL_INPUTS: int = NUM_RAYS * INPUTS_PER_RAY + PLAYER_STATE_INPUTS

const ARENA_WIDTH: float = 2560.0
const ARENA_HEIGHT: float = 1440.0
var arena_bounds: Rect2 = Rect2(40, 40, ARENA_WIDTH - 80, ARENA_HEIGHT - 80)


func _run_tests() -> void:
	print("\n[Sensor Tests]")

	_test("total_inputs_count_is_correct", _test_total_inputs_count_is_correct)
	_test("ray_angles_evenly_distributed", _test_ray_angles_evenly_distributed)
	_test("wall_distance_right", _test_wall_distance_right)
	_test("wall_distance_left", _test_wall_distance_left)
	_test("wall_distance_up", _test_wall_distance_up)
	_test("wall_distance_down", _test_wall_distance_down)
	_test("wall_distance_diagonal", _test_wall_distance_diagonal)
	_test("wall_distance_from_center", _test_wall_distance_from_center)
	_test("ray_cast_empty_returns_no_hit", _test_ray_cast_empty_returns_no_hit)
	_test("ray_cast_detects_entity_in_front", _test_ray_cast_detects_entity_in_front)
	_test("ray_cast_ignores_entity_behind", _test_ray_cast_ignores_entity_behind)
	_test("ray_cast_ignores_entity_too_far_from_ray", _test_ray_cast_ignores_entity_too_far_from_ray)
	_test("enemy_type_encoding", _test_enemy_type_encoding)


# ============================================================
# Helper functions mirroring sensor.gd logic
# ============================================================

func get_wall_distance(origin: Vector2, direction: Vector2) -> float:
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


# Mock entity class for testing
class MockEntity extends RefCounted:
	var global_position: Vector2
	var point_value: int

	func _init(pos: Vector2, points: int = 1) -> void:
		global_position = pos
		point_value = points

	func get_point_value() -> int:
		return point_value


func cast_ray_to_entities(origin: Vector2, direction: Vector2, entities: Array, hit_radius: float) -> Dictionary:
	var result := {"hit": false, "distance": RAY_LENGTH, "type_value": 0.0}

	for entity in entities:
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


# ============================================================
# Input Count Tests
# ============================================================

func _test_total_inputs_count_is_correct() -> void:
	var expected = 16 * 5 + 6  # 16 rays × 5 values + 6 player state = 86
	assert_eq(TOTAL_INPUTS, 86, "Total inputs should be 86")
	assert_eq(TOTAL_INPUTS, expected)


func _test_ray_angles_evenly_distributed() -> void:
	var ray_angles := PackedFloat32Array()
	ray_angles.resize(NUM_RAYS)
	for i in NUM_RAYS:
		ray_angles[i] = (float(i) / NUM_RAYS) * TAU

	# Check angles are evenly spaced
	var expected_spacing = TAU / NUM_RAYS
	for i in range(1, NUM_RAYS):
		var spacing = ray_angles[i] - ray_angles[i - 1]
		assert_approx(spacing, expected_spacing, 0.001, "Ray spacing should be even")

	# First ray should be at 0 radians (pointing right)
	assert_approx(ray_angles[0], 0.0, 0.001, "First ray should point right")

	# Ray at index 4 should be at 90 degrees (pointing down, since Y is down in Godot)
	assert_approx(ray_angles[4], PI / 2, 0.001, "Ray 4 should point down")


# ============================================================
# Wall Distance Tests
# ============================================================

func _test_wall_distance_right() -> void:
	var origin = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)  # Center of arena
	var direction = Vector2(1, 0)  # Right
	var dist = get_wall_distance(origin, direction)

	# From center to right wall
	var expected = arena_bounds.end.x - origin.x
	assert_approx(dist, expected, 1.0, "Distance to right wall")


func _test_wall_distance_left() -> void:
	var origin = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)
	var direction = Vector2(-1, 0)  # Left
	var dist = get_wall_distance(origin, direction)

	var expected = origin.x - arena_bounds.position.x
	assert_approx(dist, expected, 1.0, "Distance to left wall")


func _test_wall_distance_up() -> void:
	var origin = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)
	var direction = Vector2(0, -1)  # Up
	var dist = get_wall_distance(origin, direction)

	var expected = origin.y - arena_bounds.position.y
	assert_approx(dist, expected, 1.0, "Distance to top wall")


func _test_wall_distance_down() -> void:
	var origin = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)
	var direction = Vector2(0, 1)  # Down
	var dist = get_wall_distance(origin, direction)

	var expected = arena_bounds.end.y - origin.y
	assert_approx(dist, expected, 1.0, "Distance to bottom wall")


func _test_wall_distance_diagonal() -> void:
	var origin = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)
	var direction = Vector2(1, 1).normalized()  # Diagonal down-right
	var dist = get_wall_distance(origin, direction)

	# Should hit whichever wall is closer diagonally
	assert_gt(dist, 0.0, "Diagonal distance should be positive")
	assert_lt(dist, RAY_LENGTH, "Diagonal distance should be less than ray length")


func _test_wall_distance_from_center() -> void:
	var center = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)

	# From center, distance to each wall should be roughly half the arena dimension
	var dist_right = get_wall_distance(center, Vector2(1, 0))
	var dist_left = get_wall_distance(center, Vector2(-1, 0))
	var dist_down = get_wall_distance(center, Vector2(0, 1))
	var dist_up = get_wall_distance(center, Vector2(0, -1))

	# Arena is 2560x1440, with 40px walls, playable area is roughly centered
	assert_gt(dist_right, 1000.0, "Right wall should be > 1000 from center")
	assert_gt(dist_left, 1000.0, "Left wall should be > 1000 from center")
	assert_gt(dist_down, 500.0, "Bottom wall should be > 500 from center")
	assert_gt(dist_up, 500.0, "Top wall should be > 500 from center")


# ============================================================
# Ray Casting Tests
# ============================================================

func _test_ray_cast_empty_returns_no_hit() -> void:
	var origin = Vector2(500, 500)
	var direction = Vector2(1, 0)
	var entities: Array = []

	var result = cast_ray_to_entities(origin, direction, entities, 50.0)
	assert_false(result.hit, "Empty entity list should return no hit")
	assert_eq(result.distance, RAY_LENGTH, "Distance should be max when no hit")


func _test_ray_cast_detects_entity_in_front() -> void:
	var origin = Vector2(500, 500)
	var direction = Vector2(1, 0)  # Looking right
	var entity = MockEntity.new(Vector2(700, 500), 1)  # 200 units to the right
	var entities: Array = [entity]

	var result = cast_ray_to_entities(origin, direction, entities, 50.0)
	assert_true(result.hit, "Should detect entity in front")
	assert_approx(result.distance, 200.0, 1.0, "Distance should be ~200")


func _test_ray_cast_ignores_entity_behind() -> void:
	var origin = Vector2(500, 500)
	var direction = Vector2(1, 0)  # Looking right
	var entity = MockEntity.new(Vector2(300, 500), 1)  # 200 units to the LEFT (behind)
	var entities: Array = [entity]

	var result = cast_ray_to_entities(origin, direction, entities, 50.0)
	assert_false(result.hit, "Should not detect entity behind")


func _test_ray_cast_ignores_entity_too_far_from_ray() -> void:
	var origin = Vector2(500, 500)
	var direction = Vector2(1, 0)  # Looking right
	var entity = MockEntity.new(Vector2(700, 700), 1)  # 200 units right, 200 units down
	var entities: Array = [entity]

	var result = cast_ray_to_entities(origin, direction, entities, 50.0)
	assert_false(result.hit, "Should not detect entity too far from ray path")


# ============================================================
# Enemy Type Encoding Tests
# ============================================================

func _test_enemy_type_encoding() -> void:
	var origin = Vector2(500, 500)
	var direction = Vector2(1, 0)

	# Test pawn (1 point = 0.2)
	var pawn = MockEntity.new(Vector2(600, 500), 1)
	var result = cast_ray_to_entities(origin, direction, [pawn], 50.0)
	assert_approx(result.type_value, 0.2, 0.001, "Pawn should encode as 0.2")

	# Test knight/bishop (3 points = 0.5)
	var knight = MockEntity.new(Vector2(600, 500), 3)
	result = cast_ray_to_entities(origin, direction, [knight], 50.0)
	assert_approx(result.type_value, 0.5, 0.001, "Knight/Bishop should encode as 0.5")

	# Test rook (5 points = 0.8)
	var rook = MockEntity.new(Vector2(600, 500), 5)
	result = cast_ray_to_entities(origin, direction, [rook], 50.0)
	assert_approx(result.type_value, 0.8, 0.001, "Rook should encode as 0.8")

	# Test queen (9 points = 1.0)
	var queen = MockEntity.new(Vector2(600, 500), 9)
	result = cast_ray_to_entities(origin, direction, [queen], 50.0)
	assert_approx(result.type_value, 1.0, 0.001, "Queen should encode as 1.0")
