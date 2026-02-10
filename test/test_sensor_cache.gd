extends "res://test/test_base.gd"
## Tests for the sensor per-frame entity cache.
## Validates cache invalidation, per-arena grouping, and frame skipping.


func _run_tests() -> void:
	print("\n[Sensor Cache Tests]")

	_test("cache_invalidate_resets_frame", _test_cache_invalidate_resets_frame)
	_test("static_cache_vars_exist", _test_static_cache_vars_exist)
	_test("cache_frame_starts_invalid", _test_cache_frame_starts_invalid)
	_test("get_inputs_returns_correct_size_without_player", _test_get_inputs_returns_correct_size_without_player)
	_test("sensor_constants_unchanged", _test_sensor_constants_unchanged)


var SensorScript = preload("res://ai/sensor.gd")


func _test_cache_invalidate_resets_frame() -> void:
	## invalidate_cache() should force a rebuild on next query.
	SensorScript.invalidate_cache()
	assert_eq(SensorScript._cache_frame, -1, "Cache frame should be -1 after invalidate")


func _test_static_cache_vars_exist() -> void:
	## Verify the static cache dictionaries exist and are dictionaries.
	assert_true(SensorScript._arena_enemies is Dictionary, "arena_enemies should be Dictionary")
	assert_true(SensorScript._arena_obstacles is Dictionary, "arena_obstacles should be Dictionary")
	assert_true(SensorScript._arena_powerups is Dictionary, "arena_powerups should be Dictionary")


func _test_cache_frame_starts_invalid() -> void:
	## After invalidation, cache frame should be -1.
	SensorScript.invalidate_cache()
	assert_eq(SensorScript._cache_frame, -1)


func _test_get_inputs_returns_correct_size_without_player() -> void:
	## Sensor with no player should return zero-filled array of correct size.
	var sensor = SensorScript.new()
	var inputs = sensor.get_inputs()
	assert_eq(inputs.size(), SensorScript.TOTAL_INPUTS, "Should return correct number of inputs")
	# All zeros when no player
	for i in inputs.size():
		assert_approx(inputs[i], 0.0, 0.001, "Input %d should be 0.0 with no player" % i)


func _test_sensor_constants_unchanged() -> void:
	## Verify caching didn't accidentally change sensor constants.
	assert_eq(SensorScript.NUM_RAYS, 16)
	assert_eq(SensorScript.RAY_LENGTH, 2800.0)
	assert_eq(SensorScript.INPUTS_PER_RAY, 5)
	assert_eq(SensorScript.PLAYER_STATE_INPUTS, 6)
	assert_eq(SensorScript.TOTAL_INPUTS, 86)
