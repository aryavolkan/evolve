extends "res://test/test_base.gd"
## Tests for AI controller logic.
## Tests action mapping from network outputs without requiring scene instantiation.

# Constants from ai_controller.gd
const OUT_MOVE_X := 0
const OUT_MOVE_Y := 1
const OUT_SHOOT_UP := 2
const OUT_SHOOT_DOWN := 3
const OUT_SHOOT_LEFT := 4
const OUT_SHOOT_RIGHT := 5

const SHOOT_THRESHOLD := 0.0
const MOVE_DEADZONE := 0.05


func _run_tests() -> void:
    print("\n[AI Controller Tests]")

    _test("movement_from_outputs", _test_movement_from_outputs)
    _test("movement_normalized_when_exceeds_one", _test_movement_normalized_when_exceeds_one)
    _test("movement_zero_in_deadzone", _test_movement_zero_in_deadzone)
    _test("shoot_direction_picks_strongest", _test_shoot_direction_picks_strongest)
    _test("shoot_direction_up", _test_shoot_direction_up)
    _test("shoot_direction_down", _test_shoot_direction_down)
    _test("shoot_direction_left", _test_shoot_direction_left)
    _test("shoot_direction_right", _test_shoot_direction_right)
    _test("no_shoot_when_all_below_threshold", _test_no_shoot_when_all_below_threshold)
    _test("action_structure", _test_action_structure)


# ============================================================
# Helper function mirroring ai_controller.gd logic
# ============================================================


func get_action_from_outputs(outputs: PackedFloat32Array) -> Dictionary:
    # Movement direction (direct mapping from network outputs)
    var move_dir := Vector2(outputs[OUT_MOVE_X], outputs[OUT_MOVE_Y])
    if move_dir.length() < MOVE_DEADZONE:
        move_dir = Vector2.ZERO
    elif move_dir.length() > 1.0:
        move_dir = move_dir.normalized()

    # Shooting direction (pick strongest above threshold)
    var shoot_dir := Vector2.ZERO
    var shoot_outputs := [
        {"dir": Vector2.UP, "val": outputs[OUT_SHOOT_UP]},
        {"dir": Vector2.DOWN, "val": outputs[OUT_SHOOT_DOWN]},
        {"dir": Vector2.LEFT, "val": outputs[OUT_SHOOT_LEFT]},
        {"dir": Vector2.RIGHT, "val": outputs[OUT_SHOOT_RIGHT]}
    ]

    var best_shoot := SHOOT_THRESHOLD
    for s in shoot_outputs:
        if s.val > best_shoot:
            best_shoot = s.val
            shoot_dir = s.dir

    return {"move_direction": move_dir, "shoot_direction": shoot_dir}


func make_outputs(
    move_x: float,
    move_y: float,
    shoot_up: float,
    shoot_down: float,
    shoot_left: float,
    shoot_right: float
) -> PackedFloat32Array:
    var outputs := PackedFloat32Array()
    outputs.resize(6)
    outputs[OUT_MOVE_X] = move_x
    outputs[OUT_MOVE_Y] = move_y
    outputs[OUT_SHOOT_UP] = shoot_up
    outputs[OUT_SHOOT_DOWN] = shoot_down
    outputs[OUT_SHOOT_LEFT] = shoot_left
    outputs[OUT_SHOOT_RIGHT] = shoot_right
    return outputs


# ============================================================
# Movement Tests
# ============================================================


func _test_movement_from_outputs() -> void:
    var outputs = make_outputs(0.5, -0.3, 0.0, 0.0, 0.0, 0.0)
    var action = get_action_from_outputs(outputs)

    assert_approx(action.move_direction.x, 0.5, 0.001, "Move X should be 0.5")
    assert_approx(action.move_direction.y, -0.3, 0.001, "Move Y should be -0.3")


func _test_movement_normalized_when_exceeds_one() -> void:
    # Vector (0.9, 0.9) has length ~1.27, should be normalized
    var outputs = make_outputs(0.9, 0.9, 0.0, 0.0, 0.0, 0.0)
    var action = get_action_from_outputs(outputs)

    var length = action.move_direction.length()
    assert_approx(length, 1.0, 0.001, "Movement should be normalized to length 1")


func _test_movement_zero_in_deadzone() -> void:
    # Very small movement should be zeroed out
    var outputs = make_outputs(0.01, 0.02, 0.0, 0.0, 0.0, 0.0)
    var action = get_action_from_outputs(outputs)

    assert_eq(action.move_direction, Vector2.ZERO, "Movement in deadzone should be zero")


# ============================================================
# Shooting Tests
# ============================================================


func _test_shoot_direction_picks_strongest() -> void:
    # Right has highest value
    var outputs = make_outputs(0.0, 0.0, 0.2, 0.3, 0.1, 0.8)
    var action = get_action_from_outputs(outputs)

    assert_eq(action.shoot_direction, Vector2.RIGHT, "Should pick strongest direction (right)")


func _test_shoot_direction_up() -> void:
    var outputs = make_outputs(0.0, 0.0, 0.9, -0.5, -0.5, -0.5)
    var action = get_action_from_outputs(outputs)

    assert_eq(action.shoot_direction, Vector2.UP, "Should shoot up")


func _test_shoot_direction_down() -> void:
    var outputs = make_outputs(0.0, 0.0, -0.5, 0.9, -0.5, -0.5)
    var action = get_action_from_outputs(outputs)

    assert_eq(action.shoot_direction, Vector2.DOWN, "Should shoot down")


func _test_shoot_direction_left() -> void:
    var outputs = make_outputs(0.0, 0.0, -0.5, -0.5, 0.9, -0.5)
    var action = get_action_from_outputs(outputs)

    assert_eq(action.shoot_direction, Vector2.LEFT, "Should shoot left")


func _test_shoot_direction_right() -> void:
    var outputs = make_outputs(0.0, 0.0, -0.5, -0.5, -0.5, 0.9)
    var action = get_action_from_outputs(outputs)

    assert_eq(action.shoot_direction, Vector2.RIGHT, "Should shoot right")


func _test_no_shoot_when_all_below_threshold() -> void:
    # All shoot outputs are at or below threshold (0.0)
    var outputs = make_outputs(0.5, 0.5, -0.5, -0.3, -0.8, 0.0)
    var action = get_action_from_outputs(outputs)

    assert_eq(action.shoot_direction, Vector2.ZERO, "Should not shoot when all below threshold")


# ============================================================
# Structure Tests
# ============================================================


func _test_action_structure() -> void:
    var outputs = make_outputs(0.1, 0.2, 0.3, 0.4, 0.5, 0.6)
    var action = get_action_from_outputs(outputs)

    assert_true(action.has("move_direction"), "Action should have move_direction")
    assert_true(action.has("shoot_direction"), "Action should have shoot_direction")
    assert_true(action.move_direction is Vector2, "move_direction should be Vector2")
    assert_true(action.shoot_direction is Vector2, "shoot_direction should be Vector2")
