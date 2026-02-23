extends "res://test/test_base.gd"
## Integration tests for NSGA-II multi-objective evolution.

const Evolution = preload("res://ai/evolution.gd")
const NSGA2 = preload("res://evolve-core/genetic/nsga2.gd")


func run_tests() -> void:
    print("\n[Evolution NSGA-II Integration Tests]")

    # Basic integration
    _test("nsga2_mode_toggle", _test_nsga2_mode_toggle)
    _test("set_objectives_also_sets_fitness", _test_set_objectives_also_sets_fitness)
    _test("get_objectives_returns_stored", _test_get_objectives_returns_stored)
    _test("evolve_nsga2_increments_generation", _test_evolve_nsga2_increments_generation)
    _test("evolve_nsga2_preserves_population_size", _test_evolve_nsga2_preserves_population_size)
    _test("evolve_nsga2_tracks_best_network", _test_evolve_nsga2_tracks_best_network)
    _test("evolve_nsga2_tracks_all_time_best", _test_evolve_nsga2_tracks_all_time_best)
    _test("evolve_nsga2_resets_scores", _test_evolve_nsga2_resets_scores)
    _test("evolve_nsga2_builds_pareto_front", _test_evolve_nsga2_builds_pareto_front)
    _test("evolve_nsga2_computes_hypervolume", _test_evolve_nsga2_computes_hypervolume)

    # Backward compatibility
    _test("single_objective_still_works", _test_single_objective_still_works)
    _test("nsga2_off_by_default", _test_nsga2_off_by_default)

    # Edge cases
    _test("evolve_nsga2_all_equal_objectives", _test_all_equal_objectives)
    _test("evolve_nsga2_all_zero_objectives", _test_all_zero_objectives)
    _test("evolve_nsga2_diverse_tradeoffs", _test_diverse_tradeoffs)

    # Multi-generation
    _test("evolve_nsga2_multiple_generations", _test_multiple_generations)
    _test("evolve_nsga2_adaptive_mutation", _test_adaptive_mutation)


# ============================================================
# Basic Integration
# ============================================================


func _test_nsga2_mode_toggle() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    assert_false(evo.use_nsga2, "NSGA-II should be off by default")
    evo.use_nsga2 = true
    assert_true(evo.use_nsga2, "Should be able to enable NSGA-II")


func _test_set_objectives_also_sets_fitness() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.set_objectives(0, Vector3(100, 200, 50))
    assert_approx(evo.fitness_scores[0], 350.0, 0.001, "Fitness should be sum of objectives")


func _test_get_objectives_returns_stored() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.set_objectives(3, Vector3(10, 20, 30))
    var obj := evo.get_objectives(3)
    assert_approx(obj.x, 10.0, 0.001)
    assert_approx(obj.y, 20.0, 0.001)
    assert_approx(obj.z, 30.0, 0.001)


func _test_evolve_nsga2_increments_generation() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    for i in 10:
        evo.set_objectives(i, Vector3(float(i), float(10 - i), 5.0))

    evo.evolve()
    assert_eq(evo.generation, 1, "Generation should increment")


func _test_evolve_nsga2_preserves_population_size() -> void:
    var evo = Evolution.new(20, 5, 3, 2, 5)
    evo.use_nsga2 = true

    for i in 20:
        evo.set_objectives(i, Vector3(float(i), float(20 - i), randf() * 10.0))

    evo.evolve()
    assert_eq(evo.population.size(), 20, "Population size should remain 20")


func _test_evolve_nsga2_tracks_best_network() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    for i in 10:
        evo.set_objectives(i, Vector3(float(i) * 10, float(i) * 5, float(i) * 2))

    evo.evolve()
    assert_not_null(evo.best_network, "Should track best network")
    # Best = index 9 with sum 90+45+18 = 153
    assert_approx(evo.best_fitness, 153.0, 0.001, "Best fitness should be sum of best objectives")


func _test_evolve_nsga2_tracks_all_time_best() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    # Gen 1: high scores
    for i in 10:
        evo.set_objectives(i, Vector3(float(i) * 10, float(i) * 10, float(i) * 10))
    evo.evolve()
    assert_approx(evo.all_time_best_fitness, 270.0, 0.001)

    # Gen 2: lower scores
    for i in 10:
        evo.set_objectives(i, Vector3(float(i), float(i), float(i)))
    evo.evolve()
    # All-time best should still be 270
    assert_approx(evo.all_time_best_fitness, 270.0, 0.001, "All-time best should persist")


