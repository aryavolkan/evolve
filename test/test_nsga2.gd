extends "res://test/test_base.gd"
## Tests for NSGA-II multi-objective selection algorithm.

var NSGA2Script = preload("res://evolve-core/genetic/nsga2.gd")


func run_tests() -> void:
    print("\n[NSGA-II Tests]")

    # Dominance tests
    _test("nsga2_dominates_clear", _test_dominates_clear)
    _test("nsga2_dominates_equal", _test_dominates_equal)
    _test("nsga2_dominates_partial", _test_dominates_partial)
    _test("nsga2_dominates_reflexive", _test_dominates_reflexive)

    # Non-dominated sort tests
    _test("nsga2_sort_single", _test_sort_single)
    _test("nsga2_sort_clear_dominance", _test_sort_clear_dominance)
    _test("nsga2_sort_all_nondominated", _test_sort_all_nondominated)
    _test("nsga2_sort_all_equal", _test_sort_all_equal)
    _test("nsga2_sort_mixed_fronts", _test_sort_mixed_fronts)
    _test("nsga2_sort_covers_all", _test_sort_covers_all)

    # Crowding distance tests
    _test("nsga2_crowding_small_front", _test_crowding_small)
    _test("nsga2_crowding_boundaries_infinite", _test_crowding_boundaries)
    _test("nsga2_crowding_interior", _test_crowding_interior)
    _test("nsga2_crowding_identical_objectives", _test_crowding_identical)

    # Selection tests
    _test("nsga2_select_all_fit", _test_select_all_fit)
    _test("nsga2_select_half", _test_select_half)
    _test("nsga2_select_prefers_front0", _test_select_prefers_front0)
    _test("nsga2_select_diverse_within_front", _test_select_diverse_within_front)

    # Tournament selection tests
    _test("nsga2_tournament_prefers_better_rank", _test_tournament_rank)

    # Pareto front convenience
    _test("nsga2_get_pareto_front", _test_get_pareto_front)

    # Hypervolume
    _test("nsga2_hypervolume_simple", _test_hypervolume_simple)
    _test("nsga2_hypervolume_empty", _test_hypervolume_empty)
    _test("nsga2_hypervolume_two_points", _test_hypervolume_two_points)

    # Integration tests: NSGA-II with evolution.gd
    _test("evolution_nsga2_set_objectives", _test_evolution_nsga2_set_objectives)
    _test("evolution_nsga2_evolve_increments_gen", _test_evolution_nsga2_evolve_increments_gen)
    _test("evolution_nsga2_preserves_elites_from_front0", _test_evolution_nsga2_preserves_elites)
    _test("evolution_nsga2_tracks_best_network", _test_evolution_nsga2_tracks_best)
    _test("evolution_nsga2_resets_scores_after_evolve", _test_evolution_nsga2_resets_scores)
    _test("evolution_nsga2_pareto_front_populated", _test_evolution_nsga2_pareto_front)
    _test("evolution_nsga2_hypervolume_tracked", _test_evolution_nsga2_hypervolume)
    _test("evolution_nsga2_stats_include_nsga2_fields", _test_evolution_nsga2_stats)
    _test("evolution_nsga2_multiple_generations", _test_evolution_nsga2_multi_gen)
    _test("evolution_nsga2_all_equal_objectives", _test_evolution_nsga2_all_equal)
    _test("evolution_nsga2_single_dominant_individual", _test_evolution_nsga2_single_dominant)


# ============================================================
# DOMINANCE
# ============================================================


func _test_dominates_clear() -> void:
    # A beats B on all objectives
    var a := Vector3(10, 10, 10)
    var b := Vector3(5, 5, 5)
    assert_true(NSGA2Script.dominates(a, b), "A should dominate B")
    assert_false(NSGA2Script.dominates(b, a), "B should not dominate A")


func _test_dominates_equal() -> void:
    # Equal on all — no domination
    var a := Vector3(5, 5, 5)
    assert_false(NSGA2Script.dominates(a, a), "Equal solutions should not dominate each other")


func _test_dominates_partial() -> void:
    # A better on some, B better on others — neither dominates
    var a := Vector3(10, 5, 3)
    var b := Vector3(5, 10, 3)
    assert_false(NSGA2Script.dominates(a, b), "A should not dominate B (trade-off)")
    assert_false(NSGA2Script.dominates(b, a), "B should not dominate A (trade-off)")


