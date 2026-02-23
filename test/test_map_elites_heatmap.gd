extends "res://test/test_base.gd"
## Tests for MAP-Elites heatmap and archive grid helper.


func _run_tests() -> void:
    print("\n[MAP-Elites Heatmap Tests]")

    _test("get_archive_grid_empty", _test_get_archive_grid_empty)
    _test("get_archive_grid_populated", _test_get_archive_grid_populated)
    _test("get_archive_grid_dimensions", _test_get_archive_grid_dimensions)
    _test("get_archive_grid_fitness_values", _test_get_archive_grid_fitness_values)
    _test("get_archive_grid_custom_size", _test_get_archive_grid_custom_size)
    _test("heatmap_screen_to_cell_basic", _test_heatmap_screen_to_cell_basic)
    _test("heatmap_screen_to_cell_outside", _test_heatmap_screen_to_cell_outside)


func _test_get_archive_grid_empty() -> void:
    var me := MapElites.new(5)
    var grid: Array = me.get_archive_grid()
    assert_eq(grid.size(), 5, "Grid should have 5 columns")
    for x in 5:
        assert_eq(grid[x].size(), 5, "Each column should have 5 rows")
        for y in 5:
            assert_null(grid[x][y], "Empty archive should have all null cells")


func _test_get_archive_grid_populated() -> void:
    var me := MapElites.new(10)
    me.add("sol_a", Vector2(0.1, 0.1), 100.0)
    me.add("sol_b", Vector2(0.4, 0.4), 200.0)

    var grid: Array = me.get_archive_grid()
    # At least 2 non-null cells should exist
    var occupied := 0
    for x in 10:
        for y in 10:
            if grid[x][y] != null:
                occupied += 1
    assert_eq(occupied, 2, "Should have 2 occupied cells matching archive")


func _test_get_archive_grid_dimensions() -> void:
    var me := MapElites.new(20)
    var grid: Array = me.get_archive_grid()
    assert_eq(grid.size(), 20, "Default grid should be 20 columns")
    assert_eq(grid[0].size(), 20, "Default grid should have 20 rows per column")


func _test_get_archive_grid_fitness_values() -> void:
    var me := MapElites.new(10)
    me.add("fighter", Vector2(0.3, 0.0), 500.0)

    var grid: Array = me.get_archive_grid()
    # Find the occupied cell
    var found := false
    for x in 10:
        for y in 10:
            if grid[x][y] != null:
                assert_approx(grid[x][y].fitness, 500.0, 0.1, "Grid cell fitness should match")
                assert_true(grid[x][y].has("behavior"), "Grid cell should have behavior key")
                found = true
    assert_true(found, "Should find at least one occupied cell")


func _test_get_archive_grid_custom_size() -> void:
    var me := MapElites.new(3)
    var grid: Array = me.get_archive_grid()
    assert_eq(grid.size(), 3)
    assert_eq(grid[0].size(), 3)
    assert_eq(grid[2].size(), 3)


func _test_heatmap_screen_to_cell_basic() -> void:
    ## Test the screen-to-cell conversion logic.
    var heatmap := MapElitesHeatmap.new()
    heatmap.size = Vector2(400, 300)
    heatmap._grid_size = 10

    # A point in the center of the plot area should map to a middle cell
    var plot_rect := heatmap._get_plot_rect()
    var center := plot_rect.position + plot_rect.size / 2
    var cell: Vector2i = heatmap._screen_to_cell(center)
    assert_gte(cell.x, 3.0, "Center X cell should be middle-ish")
    assert_lte(cell.x, 6.0)
    assert_gte(cell.y, 3.0, "Center Y cell should be middle-ish")
    assert_lte(cell.y, 6.0)


func _test_heatmap_screen_to_cell_outside() -> void:
    ## Points outside the plot area should return (-1, -1).
    var heatmap := MapElitesHeatmap.new()
    heatmap.size = Vector2(400, 300)
    heatmap._grid_size = 10

    var cell: Vector2i = heatmap._screen_to_cell(Vector2(-10, -10))
    assert_eq(cell, Vector2i(-1, -1), "Outside point should return (-1, -1)")
