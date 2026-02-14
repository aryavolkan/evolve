extends "res://test/test_base.gd"

## Tests for ui/training_dashboard.gd

var TrainingDashboardScript = preload("res://ui/training_dashboard.gd")


class MockStatsTracker extends RefCounted:
	var history_best_fitness: Array = []
	var history_avg_fitness: Array = []
	var history_min_fitness: Array = []
	var history_avg_kill_score: Array = []
	var history_avg_powerup_score: Array = []
	var history_avg_survival_score: Array = []


func _run_tests() -> void:
	print("[Training Dashboard Tests]")

	_test("nice_ceil_ranges", func():
		assert_eq(TrainingDashboardScript._nice_ceil(50.0), 100.0)
		assert_eq(TrainingDashboardScript._nice_ceil(100.0), 100.0)
		assert_eq(TrainingDashboardScript._nice_ceil(101.0), 200.0)
		assert_eq(TrainingDashboardScript._nice_ceil(500.0), 500.0)
		assert_eq(TrainingDashboardScript._nice_ceil(501.0), 1000.0)
		assert_eq(TrainingDashboardScript._nice_ceil(5001.0), 6000.0)
	)

	_test("update_species_count_appends", func():
		var dash = TrainingDashboardScript.new()
		dash.update_species_count(3)
		dash.update_species_count(5)
		assert_eq(dash._species_history.size(), 2)
		assert_eq(dash._species_history[0], 3)
		assert_eq(dash._species_history[1], 5)
	)

	_test("score_bars_handle_mismatched_histories", func():
		var dash = TrainingDashboardScript.new()
		var stats = MockStatsTracker.new()
		stats.history_avg_kill_score = [10.0, 20.0, 30.0]
		stats.history_avg_powerup_score = [5.0]
		stats.history_avg_survival_score = []
		dash.stats_tracker = stats
		# Should not error when arrays are different lengths
		dash._draw_score_bars(ThemeDB.fallback_font, 0.0, 0.0, 200.0, 60.0)
		assert_true(true, "Draw should complete without error")
	)
