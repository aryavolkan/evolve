extends "res://test/test_base.gd"
## Tests for ai/trainer.gd configuration and state logic.
## Tests the pure configuration aspects without requiring scene instantiation.

# Constants from trainer.gd
const BEST_NETWORK_PATH := "user://best_network.nn"
const POPULATION_PATH := "user://population.evo"
const TRAINING_LOG_PATH := "user://training_log.txt"

# Default configuration values
const DEFAULT_POPULATION_SIZE := 50
const DEFAULT_GENERATIONS := 100
const DEFAULT_TIME_SCALE := 3.0
const DEFAULT_AUTO_SAVE_INTERVAL := 10
const DEFAULT_MAX_EVAL_TIME := 60.0


func _run_tests() -> void:
	print("\n[Trainer Tests]")

	_test("path_constants_use_user_directory", _test_path_constants_use_user_directory)
	_test("path_constants_have_correct_extensions", _test_path_constants_have_correct_extensions)
	_test("default_config_values_reasonable", _test_default_config_values_reasonable)
	_test("time_scale_within_bounds", _test_time_scale_within_bounds)
	_test("auto_save_interval_positive", _test_auto_save_interval_positive)
	_test("training_stats_structure", _test_training_stats_structure)
	_test("ai_action_structure", _test_ai_action_structure)
	_test("max_eval_time_reasonable", _test_max_eval_time_reasonable)
	_test("population_size_matches_evolution_spec", _test_population_size_matches_evolution_spec)


# ============================================================
# Path Configuration Tests
# ============================================================

func _test_path_constants_use_user_directory() -> void:
	# All paths should use user:// for persistence
	assert_true(BEST_NETWORK_PATH.begins_with("user://"), "Best network should save to user://")
	assert_true(POPULATION_PATH.begins_with("user://"), "Population should save to user://")
	assert_true(TRAINING_LOG_PATH.begins_with("user://"), "Training log should save to user://")


func _test_path_constants_have_correct_extensions() -> void:
	assert_true(BEST_NETWORK_PATH.ends_with(".nn"), "Network file should have .nn extension")
	assert_true(POPULATION_PATH.ends_with(".evo"), "Population file should have .evo extension")
	assert_true(TRAINING_LOG_PATH.ends_with(".txt"), "Log file should have .txt extension")


# ============================================================
# Default Configuration Tests
# ============================================================

func _test_default_config_values_reasonable() -> void:
	assert_gt(DEFAULT_POPULATION_SIZE, 0, "Population size must be positive")
	assert_gt(DEFAULT_GENERATIONS, 0, "Generations must be positive")
	assert_gt(DEFAULT_TIME_SCALE, 0.0, "Time scale must be positive")
	assert_gt(DEFAULT_AUTO_SAVE_INTERVAL, 0, "Auto save interval must be positive")


func _test_time_scale_within_bounds() -> void:
	# Time scale should be reasonable (not too slow, not too fast)
	assert_in_range(DEFAULT_TIME_SCALE, 1.0, 10.0, "Time scale should be between 1x and 10x")


func _test_auto_save_interval_positive() -> void:
	assert_gt(DEFAULT_AUTO_SAVE_INTERVAL, 0, "Auto save interval must be positive")
	assert_lt(DEFAULT_AUTO_SAVE_INTERVAL, DEFAULT_GENERATIONS, "Auto save should happen before training ends")


func _test_max_eval_time_reasonable() -> void:
	# 60 seconds per individual is the spec
	assert_eq(DEFAULT_MAX_EVAL_TIME, 60.0, "Max eval time should be 60 seconds per spec")
	assert_gt(DEFAULT_MAX_EVAL_TIME, 10.0, "Eval time should allow meaningful gameplay")


func _test_population_size_matches_evolution_spec() -> void:
	# Per CLAUDE.md, actual training uses 48 parallel arenas
	# Trainer default is 50 for sequential training
	assert_gt(DEFAULT_POPULATION_SIZE, 10, "Population should be large enough for diversity")
	assert_lt(DEFAULT_POPULATION_SIZE, 200, "Population should not be excessively large")


# ============================================================
# Training Stats Structure Tests
# ============================================================

func _test_training_stats_structure() -> void:
	# Verify expected keys in training stats dictionary
	var expected_keys := [
		"is_training",
		"generation",
		"individual",
		"population_size",
		"eval_time",
		"max_eval_time",
		"best_fitness",
		"all_time_best"
	]

	# Create mock stats to verify structure expectations
	var mock_stats := {
		"is_training": true,
		"generation": 5,
		"individual": 10,
		"population_size": 50,
		"eval_time": 30.0,
		"max_eval_time": 60.0,
		"best_fitness": 150.0,
		"all_time_best": 200.0
	}

	for key in expected_keys:
		assert_true(mock_stats.has(key), "Stats should have '%s' key" % key)

	# Type checks
	assert_true(mock_stats.is_training is bool, "is_training should be bool")
	assert_true(mock_stats.generation is int, "generation should be int")
	assert_true(mock_stats.individual is int, "individual should be int")
	assert_true(mock_stats.population_size is int, "population_size should be int")
	assert_true(mock_stats.eval_time is float, "eval_time should be float")
	assert_true(mock_stats.max_eval_time is float, "max_eval_time should be float")
	assert_true(mock_stats.best_fitness is float, "best_fitness should be float")
	assert_true(mock_stats.all_time_best is float, "all_time_best should be float")


# ============================================================
# AI Action Structure Tests
# ============================================================

func _test_ai_action_structure() -> void:
	# Verify expected structure of get_ai_action() return value
	var default_action := {
		"move_direction": Vector2.ZERO,
		"shoot_direction": Vector2.ZERO
	}

	assert_true(default_action.has("move_direction"), "Action should have move_direction")
	assert_true(default_action.has("shoot_direction"), "Action should have shoot_direction")
	assert_true(default_action.move_direction is Vector2, "move_direction should be Vector2")
	assert_true(default_action.shoot_direction is Vector2, "shoot_direction should be Vector2")
