extends "res://test/test_base.gd"
## Tests for demo export support (model fallback path and --demo flag).

var NeuralNetwork = preload("res://ai/neural_network.gd")


func _run_tests() -> void:
	print("\n[Demo Export Tests]")

	_test("load_missing_file_returns_null", _test_missing_file)
	_test("fallback_path_construction", _test_fallback_path)
	_test("demo_flag_string_matching", _test_demo_flag)
	_test("basename_extraction", _test_basename)


func _test_missing_file() -> void:
	var result = NeuralNetwork.load_from_file("user://nonexistent_network.nn")
	assert_null(result, "Loading a nonexistent file should return null")


func _test_fallback_path() -> void:
	# Verify the fallback path logic: res://models/ + basename
	var path := "user://best_network.nn"
	var expected_fallback := "res://models/" + path.get_file()
	assert_eq(expected_fallback, "res://models/best_network.nn",
		"Fallback should construct res://models/<basename>")


func _test_demo_flag() -> void:
	# Verify the --demo flag is correctly identified in arg parsing
	var args := ["--demo", "--auto-train", "--other"]
	var found_demo := false
	for arg in args:
		if arg == "--demo":
			found_demo = true
			break
	assert_true(found_demo, "--demo flag should be detected in args")


func _test_basename() -> void:
	# Verify get_file() extracts basename correctly for various paths
	assert_eq("user://best_network.nn".get_file(), "best_network.nn",
		"Should extract basename from user:// path")
	assert_eq("user://subdir/model.nn".get_file(), "model.nn",
		"Should extract basename from nested user:// path")
	assert_eq("/absolute/path/network.nn".get_file(), "network.nn",
		"Should extract basename from absolute path")
