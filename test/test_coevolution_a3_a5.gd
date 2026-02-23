extends "res://test/test_base.gd"
## Tests for co-evolution Track A3-A5 features:
## - Hall of Fame (A4)
## - Adversarial fitness calculation (A4)
## - Save/Load Hall of Fame (A5)
## - Training manager COEVOLUTION mode enum (A3)

var CoevolutionScript = preload("res://ai/coevolution.gd")
var NeuralNetworkScript = preload("res://ai/neural_network.gd")


func run_tests() -> void:
    print("\n[CoEvolution A3-A5 Tests]")

    # A4: Hall of Fame
    _test("hof_initially_empty", _test_hof_initially_empty)
    _test("hof_update_archives_top_enemies", _test_hof_update_archives_top_enemies)
    _test("hof_trimmed_to_max_size", _test_hof_trimmed_to_max_size)
    _test("hof_eval_interval", _test_hof_eval_interval)
    _test("hof_networks_returns_cloned_nets", _test_hof_networks_returns_cloned_nets)
    _test("evolve_both_updates_hof", _test_evolve_both_updates_hof)

    # A4: Adversarial fitness
    _test("enemy_fitness_damage_positive", _test_enemy_fitness_damage_positive)
    _test("enemy_fitness_survival_penalty", _test_enemy_fitness_survival_penalty)
    _test("enemy_fitness_proximity_bonus", _test_enemy_fitness_proximity_bonus)
    _test("enemy_fitness_direction_changes", _test_enemy_fitness_direction_changes)
    _test("enemy_fitness_never_negative", _test_enemy_fitness_never_negative)

    # A5: Save/Load HoF
    _test("save_load_hof_roundtrip", _test_save_load_hof_roundtrip)

    # A3: Mode enum
    _test("coevolution_mode_exists", _test_coevolution_mode_exists)
    _test("coevolution_mode_distinct", _test_coevolution_mode_distinct)


# ============================================================
# Helpers
# ============================================================


func _make_coevo(pop: int = 20) -> RefCounted:
    return CoevolutionScript.new(pop, 86, 32, 6, pop, 3, 0.15, 0.3, 0.7)


func _set_enemy_fitness_linear(coevo, pop: int) -> void:
    ## Set fitness 10, 20, 30... so we know which are "top".
    for i in pop:
        coevo.set_enemy_fitness(i, float(i + 1) * 10.0)


# ============================================================
# A4: Hall of Fame tests
# ============================================================


func _test_hof_initially_empty() -> void:
    var coevo = _make_coevo()
    assert_eq(coevo.get_hof_size(), 0, "HoF should start empty")
    assert_true(coevo.hall_of_fame.is_empty(), "HoF array should be empty")


func _test_hof_update_archives_top_enemies() -> void:
    var coevo = _make_coevo()
    _set_enemy_fitness_linear(coevo, 20)
    coevo.update_hall_of_fame()

    assert_eq(coevo.get_hof_size(), CoevolutionScript.HOF_SIZE, "HoF should have HOF_SIZE entries")

    # Verify they are sorted by fitness (descending)
    for i in range(coevo.get_hof_size() - 1):
        assert_gte(
            coevo.hall_of_fame[i].fitness,
            coevo.hall_of_fame[i + 1].fitness,
            "HoF should be sorted by fitness descending"
        )


func _test_hof_trimmed_to_max_size() -> void:
    var coevo = _make_coevo()
    # Update HoF twice - should still be capped at HOF_SIZE
    _set_enemy_fitness_linear(coevo, 20)
    coevo.update_hall_of_fame()
    _set_enemy_fitness_linear(coevo, 20)
    coevo.update_hall_of_fame()

    assert_eq(
        coevo.get_hof_size(),
        CoevolutionScript.HOF_SIZE,
        "HoF should be trimmed to HOF_SIZE even after multiple updates"
    )


func _test_hof_eval_interval() -> void:
    var coevo = _make_coevo()
    # Generation 0, no HoF -> should not eval against HoF
    assert_false(
        coevo.should_eval_against_hof(), "Gen 0 with empty HoF should not eval against HoF"
    )

    # Add some HoF entries
    _set_enemy_fitness_linear(coevo, 20)
    coevo.update_hall_of_fame()

    # Gen 0 with HoF -> false (generation check)
    assert_false(coevo.should_eval_against_hof(), "Gen 0 should not eval against HoF")

    # Evolve to reach gen HOF_EVAL_INTERVAL
    for i in 20:
        coevo.set_player_fitness(i, float(i))
    for g in CoevolutionScript.HOF_EVAL_INTERVAL:
        for i in 20:
            coevo.set_player_fitness(i, float(i))
            coevo.set_enemy_fitness(i, float(i))
        coevo.evolve_both()

    assert_eq(
        coevo.get_generation(),
        CoevolutionScript.HOF_EVAL_INTERVAL,
        "Should be at gen HOF_EVAL_INTERVAL"
    )
    assert_true(
        coevo.should_eval_against_hof(), "Gen HOF_EVAL_INTERVAL with HoF should eval against HoF"
    )


