extends "res://test/test_base.gd"

## Tests for ui/sensor_visualizer.gd

var SensorVizScript = preload("res://ui/sensor_visualizer.gd")


func _run_tests() -> void:
	print("[Sensor Visualizer Tests]")

	_test("creates_without_error", func():
		var viz = SensorVizScript.new()
		assert_not_null(viz)
	)

	_test("starts_disabled", func():
		var viz = SensorVizScript.new()
		assert_false(viz.enabled, "Should start disabled")
	)

	_test("toggle_enables", func():
		var viz = SensorVizScript.new()
		viz.toggle()
		assert_true(viz.enabled, "Should be enabled after first toggle")
	)

	_test("toggle_twice_disables", func():
		var viz = SensorVizScript.new()
		viz.toggle()
		viz.toggle()
		assert_false(viz.enabled, "Should be disabled after second toggle")
	)

	_test("color_constants_defined", func():
		var viz = SensorVizScript.new()
		# Just verify they exist and are Color type
		assert_true(viz.COLOR_ENEMY is Color, "COLOR_ENEMY should be Color")
		assert_true(viz.COLOR_POWERUP is Color, "COLOR_POWERUP should be Color")
		assert_true(viz.COLOR_OBSTACLE is Color, "COLOR_OBSTACLE should be Color")
		assert_true(viz.COLOR_WALL is Color, "COLOR_WALL should be Color")
	)
