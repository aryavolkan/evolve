extends "res://test/test_base.gd"

## Tests for ui/title_screen.gd

var TitleScreenScript = preload("res://ui/title_screen.gd")


func _run_tests() -> void:
	print("[Title Screen Tests]")

	_test("creates_without_error", func():
		var screen = TitleScreenScript.new()
		assert_not_null(screen)
	)

	_test("has_menu_items", func():
		var screen = TitleScreenScript.new()
		assert_eq(screen.MENU_ITEMS.size(), 6, "Should have 6 menu items")
	)

	_test("menu_modes_correct", func():
		var screen = TitleScreenScript.new()
		var modes = []
		for item in screen.MENU_ITEMS:
			modes.append(item.mode)
		assert_true("play" in modes, "Should have play mode")
		assert_true("watch" in modes, "Should have watch mode")
		assert_true("train" in modes, "Should have train mode")
		assert_true("sandbox" in modes, "Should have sandbox mode")
		assert_true("compare" in modes, "Should have compare mode")
		assert_true("coevolution" in modes, "Should have coevolution mode")
	)

	_test("show_hide_menu", func():
		var screen = TitleScreenScript.new()
		screen.show_menu()
		assert_true(screen.visible, "Should be visible after show")
		screen.hide_menu()
		assert_false(screen.visible, "Should be hidden after hide")
	)

	_test("signal_defined", func():
		var screen = TitleScreenScript.new()
		assert_true(screen.has_signal("mode_selected"), "Should have mode_selected signal")
	)
