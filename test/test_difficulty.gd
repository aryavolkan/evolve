extends "res://test/test_base.gd"
## Tests for difficulty scaling in main.gd
## These test the pure calculation functions without requiring scene instantiation.

# Constants from main.gd
const BASE_ENEMY_SPEED: float = 150.0
const MAX_ENEMY_SPEED: float = 300.0
const BASE_SPAWN_INTERVAL: float = 50.0
const MIN_SPAWN_INTERVAL: float = 20.0
const DIFFICULTY_SCALE_SCORE: float = 500.0


func run_tests() -> void:
    print("\n[Difficulty Scaling Tests]")

    _test("difficulty_factor_at_zero_score", _test_difficulty_factor_at_zero_score)
    _test("difficulty_factor_at_mid_score", _test_difficulty_factor_at_mid_score)
    _test("difficulty_factor_at_max_score", _test_difficulty_factor_at_max_score)
    _test("difficulty_factor_capped_above_max", _test_difficulty_factor_capped_above_max)
    _test("enemy_speed_at_zero_score", _test_enemy_speed_at_zero_score)
    _test("enemy_speed_at_max_score", _test_enemy_speed_at_max_score)
    _test("enemy_speed_at_mid_score", _test_enemy_speed_at_mid_score)
    _test("spawn_interval_at_zero_score", _test_spawn_interval_at_zero_score)
    _test("spawn_interval_at_max_score", _test_spawn_interval_at_max_score)
    _test("spawn_interval_at_mid_score", _test_spawn_interval_at_mid_score)
    _test("scaling_is_linear", _test_scaling_is_linear)


# Helper functions that mirror main.gd logic
func get_difficulty_factor(score: float) -> float:
    return clampf(score / DIFFICULTY_SCALE_SCORE, 0.0, 1.0)


func get_scaled_enemy_speed(score: float) -> float:
    var factor = get_difficulty_factor(score)
    return lerpf(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, factor)


func get_scaled_spawn_interval(score: float) -> float:
    var factor = get_difficulty_factor(score)
    return lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, factor)


# ============================================================
# Difficulty Factor Tests
# ============================================================


func _test_difficulty_factor_at_zero_score() -> void:
    assert_approx(get_difficulty_factor(0.0), 0.0, 0.001, "Factor at score 0 should be 0")


func _test_difficulty_factor_at_mid_score() -> void:
    # At score 250, factor should be 0.5
    assert_approx(get_difficulty_factor(250.0), 0.5, 0.001, "Factor at score 250 should be 0.5")


func _test_difficulty_factor_at_max_score() -> void:
    # At score 500, factor should be 1.0
    assert_approx(get_difficulty_factor(500.0), 1.0, 0.001, "Factor at score 500 should be 1.0")


func _test_difficulty_factor_capped_above_max() -> void:
    # Above 500, factor should still be 1.0 (capped)
    assert_approx(
        get_difficulty_factor(1000.0), 1.0, 0.001, "Factor above 500 should be capped at 1.0"
    )
    assert_approx(
        get_difficulty_factor(9999.0),
        1.0,
        0.001,
        "Factor at very high score should be capped at 1.0"
    )


# ============================================================
# Enemy Speed Tests
# ============================================================


func _test_enemy_speed_at_zero_score() -> void:
    assert_approx(
        get_scaled_enemy_speed(0.0),
        BASE_ENEMY_SPEED,
        0.001,
        "Speed at score 0 should be base speed (150)"
    )


func _test_enemy_speed_at_max_score() -> void:
    assert_approx(
        get_scaled_enemy_speed(500.0),
        MAX_ENEMY_SPEED,
        0.001,
        "Speed at score 500 should be max speed (300)"
    )


func _test_enemy_speed_at_mid_score() -> void:
    # At score 250, speed should be halfway between 150 and 300 = 225
    var expected = (BASE_ENEMY_SPEED + MAX_ENEMY_SPEED) / 2.0  # 225
    assert_approx(
        get_scaled_enemy_speed(250.0), expected, 0.001, "Speed at score 250 should be 225"
    )


# ============================================================
# Spawn Interval Tests
# ============================================================


func _test_spawn_interval_at_zero_score() -> void:
    assert_approx(
        get_scaled_spawn_interval(0.0),
        BASE_SPAWN_INTERVAL,
        0.001,
        "Interval at score 0 should be base interval (50)"
    )


func _test_spawn_interval_at_max_score() -> void:
    assert_approx(
        get_scaled_spawn_interval(500.0),
        MIN_SPAWN_INTERVAL,
        0.001,
        "Interval at score 500 should be min interval (20)"
    )


func _test_spawn_interval_at_mid_score() -> void:
    # At score 250, interval should be halfway between 50 and 20 = 35
    var expected = (BASE_SPAWN_INTERVAL + MIN_SPAWN_INTERVAL) / 2.0  # 35
    assert_approx(
        get_scaled_spawn_interval(250.0), expected, 0.001, "Interval at score 250 should be 35"
    )


# ============================================================
# Linear Scaling Tests
# ============================================================


func _test_scaling_is_linear() -> void:
    # Test that scaling increases linearly
    var prev_factor := 0.0
    var prev_speed := BASE_ENEMY_SPEED

    for score_step in [100, 200, 300, 400, 500]:
        var factor = get_difficulty_factor(float(score_step))
        var speed = get_scaled_enemy_speed(float(score_step))

        # Factor should increase by 0.2 each step (100/500)
        assert_gt(factor, prev_factor, "Factor should increase with score")

        # Speed should increase with score
        assert_gt(speed, prev_speed, "Speed should increase with score")

        prev_factor = factor
        prev_speed = speed

    # Check linearity: speed difference between each step should be constant
    var speed_100 = get_scaled_enemy_speed(100.0)
    var speed_200 = get_scaled_enemy_speed(200.0)
    var speed_300 = get_scaled_enemy_speed(300.0)

    var diff_1 = speed_200 - speed_100
    var diff_2 = speed_300 - speed_200

    assert_approx(diff_1, diff_2, 0.001, "Speed increase should be linear (constant difference)")