func _test_evolve_nsga2_resets_scores() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    for i in 10:
        evo.set_objectives(i, Vector3(10, 20, 30))

    evo.evolve()

    for i in 10:
        assert_approx(evo.fitness_scores[i], 0.0, 0.001, "Fitness should be reset")
        var obj := evo.get_objectives(i)
        assert_approx(obj.x, 0.0, 0.001, "Objective x should be reset")
        assert_approx(obj.y, 0.0, 0.001, "Objective y should be reset")
        assert_approx(obj.z, 0.0, 0.001, "Objective z should be reset")


func _test_evolve_nsga2_builds_pareto_front() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    # Create clear trade-offs: some on front 0, some dominated
    evo.set_objectives(0, Vector3(100, 10, 5))  # Front 0 (high survival)
    evo.set_objectives(1, Vector3(10, 100, 5))  # Front 0 (high kills)
    evo.set_objectives(2, Vector3(10, 10, 100))  # Front 0 (high powerups)
    for i in range(3, 10):
        evo.set_objectives(i, Vector3(1, 1, 1))  # Dominated

    evo.evolve()
    assert_true(evo.pareto_front.size() >= 3, "Pareto front should have at least 3 members")


func _test_evolve_nsga2_computes_hypervolume() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    for i in 10:
        evo.set_objectives(i, Vector3(float(i) * 10, float(10 - i) * 10, 5.0))

    evo.evolve()
    assert_gt(evo.last_hypervolume, 0.0, "Hypervolume should be positive")


# ============================================================
# Backward Compatibility
# ============================================================


func _test_single_objective_still_works() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    # use_nsga2 is false by default

    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)

    evo.evolve()
    assert_eq(evo.generation, 1, "Single-objective evolve should still work")
    assert_approx(evo.best_fitness, 90.0, 0.001)


func _test_nsga2_off_by_default() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    assert_false(evo.use_nsga2, "NSGA-II should be off by default")


# ============================================================
# Edge Cases
# ============================================================


func _test_all_equal_objectives() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    for i in 10:
        evo.set_objectives(i, Vector3(50, 50, 50))

    # Should not crash
    evo.evolve()
    assert_eq(evo.generation, 1, "Should handle all-equal objectives")
    assert_eq(evo.population.size(), 10, "Population should remain intact")


func _test_all_zero_objectives() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    for i in 10:
        evo.set_objectives(i, Vector3.ZERO)

    # Should not crash
    evo.evolve()
    assert_eq(evo.generation, 1, "Should handle all-zero objectives")


func _test_diverse_tradeoffs() -> void:
    var evo = Evolution.new(20, 5, 3, 2, 5)
    evo.use_nsga2 = true

    # Create a population with diverse trade-offs
    var rng := RandomNumberGenerator.new()
    rng.seed = 42
    for i in 20:
        evo.set_objectives(i, Vector3(rng.randf() * 100, rng.randf() * 100, rng.randf() * 100))

    evo.evolve()
    assert_eq(evo.population.size(), 20, "Population size should remain 20")
    assert_true(evo.pareto_front.size() >= 1, "Should have at least 1 Pareto front member")


# ============================================================
# Multi-Generation
# ============================================================


func _test_multiple_generations() -> void:
    var evo = Evolution.new(20, 5, 3, 2, 3)
    evo.use_nsga2 = true

    var rng := RandomNumberGenerator.new()
    rng.seed = 99

    for gen in 5:
        for i in 20:
            evo.set_objectives(i, Vector3(rng.randf() * 100, rng.randf() * 100, rng.randf() * 100))
        evo.evolve()

    assert_eq(evo.generation, 5, "Should complete 5 generations")
    assert_eq(evo.population.size(), 20, "Population should remain 20")
    assert_not_null(evo.all_time_best_network, "Should have all-time best")


func _test_adaptive_mutation() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.use_nsga2 = true

    # Run several generations with identical objectives to trigger stagnation
    for gen in 6:
        for i in 10:
            evo.set_objectives(i, Vector3(50, 50, 50))
        evo.evolve()

    # After STAGNATION_THRESHOLD (3) generations of no improvement,
    # mutation should have been boosted
    assert_gte(
        float(evo.stagnant_generations),
        float(Evolution.STAGNATION_THRESHOLD),
        "Should detect stagnation"
    )
