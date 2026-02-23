extends "res://test/test_base.gd"
## Tests for ai/arena_pool.gd — viewport grid management.

var ArenaPoolScript = preload("res://ai/arena_pool.gd")


func run_tests() -> void:
    print("\n[ArenaPool Tests]")

    _test("default_state", _test_default_state)
    _test("grid_dimensions_default", _test_grid_dimensions_default)
    _test("grid_dimensions_custom", _test_grid_dimensions_custom)
    _test("fullscreen_index_starts_negative", _test_fullscreen_index_starts_negative)
    _test("cleanup_all_clears_slots", _test_cleanup_all_clears_slots)
    _test("destroy_resets_state", _test_destroy_resets_state)
    _test("set_stats_text_without_setup", _test_set_stats_text_without_setup)
    _test("get_slot_at_position_empty", _test_get_slot_at_position_empty)
    _test("get_window_size_without_tree", _test_get_window_size_without_tree)
    _test("get_viewport_out_of_bounds", _test_get_viewport_out_of_bounds)
    _test("replace_slot_out_of_bounds", _test_replace_slot_out_of_bounds)


func _test_default_state() -> void:
    var pool = ArenaPoolScript.new()
    assert_null(pool.canvas_layer, "Canvas layer should be null before setup")
    assert_null(pool.container, "Container should be null before setup")
    assert_null(pool.stats_label, "Stats label should be null before setup")
    assert_eq(pool.slots.size(), 0, "Slots should be empty before setup")
    assert_eq(pool.fullscreen_index, -1, "Fullscreen index should be -1")
    assert_eq(pool.parallel_count, 20, "Default parallel count should be 20")


func _test_grid_dimensions_default() -> void:
    var pool = ArenaPoolScript.new()
    var grid = pool.get_grid_dimensions()
    assert_eq(grid.cols, 5, "Default grid should have 5 columns")
    assert_eq(grid.rows, 4, "Default grid with 20 parallel should have 4 rows")


func _test_grid_dimensions_custom() -> void:
    var pool = ArenaPoolScript.new()
    pool.parallel_count = 10
    var grid = pool.get_grid_dimensions()
    assert_eq(grid.cols, 5, "Grid should always have 5 columns")
    assert_eq(grid.rows, 2, "10 arenas / 5 cols = 2 rows")

    pool.parallel_count = 3
    grid = pool.get_grid_dimensions()
    assert_eq(grid.rows, 1, "3 arenas should need 1 row")

    pool.parallel_count = 6
    grid = pool.get_grid_dimensions()
    assert_eq(grid.rows, 2, "6 arenas should need 2 rows")


func _test_fullscreen_index_starts_negative() -> void:
    var pool = ArenaPoolScript.new()
    assert_eq(pool.fullscreen_index, -1, "Should start in grid view (index -1)")


func _test_cleanup_all_clears_slots() -> void:
    var pool = ArenaPoolScript.new()
    # No setup needed — cleanup_all should work safely on empty pool
    pool.cleanup_all()
    assert_eq(pool.slots.size(), 0, "Slots should be empty after cleanup")
    assert_eq(pool.fullscreen_index, -1, "Fullscreen should reset after cleanup")


func _test_destroy_resets_state() -> void:
    var pool = ArenaPoolScript.new()
    # Destroy without setup should be safe
    pool.destroy()
    assert_null(pool.canvas_layer, "Canvas layer should be null after destroy")
    assert_null(pool.container, "Container should be null after destroy")
    assert_null(pool.stats_label, "Stats label should be null after destroy")
    assert_eq(pool.slots.size(), 0, "Slots should be empty after destroy")


func _test_set_stats_text_without_setup() -> void:
    var pool = ArenaPoolScript.new()
    # Should not crash when no stats label exists
    pool.set_stats_text("test text")
    # No assertion needed — just verifying no crash


func _test_get_slot_at_position_empty() -> void:
    var pool = ArenaPoolScript.new()
    assert_eq(pool.get_slot_at_position(Vector2(100, 100)), -1, "Should return -1 when no slots")


func _test_get_window_size_without_tree() -> void:
    var pool = ArenaPoolScript.new()
    var size = pool.get_window_size()
    assert_eq(size, Vector2(1280, 720), "Should return default 1280x720 without tree")


func _test_get_viewport_out_of_bounds() -> void:
    var pool = ArenaPoolScript.new()
    assert_null(pool.get_viewport(-1), "Negative index should return null")
    assert_null(pool.get_viewport(0), "Out of bounds index should return null")
    assert_null(pool.get_viewport(100), "Way out of bounds index should return null")


func _test_replace_slot_out_of_bounds() -> void:
    var pool = ArenaPoolScript.new()
    var result = pool.replace_slot(-1)
    assert_true(result.is_empty(), "Negative index should return empty dict")
    result = pool.replace_slot(0)
    assert_true(result.is_empty(), "Out of bounds index should return empty dict")
