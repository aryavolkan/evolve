extends "res://test/test_base.gd"

## Tests for ui/educational_overlay.gd

var OverlayScript = preload("res://ui/educational_overlay.gd")


func _run_tests() -> void:
	print("\n[Educational Overlay Tests]")

	_test("creates_without_error", func():
		var overlay = OverlayScript.new()
		assert_not_null(overlay)
		overlay.free()
	)

	_test("starts_hidden_after_ready", func():
		var overlay = OverlayScript.new()
		# Simulate _ready() which sets visible = false
		overlay._ready()
		assert_false(overlay.visible, "Should be hidden after _ready")
		overlay.free()
	)

	_test("analyze_threats_detects_enemy", func():
		var overlay = OverlayScript.new()
		# Build synthetic inputs: 86 values, all zero
		var inputs := PackedFloat32Array()
		inputs.resize(86)
		inputs.fill(0.0)
		# Ray 5: enemy at 70% proximity, queen type (1.0)
		var base := 5 * 5  # ray 5 * INPUTS_PER_RAY
		inputs[base] = 0.7      # enemy_dist
		inputs[base + 1] = 1.0  # enemy_type (queen)
		var result: Dictionary = overlay._analyze_threats(inputs)
		assert_eq(result.ray_index, 5, "Should detect ray 5")
		assert_eq(result.kind, "enemy", "Should be enemy kind")
		assert_approx(result.dist_value, 0.7, 0.01, "Distance should be 0.7")
		assert_approx(result.type_value, 1.0, 0.01, "Type should be 1.0 (queen)")
		overlay.free()
	)

	_test("analyze_threats_detects_powerup_when_no_enemy", func():
		var overlay = OverlayScript.new()
		var inputs := PackedFloat32Array()
		inputs.resize(86)
		inputs.fill(0.0)
		# Ray 10: powerup at 60% proximity
		var base := 10 * 5
		inputs[base + 3] = 0.6  # powerup_dist
		var result: Dictionary = overlay._analyze_threats(inputs)
		assert_eq(result.ray_index, 10, "Should detect ray 10")
		assert_eq(result.kind, "powerup", "Should be powerup kind")
		assert_approx(result.dist_value, 0.6, 0.01)
		overlay.free()
	)

	_test("analyze_threats_returns_none_for_empty", func():
		var overlay = OverlayScript.new()
		var inputs := PackedFloat32Array()
		inputs.resize(86)
		inputs.fill(0.0)
		var result: Dictionary = overlay._analyze_threats(inputs)
		assert_eq(result.kind, "none", "Should be none when no detections")
		assert_eq(result.ray_index, -1, "Ray index should be -1")
		overlay.free()
	)

	_test("describe_shooting_fires_strongest", func():
		var overlay = OverlayScript.new()
		# outputs: [move_x, move_y, shoot_up, shoot_down, shoot_left, shoot_right]
		var outputs := PackedFloat32Array([0.0, 0.0, 0.1, 0.85, 0.2, 0.05])
		var text: String = overlay._describe_shooting(outputs)
		assert_true(text.contains("DOWN"), "Should mention DOWN direction")
		assert_true(text.contains("0.85"), "Should mention output value")
		overlay.free()
	)

	_test("describe_shooting_no_fire_below_threshold", func():
		var overlay = OverlayScript.new()
		var outputs := PackedFloat32Array([0.0, 0.0, -0.5, -0.3, -0.8, -0.1])
		var text: String = overlay._describe_shooting(outputs)
		assert_eq(text, "Not shooting", "All negative outputs should mean no shooting")
		overlay.free()
	)

	_test("describe_state_shows_invincible", func():
		var overlay = OverlayScript.new()
		var inputs := PackedFloat32Array()
		inputs.resize(86)
		inputs.fill(0.0)
		inputs[82] = 1.0  # PLAYER_STATE_OFFSET + 2 = invincible
		var text: String = overlay._describe_state(inputs)
		assert_true(text.contains("INVINCIBLE"), "Should show INVINCIBLE state")
		overlay.free()
	)

	_test("describe_state_shows_multiple", func():
		var overlay = OverlayScript.new()
		var inputs := PackedFloat32Array()
		inputs.resize(86)
		inputs.fill(0.0)
		inputs[82] = 1.0  # invincible
		inputs[83] = 1.0  # speed boost
		var text: String = overlay._describe_state(inputs)
		assert_true(text.contains("INVINCIBLE"), "Should show INVINCIBLE")
		assert_true(text.contains("SPEED BOOST"), "Should show SPEED BOOST")
		overlay.free()
	)
