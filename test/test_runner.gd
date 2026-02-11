extends SceneTree
## Minimal test runner for Evolve project.
## Run with: godot --headless --script test/test_runner.gd

var _tests_run := 0
var _tests_passed := 0
var _tests_failed := 0
var _current_test := ""
var _failure_messages: Array[String] = []


func _init() -> void:
	print("\n========================================")
	print("       EVOLVE TEST SUITE")
	print("========================================\n")

	_run_all_tests()

	print("\n========================================")
	print("       RESULTS")
	print("========================================")
	print("Tests run:    %d" % _tests_run)
	print("Tests passed: %d" % _tests_passed)
	print("Tests failed: %d" % _tests_failed)

	if _failure_messages.size() > 0:
		print("\nFAILURES:")
		for msg in _failure_messages:
			print("  - %s" % msg)

	print("========================================\n")

	# Exit with appropriate code
	quit(0 if _tests_failed == 0 else 1)


func _run_all_tests() -> void:
	# Import and run each test suite
	var test_suites: Array = [
		preload("res://test/test_neural_network.gd"),
		preload("res://test/test_evolution.gd"),
		preload("res://test/test_difficulty.gd"),
		preload("res://test/test_highscore.gd"),
		preload("res://test/test_enemy.gd"),
		preload("res://test/test_sensor.gd"),
		preload("res://test/test_ai_controller.gd"),
		preload("res://test/test_edge_cases.gd"),
		preload("res://test/test_powerup.gd"),
		preload("res://test/test_trainer.gd"),
		preload("res://test/test_curriculum.gd"),
		preload("res://test/test_curriculum_phase2.gd"),
		preload("res://test/test_nsga2.gd"),
		preload("res://test/test_evolution_nsga2.gd"),
		preload("res://test/test_integration.gd"),
		preload("res://test/test_elman_memory.gd"),
		preload("res://test/test_neat_config.gd"),
		preload("res://test/test_neat_innovation.gd"),
		preload("res://test/test_neat_genome.gd"),
		preload("res://test/test_neat_crossover.gd"),
		preload("res://test/test_neat_species.gd"),
		preload("res://test/test_neat_network.gd"),
		preload("res://test/test_neat_evolution.gd"),
		preload("res://test/test_map_elites.gd"),
		preload("res://test/test_sensor_cache.gd"),
		preload("res://test/test_map_elites_heatmap.gd"),
		preload("res://test/test_enemy_sensor.gd"),
		preload("res://test/test_enemy_ai_controller.gd"),
		preload("res://test/test_coevolution.gd"),
		preload("res://test/test_title_screen.gd"),
		preload("res://test/test_game_over_screen.gd"),
		preload("res://test/test_sensor_visualizer.gd"),
	]

	for suite_script in test_suites:
		var suite = suite_script.new()
		suite._runner = self
		suite._run_tests()


func _start_test(name: String) -> void:
	_current_test = name
	_tests_run += 1


func _pass_test() -> void:
	_tests_passed += 1
	print("  PASS: %s" % _current_test)


func _fail_test(message: String) -> void:
	_tests_failed += 1
	var full_msg := "%s: %s" % [_current_test, message]
	_failure_messages.append(full_msg)
	print("  FAIL: %s" % _current_test)
	print("        %s" % message)
