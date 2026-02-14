extends "res://test/test_base.gd"

## Tests for sandbox training integration, overrides, and event generation.

var EventGeneratorScript = preload("res://scripts/event_generator.gd")
var SandboxTrainingModeScript = preload("res://modes/sandbox_training_mode.gd")
var MainSceneScript = preload("res://main.gd")


func _run_tests() -> void:
	print("[Sandbox Training Tests]")

	_test("spawn_rate_multiplier_speeds_enemy_events", func():
		var baseline = EventGeneratorScript.generate(123)
		var fast = EventGeneratorScript.generate(123, {}, {"spawn_rate_multiplier": 2.0})
		assert_lt(fast.enemy_spawns[0].time, baseline.enemy_spawns[0].time, "Faster spawn rate should reduce first spawn time")
		assert_lt(fast.enemy_spawns[5].time, baseline.enemy_spawns[5].time, "Faster spawn rate should reduce later spawn times")
	)

	_test("powerup_frequency_changes_spawn_count", func():
		var baseline = EventGeneratorScript.generate(456)
		var dense = EventGeneratorScript.generate(456, {}, {"powerup_frequency": 2.0})
		assert_gt(dense.powerup_spawns.size(), baseline.powerup_spawns.size(), "Higher powerup frequency should increase spawn count")
	)

	_test("starting_difficulty_affects_initial_spawn_interval", func():
		var baseline = EventGeneratorScript.generate(789)
		var hard = EventGeneratorScript.generate(789, {}, {"starting_difficulty": 0.9})
		assert_lt(hard.enemy_spawns[0].time, baseline.enemy_spawns[0].time, "Higher starting difficulty should spawn enemies sooner")
	)

	_test("sandbox_training_overrides_are_clamped", func():
		var mode = SandboxTrainingModeScript.new()
		mode.sandbox_cfg = {
			"enemy_types": [1, 4],
			"spawn_rate_multiplier": 10.0,
			"powerup_frequency": 0.05,
			"starting_difficulty": 1.5,
		}
		var overrides = mode._build_training_overrides()
		assert_true(overrides.has("enemy_types"), "Overrides should include enemy types")
		assert_array_eq(overrides.enemy_types, [1, 4], "Enemy types should be preserved")
		assert_eq(overrides.spawn_rate_multiplier, 3.0, "Spawn rate should be clamped to max")
		assert_eq(overrides.powerup_frequency, 0.25, "Powerup frequency should be clamped to min")
		assert_eq(overrides.starting_difficulty, 1.0, "Starting difficulty should be clamped to 1.0")
	)

	_test("main_scene_forwards_sandbox_overrides_to_event_generator", func():
		var overrides = {"spawn_rate_multiplier": 1.5, "powerup_frequency": 0.5}
		var via_main = MainSceneScript.generate_random_events(2024, {}, overrides)
		var direct = EventGeneratorScript.generate(2024, {}, overrides)
		assert_eq(via_main.enemy_spawns.size(), direct.enemy_spawns.size(), "Enemy spawn counts should match direct generator")
		assert_approx(via_main.enemy_spawns[0].time, direct.enemy_spawns[0].time, 0.0001, "First spawn time should match direct generator")
		assert_eq(via_main.powerup_spawns.size(), direct.powerup_spawns.size(), "Powerup spawn counts should match direct generator")
	)