func _test_dominates_reflexive() -> void:
    # A equals B on two, strictly better on one — A dominates B
    var a := Vector3(10, 5, 5)
    var b := Vector3(10, 5, 3)
    assert_true(NSGA2Script.dominates(a, b), "A should dominate B (equal on 2, better on 1)")
    assert_false(NSGA2Script.dominates(b, a), "B should not dominate A")


# ============================================================
# NON-DOMINATED SORT
# ============================================================


func _test_sort_single() -> void:
    var objectives := [Vector3(5, 5, 5)]
    var fronts := NSGA2Script.non_dominated_sort(objectives)
    assert_eq(fronts.size(), 1, "Single individual = 1 front")
    assert_eq(fronts[0].size(), 1, "Front 0 should have 1 individual")
    assert_eq(fronts[0][0], 0, "Individual 0 should be in front 0")


func _test_sort_clear_dominance() -> void:
    # Individual 0 dominates individual 1
    var objectives := [Vector3(10, 10, 10), Vector3(5, 5, 5)]
    var fronts := NSGA2Script.non_dominated_sort(objectives)
    assert_eq(fronts.size(), 2, "Should have 2 fronts")
    assert_true(0 in fronts[0], "Individual 0 should be in front 0")
    assert_true(1 in fronts[1], "Individual 1 should be in front 1")


func _test_sort_all_nondominated() -> void:
    # Trade-offs — all on front 0
    var objectives := [
        Vector3(10, 5, 3),
        Vector3(5, 10, 3),
        Vector3(3, 3, 10),
    ]
    var fronts := NSGA2Script.non_dominated_sort(objectives)
    assert_eq(fronts.size(), 1, "All non-dominated = 1 front")
    assert_eq(fronts[0].size(), 3, "All 3 should be in front 0")


func _test_sort_all_equal() -> void:
    # All identical — all on front 0 (no one dominates anyone)
    var objectives := [Vector3(5, 5, 5), Vector3(5, 5, 5), Vector3(5, 5, 5)]
    var fronts := NSGA2Script.non_dominated_sort(objectives)
    assert_eq(fronts.size(), 1, "All equal = 1 front")
    assert_eq(fronts[0].size(), 3, "All 3 in front 0")


func _test_sort_mixed_fronts() -> void:
    # 5 individuals with known structure:
    # 0: (10,10,10) — dominates 2,3,4
    # 1: (9,11,9)   — dominates 2,3,4
    # 2: (5,5,5)    — dominates 3,4
    # 3: (3,3,3)    — dominates 4
    # 4: (1,1,1)    — dominated by all
    var objectives := [
        Vector3(10, 10, 10),
        Vector3(9, 11, 9),
        Vector3(5, 5, 5),
        Vector3(3, 3, 3),
        Vector3(1, 1, 1),
    ]
    var fronts := NSGA2Script.non_dominated_sort(objectives)
    assert_eq(fronts.size(), 4, "Should have 4 fronts")
    # Front 0: 0 and 1 (non-dominated pair)
    assert_true(0 in fronts[0], "0 in front 0")
    assert_true(1 in fronts[0], "1 in front 0")
    # Front 1: 2
    assert_true(2 in fronts[1], "2 in front 1")
    # Front 2: 3
    assert_true(3 in fronts[2], "3 in front 2")
    # Front 3: 4
    assert_true(4 in fronts[3], "4 in front 3")


func _test_sort_covers_all() -> void:
    # Generate 20 random objectives, verify all indices appear exactly once across fronts
    var objectives: Array = []
    var rng := RandomNumberGenerator.new()
    rng.seed = 42
    for i in 20:
        objectives.append(Vector3(rng.randf() * 100, rng.randf() * 100, rng.randf() * 100))

    var fronts := NSGA2Script.non_dominated_sort(objectives)

    var all_indices: Array = []
    for front in fronts:
        all_indices.append_array(front)

    all_indices.sort()
    assert_eq(all_indices.size(), 20, "All 20 individuals should appear")
    for i in 20:
        assert_eq(all_indices[i], i, "Individual %d should appear exactly once" % i)


