extends "res://test/test_base.gd"
## Tests for ai/evolution.gd

const Evolution = preload("res://ai/evolution.gd")


func run_tests() -> void:
    print("\n[Evolution Tests]")

    _test("initialization_creates_population", _test_initialization_creates_population)
    _test("initialization_sets_parameters", _test_initialization_sets_parameters)
    _test("set_fitness_stores_value", _test_set_fitness_stores_value)
    _test("get_individual_returns_network", _test_get_individual_returns_network)
    _test("evolve_increments_generation", _test_evolve_increments_generation)
    _test("evolve_preserves_elites", _test_evolve_preserves_elites)
    _test("evolve_tracks_best_fitness", _test_evolve_tracks_best_fitness)
    _test("evolve_tracks_all_time_best", _test_evolve_tracks_all_time_best)
    _test(
        "tournament_selection_prefers_higher_fitness",
        _test_tournament_selection_prefers_higher_fitness
    )
    _test("evolve_resets_fitness_scores", _test_evolve_resets_fitness_scores)
    _test("backup_and_restore_works", _test_backup_and_restore_works)
    _test("save_load_population_roundtrip", _test_save_load_population_roundtrip)
    _test("get_stats_returns_valid_data", _test_get_stats_returns_valid_data)
    _test("save_best_and_load_best", _test_save_best_and_load_best)
    _test("load_population_rejects_size_mismatch", _test_load_population_rejects_size_mismatch)
    _test("evolve_handles_zero_fitness", _test_evolve_handles_zero_fitness)
    _test("evolve_handles_equal_fitness", _test_evolve_handles_equal_fitness)


# ============================================================
# Initialization Tests
# ============================================================


func _test_initialization_creates_population() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)  # 10 individuals
    assert_eq(evo.population.size(), 10, "Should create 10 networks")


func _test_initialization_sets_parameters() -> void:
    var evo = Evolution.new(20, 10, 5, 3, 3, 0.2, 0.4, 0.8)
    assert_eq(evo.population_size, 20)
    assert_eq(evo.input_size, 10)
    assert_eq(evo.hidden_size, 5)
    assert_eq(evo.output_size, 3)
    assert_eq(evo.elite_count, 3)
    assert_approx(evo.mutation_rate, 0.2)
    assert_approx(evo.mutation_strength, 0.4)
    assert_approx(evo.crossover_rate, 0.8)


# ============================================================
# Fitness Tests
# ============================================================


func _test_set_fitness_stores_value() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    evo.set_fitness(0, 100.0)
    evo.set_fitness(5, 50.0)
    assert_approx(evo.fitness_scores[0], 100.0)
    assert_approx(evo.fitness_scores[5], 50.0)


func _test_get_individual_returns_network() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    var net = evo.get_individual(0)
    assert_not_null(net)
    assert_eq(net.input_size, 5)
    assert_eq(net.hidden_size, 3)
    assert_eq(net.output_size, 2)


# ============================================================
# Evolution Tests
# ============================================================


func _test_evolve_increments_generation() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    assert_eq(evo.generation, 0)

    # Set some fitness values
    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)

    evo.evolve()
    assert_eq(evo.generation, 1)

    # Set fitness again and evolve
    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)

    evo.evolve()
    assert_eq(evo.generation, 2)


func _test_evolve_preserves_elites() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 2)  # 2 elites

    # Set fitness: indices 8 and 9 are best
    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)

    # Get weights of top performers before evolution
    var elite1_weights: PackedFloat32Array = evo.get_individual(9).get_weights()
    var elite2_weights: PackedFloat32Array = evo.get_individual(8).get_weights()

    evo.evolve()

    # Check that top 2 networks in new population have the elite weights
    # Elites should be at indices 0 and 1 after evolution
    var new_elite1: PackedFloat32Array = evo.get_individual(0).get_weights()
    var new_elite2: PackedFloat32Array = evo.get_individual(1).get_weights()

    var match_count := 0
    # Elite weights should match one of the top two spots
    for i in elite1_weights.size():
        if abs(new_elite1[i] - elite1_weights[i]) < 0.0001:
            match_count += 1
    assert_eq(match_count, elite1_weights.size(), "Best elite should be preserved exactly")


func _test_evolve_tracks_best_fitness() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)

    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)

    evo.evolve()

    assert_approx(evo.best_fitness, 90.0, 0.001, "Best fitness should be 90")
    assert_not_null(evo.best_network)


func _test_evolve_tracks_all_time_best() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)

    # First generation: max fitness 90
    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)
    evo.evolve()
    assert_approx(evo.all_time_best_fitness, 90.0, 0.001)

    # Second generation: lower max fitness 50
    for i in 10:
        evo.set_fitness(i, float(i) * 5.0)
    evo.evolve()

    # All-time best should still be 90
    assert_approx(evo.all_time_best_fitness, 90.0, 0.001, "All-time best should persist")


func _test_tournament_selection_prefers_higher_fitness() -> void:
    var evo = Evolution.new(100, 5, 3, 2)

    # Create a clear fitness gradient: top individuals have much higher fitness
    for i in 100:
        evo.set_fitness(i, float(100 - i))  # Index 0 has 100, index 99 has 1

    # Run many selections and track average fitness of selected individuals
    var total_fitness := 0.0
    var iterations := 100

    for _iter in iterations:
        var indexed_fitness: Array = []
        for i in 100:
            indexed_fitness.append({"index": i, "fitness": evo.fitness_scores[i]})

        var selected = evo.select_parent(indexed_fitness)
        # Find the fitness of the selected individual
        for i in 100:
            if evo.population[i] == selected:
                total_fitness += evo.fitness_scores[i]
                break

    var avg_selected_fitness = total_fitness / iterations
    var population_avg_fitness = 50.5  # Mean of 1 to 100

    # Tournament selection should select individuals with above-average fitness
    assert_gt(
        avg_selected_fitness,
        population_avg_fitness,
        "Tournament selection should prefer higher fitness"
    )


