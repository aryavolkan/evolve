extends "res://test/test_base.gd"

## Tests for MapElites quality-diversity archive.


func run_tests() -> void:
    _test("map_elites_init", test_init)
    _test("map_elites_add_new_bin", test_add_new_bin)
    _test("map_elites_add_better_replaces", test_add_better_replaces)
    _test("map_elites_add_worse_rejected", test_add_worse_rejected)
    _test("map_elites_coverage", test_coverage)
    _test("map_elites_get_elite", test_get_elite)
    _test("map_elites_get_elite_empty", test_get_elite_empty)
    _test("map_elites_sample", test_sample)
    _test("map_elites_sample_empty", test_sample_empty)
    _test("map_elites_sample_capped", test_sample_capped)
    _test("map_elites_best_fitness", test_best_fitness)
    _test("map_elites_avg_fitness", test_avg_fitness)
    _test("map_elites_get_stats", test_get_stats)
    _test("map_elites_clear", test_clear)
    _test("map_elites_calculate_behavior", test_calculate_behavior)
    _test("map_elites_calculate_behavior_zero_time", test_calculate_behavior_zero_time)
    _test("map_elites_expand_bounds", test_expand_bounds)
    _test("map_elites_different_bins", test_different_bins)
    _test("map_elites_custom_grid_size", test_custom_grid_size)


func test_init() -> void:
    var me := MapElites.new()
    assert_eq(me.grid_size, 20)
    assert_eq(me.archive.size(), 0)
    assert_approx(me.get_coverage(), 0.0)


func test_add_new_bin() -> void:
    var me := MapElites.new(10)
    var added := me.add("solution_a", Vector2(0.1, 0.1), 100.0)
    assert_true(added, "Should add to empty bin")
    assert_eq(me.archive.size(), 1)


func test_add_better_replaces() -> void:
    var me := MapElites.new(10)
    me.add("sol_weak", Vector2(0.1, 0.1), 50.0)
    var replaced := me.add("sol_strong", Vector2(0.1, 0.1), 100.0)
    assert_true(replaced, "Better solution should replace")
    assert_eq(me.archive.size(), 1)
    # The stored solution should be the stronger one
    var keys = me.archive.keys()
    assert_approx(me.archive[keys[0]].fitness, 100.0)


func test_add_worse_rejected() -> void:
    var me := MapElites.new(10)
    me.add("sol_strong", Vector2(0.1, 0.1), 100.0)
    var added := me.add("sol_weak", Vector2(0.1, 0.1), 50.0)
    assert_false(added, "Worse solution should be rejected")
    assert_eq(me.archive.size(), 1)
    var keys = me.archive.keys()
    assert_approx(me.archive[keys[0]].fitness, 100.0)


func test_coverage() -> void:
    var me := MapElites.new(5)  # 5x5 = 25 bins
    assert_approx(me.get_coverage(), 0.0)
    # Add solutions at spread-out behaviors to fill different bins
    me.add("a", Vector2(0.0, 0.0), 10.0)
    me.add("b", Vector2(0.4, 0.4), 20.0)
    # Coverage should be > 0 and <= 1
    assert_gt(me.get_coverage(), 0.0)
    assert_lte(me.get_coverage(), 1.0)


func test_get_elite() -> void:
    var me := MapElites.new(10)
    me.add("my_solution", Vector2(0.1, 0.1), 42.0)
    var bin = me._behavior_to_bin(Vector2(0.1, 0.1))
    var elite = me.get_elite(bin)
    assert_not_null(elite)
    assert_approx(elite.fitness, 42.0)
    assert_eq(elite.solution, "my_solution")


func test_get_elite_empty() -> void:
    var me := MapElites.new(10)
    var elite = me.get_elite(Vector2i(5, 5))
    assert_null(elite)


func test_sample() -> void:
    var me := MapElites.new(10)
    me.add("a", Vector2(0.0, 0.0), 10.0)
    me.add("b", Vector2(0.3, 0.3), 20.0)
    me.add("c", Vector2(0.45, 0.45), 30.0)
    var samples = me.sample(2)
    assert_eq(samples.size(), 2)
    # Each sample should have fitness and solution
    for s in samples:
        assert_gt(s.fitness, 0.0)
        assert_not_null(s.solution)