# ============================================================
# CROWDING DISTANCE
# ============================================================


func _test_crowding_small() -> void:
    # Front with 1 or 2 members — all should be INF
    var objectives := [Vector3(10, 5, 3), Vector3(5, 10, 7)]
    var front := [0, 1]
    var dist := NSGA2Script.crowding_distance(front, objectives)
    assert_eq(dist.size(), 2, "Should have 2 distances")
    assert_eq(dist[0], INF, "Member 0 should have INF distance")
    assert_eq(dist[1], INF, "Member 1 should have INF distance")


func _test_crowding_boundaries() -> void:
    # Front with 4 members — boundary individuals should have INF
    var objectives := [
        Vector3(1, 10, 5),
        Vector3(4, 7, 5),
        Vector3(7, 4, 5),
        Vector3(10, 1, 5),
    ]
    var front := [0, 1, 2, 3]
    var dist := NSGA2Script.crowding_distance(front, objectives)

    # In at least one objective, indices 0 and 3 are at the extremes
    # Both should have INF
    assert_eq(dist[0], INF, "Boundary member 0 should have INF")
    assert_eq(dist[3], INF, "Boundary member 3 should have INF")


func _test_crowding_interior() -> void:
    # Interior members should have finite, positive distances
    var objectives := [
        Vector3(1, 10, 5),
        Vector3(4, 7, 5),
        Vector3(7, 4, 5),
        Vector3(10, 1, 5),
    ]
    var front := [0, 1, 2, 3]
    var dist := NSGA2Script.crowding_distance(front, objectives)

    # Interior members (1, 2) should have finite positive distance
    assert_true(
        dist[1] > 0.0 and dist[1] < INF, "Interior member 1 should have finite positive distance"
    )
    assert_true(
        dist[2] > 0.0 and dist[2] < INF, "Interior member 2 should have finite positive distance"
    )


func _test_crowding_identical() -> void:
    # All identical objectives — distances should not cause errors
    var objectives := [Vector3(5, 5, 5), Vector3(5, 5, 5), Vector3(5, 5, 5)]
    var front := [0, 1, 2]
    var dist := NSGA2Script.crowding_distance(front, objectives)
    assert_eq(dist.size(), 3, "Should return 3 distances")
    # Boundaries still INF, interior 0 (no spread)
    assert_eq(dist[0], INF, "Boundary INF even when identical")
    assert_eq(dist[2], INF, "Boundary INF even when identical")


# ============================================================
# SELECTION
# ============================================================


func _test_select_all_fit() -> void:
    # Request more than population — should return all
    var objectives := [Vector3(1, 1, 1), Vector3(2, 2, 2)]
    var selected := NSGA2Script.select(objectives, 5)
    assert_eq(selected.size(), 2, "Should return all individuals")


func _test_select_half() -> void:
    # Select half the population
    var objectives: Array = []
    for i in 10:
        objectives.append(Vector3(i, 10 - i, 5))
    var selected := NSGA2Script.select(objectives, 5)
    assert_eq(selected.size(), 5, "Should select exactly 5")

    # All selected indices should be valid
    for idx in selected:
        assert_true(idx >= 0 and idx < 10, "Index %d should be valid" % idx)


func _test_select_prefers_front0() -> void:
    # 3 in front 0 (trade-offs), 3 clearly dominated — selecting 3 should give front 0
    var objectives := [
        Vector3(10, 1, 5),  # Front 0
        Vector3(1, 10, 5),  # Front 0
        Vector3(5, 5, 10),  # Front 0
        Vector3(1, 1, 1),  # Front 1
        Vector3(0, 0, 0),  # Front 2
        Vector3(0, 0, 0),  # Front 2
    ]
    var selected := NSGA2Script.select(objectives, 3)
    assert_eq(selected.size(), 3, "Should select 3")

    # All front 0 members should be selected
    for idx in selected:
        assert_true(idx in [0, 1, 2], "Selected %d should be from front 0" % idx)