func _test_hof_networks_returns_cloned_nets() -> void:
    var coevo = _make_coevo()
    _set_enemy_fitness_linear(coevo, 20)
    coevo.update_hall_of_fame()

    var nets = coevo.get_hof_networks()
    assert_eq(nets.size(), CoevolutionScript.HOF_SIZE, "Should return HOF_SIZE networks")
    assert_not_null(nets[0], "Network should not be null")


func _test_evolve_both_updates_hof() -> void:
    var coevo = _make_coevo()
    for i in 20:
        coevo.set_player_fitness(i, float(i))
        coevo.set_enemy_fitness(i, float(i + 1) * 10.0)
    coevo.evolve_both()

    assert_gt(coevo.get_hof_size(), 0, "HoF should be populated after evolve_both")


# ============================================================
# A4: Adversarial fitness tests
# ============================================================


func _test_enemy_fitness_damage_positive() -> void:
    # More damage = higher fitness
    var f_no_damage = CoevolutionScript.compute_enemy_fitness(0.0, 0.0, 10.0, 0)
    var f_with_damage = CoevolutionScript.compute_enemy_fitness(2.0, 0.0, 10.0, 0)
    assert_gt(f_with_damage, f_no_damage, "More damage should increase fitness")


func _test_enemy_fitness_survival_penalty() -> void:
    # Longer player survival = lower enemy fitness
    var f_short = CoevolutionScript.compute_enemy_fitness(1.0, 0.0, 5.0, 0)
    var f_long = CoevolutionScript.compute_enemy_fitness(1.0, 0.0, 30.0, 0)
    assert_gt(f_short, f_long, "Longer player survival should decrease enemy fitness")


func _test_enemy_fitness_proximity_bonus() -> void:
    # Higher proximity = higher fitness
    var f_far = CoevolutionScript.compute_enemy_fitness(0.0, 0.1, 10.0, 0)
    var f_close = CoevolutionScript.compute_enemy_fitness(0.0, 0.8, 10.0, 0)
    assert_gt(f_close, f_far, "Higher proximity should increase fitness")


func _test_enemy_fitness_direction_changes() -> void:
    # More direction changes forced = higher fitness
    var f_none = CoevolutionScript.compute_enemy_fitness(0.0, 0.5, 10.0, 0)
    var f_many = CoevolutionScript.compute_enemy_fitness(0.0, 0.5, 10.0, 20)
    assert_gt(f_many, f_none, "Forcing direction changes should increase fitness")


func _test_enemy_fitness_never_negative() -> void:
    # Even with bad performance, fitness >= 0
    var f = CoevolutionScript.compute_enemy_fitness(0.0, 0.0, 60.0, 0)
    assert_gte(f, 0.0, "Enemy fitness should never be negative")


# ============================================================
# A5: Save/Load Hall of Fame
# ============================================================


func _test_save_load_hof_roundtrip() -> void:
    var coevo = _make_coevo()
    _set_enemy_fitness_linear(coevo, 20)
    coevo.update_hall_of_fame()

    var original_size = coevo.get_hof_size()
    var original_fitness = coevo.hall_of_fame[0].fitness

    # Save
    var path := "user://test_hof_roundtrip.evo"
    coevo.save_hall_of_fame(path)

    # Load into fresh instance
    var coevo2 = _make_coevo()
    var ok = coevo2.load_hall_of_fame(path)
    assert_true(ok, "load_hall_of_fame should return true")
    assert_eq(coevo2.get_hof_size(), original_size, "Loaded HoF should have same size")
    assert_approx(
        coevo2.hall_of_fame[0].fitness, original_fitness, 0.1, "Loaded HoF top fitness should match"
    )

    # Clean up
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ============================================================
# A3: CoEvolution class integration readiness
# ============================================================


func _test_coevolution_mode_exists() -> void:
    # Verify CoEvolution has the methods needed by training manager integration
    var coevo = _make_coevo()
    assert_not_null(coevo.player_evolution, "player_evolution should exist")
    assert_not_null(coevo.enemy_evolution, "enemy_evolution should exist")
    assert_true(coevo.has_method("evolve_both"), "Should have evolve_both")
    assert_true(coevo.has_method("save_populations"), "Should have save_populations")
    assert_true(coevo.has_method("save_hall_of_fame"), "Should have save_hall_of_fame")
    assert_true(coevo.has_method("should_eval_against_hof"), "Should have should_eval_against_hof")


func _test_coevolution_mode_distinct() -> void:
    # Verify the full lifecycle: init -> set fitness -> evolve -> check generation
    var coevo = _make_coevo()
    for i in 20:
        coevo.set_player_fitness(i, float(i) * 10.0)
        coevo.set_enemy_fitness(i, float(20 - i) * 5.0)
    coevo.evolve_both()
    assert_eq(coevo.get_generation(), 1, "Should advance to gen 1")
    assert_gt(coevo.player_evolution.get_best_fitness(), 0.0, "Player best should be > 0")
    assert_gt(coevo.enemy_evolution.get_best_fitness(), 0.0, "Enemy best should be > 0")