func test_sample_empty() -> void:
    var me := MapElites.new(10)
    var samples = me.sample(5)
    assert_eq(samples.size(), 0)


func test_sample_capped() -> void:
    var me := MapElites.new(10)
    me.add("only_one", Vector2(0.1, 0.1), 10.0)
    var samples = me.sample(100)
    assert_eq(samples.size(), 1)


func test_best_fitness() -> void:
    var me := MapElites.new(10)
    me.add("a", Vector2(0.0, 0.0), 10.0)
    me.add("b", Vector2(0.3, 0.3), 50.0)
    me.add("c", Vector2(0.45, 0.45), 30.0)
    assert_approx(me.get_best_fitness(), 50.0)


func test_avg_fitness() -> void:
    var me := MapElites.new(10)
    me.add("a", Vector2(0.0, 0.0), 10.0)
    me.add("b", Vector2(0.3, 0.3), 20.0)
    me.add("c", Vector2(0.45, 0.45), 30.0)
    assert_approx(me.get_average_fitness(), 20.0)


func test_get_stats() -> void:
    var me := MapElites.new(10)
    me.add("x", Vector2(0.1, 0.1), 99.0)
    var stats: Dictionary = me.get_stats()
    assert_eq(stats.grid_size, 10)
    assert_eq(stats.total_bins, 100)
    assert_gt(stats.occupied, 0)
    assert_approx(stats.best_fitness, 99.0)


func test_clear() -> void:
    var me := MapElites.new(10)
    me.add("a", Vector2(0.1, 0.1), 10.0)
    me.add("b", Vector2(0.3, 0.3), 20.0)
    assert_eq(me.archive.size(), 2)
    me.clear()
    assert_eq(me.archive.size(), 0)
    assert_approx(me.get_coverage(), 0.0)


func test_calculate_behavior() -> void:
    var stats := {"kills": 10, "powerups_collected": 5, "survival_time": 20.0}
    var behavior: Vector2 = MapElites.calculate_behavior(stats)
    # kill_rate = 10 / 20.0 = 0.5
    assert_approx(behavior.x, 0.5)
    # collect_rate = 5 / 20.0 = 0.25
    assert_approx(behavior.y, 0.25)


func test_calculate_behavior_zero_time() -> void:
    # survival_time = 0 should use 1.0 as floor
    var stats := {"kills": 3, "powerups_collected": 1, "survival_time": 0.0}
    var behavior: Vector2 = MapElites.calculate_behavior(stats)
    assert_approx(behavior.x, 3.0)
    assert_approx(behavior.y, 1.0)


func test_expand_bounds() -> void:
    var me := MapElites.new(10)
    # Initial bounds: x=[0, 0.5], y=[0, 0.5]
    assert_approx(me.behavior_maxs.x, 0.5)
    # Add a behavior that exceeds the max
    me.add("outlier", Vector2(2.0, 3.0), 10.0)
    # Bounds should have expanded (2.0 * 1.1 = 2.2, 3.0 * 1.1 = 3.3)
    assert_gt(me.behavior_maxs.x, 2.0)
    assert_gt(me.behavior_maxs.y, 3.0)


func test_different_bins() -> void:
    # Ensure sufficiently different behaviors go to different bins
    var me := MapElites.new(10)
    me.add("passive", Vector2(0.0, 0.0), 10.0)
    me.add("fighter", Vector2(0.4, 0.0), 20.0)
    me.add("collector", Vector2(0.0, 0.4), 30.0)
    me.add("versatile", Vector2(0.4, 0.4), 40.0)
    assert_eq(me.archive.size(), 4, "Four distinct behaviors should occupy 4 bins")


func test_custom_grid_size() -> void:
    var me := MapElites.new(5)
    assert_eq(me.grid_size, 5)
    var stats: Dictionary = me.get_stats()
    assert_eq(stats.total_bins, 25)