func _test_select_diverse_within_front() -> void:
    # 5 on front 0, select 3 — should prefer diverse (boundary + spread)
    var objectives := [
        Vector3(10, 1, 5),  # Extreme in x
        Vector3(8, 2, 5),  # Interior, close to 0
        Vector3(5, 5, 5),  # Middle
        Vector3(2, 8, 5),  # Interior, close to 4
        Vector3(1, 10, 5),  # Extreme in y
    ]
    var selected := NSGA2Script.select(objectives, 3)
    assert_eq(selected.size(), 3, "Should select 3")

    # Boundary individuals (0 and 4) should always be selected (INF crowding)
    assert_true(0 in selected, "Boundary individual 0 should be selected")
    assert_true(4 in selected, "Boundary individual 4 should be selected")


# ============================================================
# TOURNAMENT
# ============================================================


func _test_tournament_rank() -> void:
    # Set up: 2 fronts, tournament should prefer front 0
    var objectives := [
        Vector3(10, 10, 10),  # Front 0
        Vector3(1, 1, 1),  # Front 1
    ]
    var fronts := NSGA2Script.non_dominated_sort(objectives)
    var crowding := {0: 1.0, 1: 1.0}

    # Run many tournaments — front 0 individual should win more often
    var wins := [0, 0]
    var rng := RandomNumberGenerator.new()
    rng.seed = 123
    for i in 100:
        var winner := NSGA2Script.tournament_select(objectives, fronts, crowding, rng)
        wins[winner] += 1

    assert_gt(float(wins[0]), float(wins[1]), "Front 0 individual should win more tournaments")


# ============================================================
# PARETO FRONT
# ============================================================


func _test_get_pareto_front() -> void:
    var objectives := [
        Vector3(10, 1, 5),
        Vector3(1, 10, 5),
        Vector3(1, 1, 1),  # Dominated by both 0 and 1
    ]
    var pf := NSGA2Script.get_pareto_front(objectives)
    assert_eq(pf.size(), 2, "Pareto front should have 2 members")

    var indices: Array = []
    for entry in pf:
        indices.append(entry.index)
    indices.sort()
    assert_eq(indices[0], 0, "Index 0 should be on Pareto front")
    assert_eq(indices[1], 1, "Index 1 should be on Pareto front")


# ============================================================
# HYPERVOLUME
# ============================================================


func _test_hypervolume_simple() -> void:
    # Single point (10, 10) with ref (0, 0) — hypervolume = 100
    var front := [Vector2(10, 10)]
    var hv := NSGA2Script.hypervolume_2d(front, Vector2(0, 0))
    assert_approx(hv, 100.0, 0.01, "Single point hypervolume should be 100")


func _test_hypervolume_empty() -> void:
    var front: Array = []
    var hv := NSGA2Script.hypervolume_2d(front, Vector2(0, 0))
    assert_approx(hv, 0.0, 0.01, "Empty front hypervolume should be 0")


func _test_hypervolume_two_points() -> void:
    # Two points: (10,5) and (5,10) with ref (0,0)
    # HV = 10*5 + 5*(10-5) = 50 + 25 = 75
    var front := [Vector2(10, 5), Vector2(5, 10)]
    var hv := NSGA2Script.hypervolume_2d(front, Vector2(0, 0))
    assert_approx(hv, 75.0, 0.01, "Two-point hypervolume should be 75")


# ============================================================
# INTEGRATION: Evolution + NSGA-II
# ============================================================

const Evolution = preload("res://ai/evolution.gd")


func _create_nsga2_evo(pop_size: int = 10) -> RefCounted:
    var evo = Evolution.new(pop_size, 5, 3, 2)
    evo.use_nsga2 = true
    return evo


func _test_evolution_nsga2_set_objectives() -> void:
    var evo = _create_nsga2_evo()
    evo.set_objectives(0, Vector3(10, 20, 30))
    assert_eq(evo.objective_scores[0], Vector3(10, 20, 30))
    # Scalar fitness should be sum
    assert_approx(evo.fitness_scores[0], 60.0, 0.001)


func _test_evolution_nsga2_evolve_increments_gen() -> void:
    var evo = _create_nsga2_evo()
    for i in 10:
        evo.set_objectives(i, Vector3(float(i), float(10 - i), 5.0))
    evo.evolve()
    assert_eq(evo.generation, 1)