func _test_evolve_resets_fitness_scores() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)

    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)

    evo.evolve()

    # All fitness scores should be reset to 0
    for i in 10:
        assert_approx(evo.fitness_scores[i], 0.0, 0.001, "Fitness %d should be reset" % i)


# ============================================================
# Backup/Restore Tests
# ============================================================


func _test_backup_and_restore_works() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)

    # Get initial weights
    var original_weights: PackedFloat32Array = evo.get_individual(0).get_weights()

    # Set fitness and evolve
    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)
    evo.evolve()

    # Weights should be different now (due to crossover/mutation)
    var evolved_weights: PackedFloat32Array = evo.get_individual(0).get_weights()

    # Restore backup
    evo.restore_backup()

    # Weights should match original
    var restored_weights: PackedFloat32Array = evo.get_individual(0).get_weights()
    for i in original_weights.size():
        assert_approx(
            restored_weights[i], original_weights[i], 0.0001, "Weight %d should be restored" % i
        )


# ============================================================
# Persistence Tests
# ============================================================


func _test_save_load_population_roundtrip() -> void:
    var evo1 = Evolution.new(10, 5, 3, 2, 3)
    var test_path := "user://test_population.evo"

    # Set some fitness and evolve to create state
    for i in 10:
        evo1.set_fitness(i, float(i) * 10.0)
    evo1.evolve()

    # Save
    evo1.save_population(test_path)

    # Create new evolution with same params and load
    var evo2 = Evolution.new(10, 5, 3, 2, 3)
    var loaded := evo2.load_population(test_path)

    assert_true(loaded, "Should load successfully")
    assert_eq(evo2.generation, evo1.generation, "Generation should match")
    assert_approx(evo2.best_fitness, evo1.best_fitness, 0.001, "Best fitness should match")
    assert_approx(
        evo2.all_time_best_fitness, evo1.all_time_best_fitness, 0.001, "All-time best should match"
    )

    # Verify network weights match
    var weights1: PackedFloat32Array = evo1.get_individual(0).get_weights()
    var weights2: PackedFloat32Array = evo2.get_individual(0).get_weights()
    for i in weights1.size():
        assert_approx(weights1[i], weights2[i], 0.0001, "Weight %d should match" % i)

    # Cleanup
    DirAccess.remove_absolute(test_path)


# ============================================================
# Stats Tests
# ============================================================


func _test_get_stats_returns_valid_data() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)

    for i in 10:
        evo.set_fitness(i, float(i + 1) * 10.0)  # 10, 20, ..., 100

    var stats: Dictionary = evo.get_stats()

    assert_eq(stats.generation, 0)
    assert_eq(stats.population_size, 10)
    assert_approx(stats.current_min, 10.0, 0.001)
    assert_approx(stats.current_max, 100.0, 0.001)
    assert_approx(stats.current_avg, 55.0, 0.001)  # (10+20+...+100)/10 = 550/10 = 55


# ============================================================
# Best Network Persistence Tests
# ============================================================


func _test_save_best_and_load_best() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)
    var test_path := "user://test_best_network.nn"

    # Run evolution to establish a best network
    for i in 10:
        evo.set_fitness(i, float(i) * 10.0)
    evo.evolve()

    # Save best network
    evo.save_best(test_path)

    # Create new evolution and load
    var evo2 = Evolution.new(10, 5, 3, 2, 3)
    evo2.load_best(test_path)

    assert_not_null(evo2.all_time_best_network, "Should load best network")

    # Verify weights match
    var weights1: PackedFloat32Array = evo.all_time_best_network.get_weights()
    var weights2: PackedFloat32Array = evo2.all_time_best_network.get_weights()
    assert_eq(weights1.size(), weights2.size())
    for i in weights1.size():
        assert_approx(weights1[i], weights2[i], 0.0001, "Weight %d should match" % i)

    # Cleanup
    DirAccess.remove_absolute(test_path)


func _test_load_population_rejects_size_mismatch() -> void:
    var evo1 = Evolution.new(10, 5, 3, 2, 3)
    var test_path := "user://test_pop_mismatch.evo"

    for i in 10:
        evo1.set_fitness(i, float(i) * 10.0)
    evo1.evolve()
    evo1.save_population(test_path)

    # Try to load into evolution with different population size
    var evo2 = Evolution.new(20, 5, 3, 2, 3)  # Different size!
    var loaded := evo2.load_population(test_path)

    assert_false(loaded, "Should reject population size mismatch")

    # Cleanup
    DirAccess.remove_absolute(test_path)


# ============================================================
# Edge Case Fitness Tests
# ============================================================


func _test_evolve_handles_zero_fitness() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)

    # All individuals have zero fitness
    for i in 10:
        evo.set_fitness(i, 0.0)

    # Should not crash
    evo.evolve()

    assert_eq(evo.generation, 1, "Should complete evolution with zero fitness")
    assert_eq(evo.population.size(), 10, "Population size should remain constant")


func _test_evolve_handles_equal_fitness() -> void:
    var evo = Evolution.new(10, 5, 3, 2, 3)

    # All individuals have equal fitness
    for i in 10:
        evo.set_fitness(i, 50.0)

    evo.evolve()

    assert_eq(evo.generation, 1, "Should complete evolution with equal fitness")
    assert_approx(evo.best_fitness, 50.0, 0.001, "Best fitness should be 50")