func _test_evolution_nsga2_preserves_elites() -> void:
    var evo = _create_nsga2_evo()
    # Individual 0 dominates all others on all objectives
    evo.set_objectives(0, Vector3(100, 100, 100))
    for i in range(1, 10):
        evo.set_objectives(i, Vector3(float(i), float(i), float(i)))

    var elite_weights: PackedFloat32Array = evo.get_individual(0).get_weights()
    evo.evolve()

    # The dominant individual should be preserved as an elite
    var found_elite := false
    for i in evo.elite_count:
        var w: PackedFloat32Array = evo.get_individual(i).get_weights()
        var weights_match := true
        for j in w.size():
            if abs(w[j] - elite_weights[j]) > 0.0001:
                weights_match = false
                break
        if weights_match:
            found_elite = true
            break
    assert_true(found_elite, "Dominant individual should be preserved as elite")


func _test_evolution_nsga2_tracks_best() -> void:
    var evo = _create_nsga2_evo()
    evo.set_objectives(0, Vector3(50, 30, 20))  # sum = 100
    for i in range(1, 10):
        evo.set_objectives(i, Vector3(1, 1, 1))  # sum = 3
    evo.evolve()
    assert_approx(evo.best_fitness, 100.0, 0.001)
    assert_not_null(evo.best_network)
    assert_approx(evo.all_time_best_fitness, 100.0, 0.001)


func _test_evolution_nsga2_resets_scores() -> void:
    var evo = _create_nsga2_evo()
    for i in 10:
        evo.set_objectives(i, Vector3(float(i), float(i), float(i)))
    evo.evolve()
    for i in 10:
        assert_approx(evo.fitness_scores[i], 0.0, 0.001)
        assert_eq(evo.objective_scores[i], Vector3.ZERO)


func _test_evolution_nsga2_pareto_front() -> void:
    var evo = _create_nsga2_evo()
    # 3 non-dominated, rest dominated
    evo.set_objectives(0, Vector3(10, 1, 1))
    evo.set_objectives(1, Vector3(1, 10, 1))
    evo.set_objectives(2, Vector3(1, 1, 10))
    for i in range(3, 10):
        evo.set_objectives(i, Vector3(0.5, 0.5, 0.5))
    evo.evolve()
    assert_eq(evo.pareto_front.size(), 3, "Pareto front should have 3 non-dominated")


func _test_evolution_nsga2_hypervolume() -> void:
    var evo = _create_nsga2_evo()
    for i in 10:
        evo.set_objectives(i, Vector3(float(i + 1) * 10, float(i + 1) * 5, 1.0))
    evo.evolve()
    assert_gt(evo.last_hypervolume, 0.0, "Hypervolume should be positive")


func _test_evolution_nsga2_stats() -> void:
    var evo = _create_nsga2_evo()
    for i in 10:
        evo.set_objectives(i, Vector3(float(i), float(10 - i), 5.0))
    evo.evolve()
    var stats: Dictionary = evo.get_stats()
    assert_true(stats.has("pareto_front_size"), "Stats should include pareto_front_size")
    assert_true(stats.has("hypervolume"), "Stats should include hypervolume")
    assert_true(stats.has("num_fronts"), "Stats should include num_fronts")


func _test_evolution_nsga2_multi_gen() -> void:
    var evo = _create_nsga2_evo()
    # Run 3 generations
    for gen in 3:
        for i in 10:
            evo.set_objectives(i, Vector3(randf() * 100, randf() * 100, randf() * 100))
        evo.evolve()
    assert_eq(evo.generation, 3)
    assert_eq(evo.population.size(), 10)


func _test_evolution_nsga2_all_equal() -> void:
    var evo = _create_nsga2_evo()
    for i in 10:
        evo.set_objectives(i, Vector3(50, 50, 50))
    # Should not crash
    evo.evolve()
    assert_eq(evo.generation, 1)
    assert_eq(evo.population.size(), 10)


func _test_evolution_nsga2_single_dominant() -> void:
    var evo = _create_nsga2_evo()
    # One individual dominates all
    evo.set_objectives(0, Vector3(100, 100, 100))
    for i in range(1, 10):
        evo.set_objectives(i, Vector3(1, 1, 1))
    evo.evolve()
    assert_eq(evo.pareto_front.size(), 1, "Only 1 individual on Pareto front")
    assert_approx(evo.best_fitness, 300.0, 0.001)
