extends "res://test/test_base.gd"

## Tests for NEAT speciation system.

var config: NeatConfig
var tracker: NeatInnovation


func _setup() -> void:
    config = NeatConfig.new()
    config.input_count = 3
    config.output_count = 2
    config.use_bias = false
    config.allow_recurrent = false
    config.compatibility_threshold = 3.0
    config.target_species_count = 4
    config.threshold_step = 0.3
    tracker = NeatInnovation.new()


func _run_tests() -> void:
    _test("species_creation", test_creation)
    _test("species_add_member", test_add_member)
    _test("species_clear_members", test_clear_members)
    _test("species_adjusted_fitness", test_adjusted_fitness)
    _test("species_best_genome", test_best_genome)
    _test("species_stagnation_tracking", test_stagnation)
    _test("species_sorted_members", test_sorted_members)
    _test("speciate_identical_genomes", test_speciate_identical)
    _test("speciate_different_genomes", test_speciate_different)
    _test("speciate_removes_empty", test_speciate_removes_empty)
    _test("speciate_preserves_across_generations", test_speciate_across_gens)
    _test("threshold_adjustment_too_few", test_threshold_too_few)
    _test("threshold_adjustment_too_many", test_threshold_too_many)
    _test("threshold_clamp_minimum", test_threshold_clamp)


func test_creation() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    var species := NeatSpecies.new(0, genome)
    assert_eq(species.id, 0)
    assert_eq(species.members.size(), 1)
    assert_eq(species.generations_without_improvement, 0)


func test_add_member() -> void:
    _setup()
    var g1 := NeatGenome.create(config, tracker)
    var species := NeatSpecies.new(0, g1)
    var g2 := NeatGenome.create(config, tracker)
    species.add_member(g2)
    assert_eq(species.members.size(), 2)


func test_clear_members() -> void:
    _setup()
    var g1 := NeatGenome.create(config, tracker)
    var species := NeatSpecies.new(0, g1)
    species.add_member(NeatGenome.create(config, tracker))
    species.add_member(NeatGenome.create(config, tracker))
    assert_eq(species.members.size(), 3)
    species.clear_members()
    assert_eq(species.members.size(), 0)
    # Representative should still exist
    assert_not_null(species.representative)


func test_adjusted_fitness() -> void:
    _setup()
    var g1 := NeatGenome.create(config, tracker)
    g1.fitness = 10.0
    var g2 := NeatGenome.create(config, tracker)
    g2.fitness = 20.0
    var species := NeatSpecies.new(0, g1)
    species.add_member(g2)
    species.calculate_adjusted_fitness()
    # 2 members: fitness / 2
    assert_approx(g1.adjusted_fitness, 5.0)
    assert_approx(g2.adjusted_fitness, 10.0)


func test_best_genome() -> void:
    _setup()
    var g1 := NeatGenome.create(config, tracker)
    g1.fitness = 5.0
    var g2 := NeatGenome.create(config, tracker)
    g2.fitness = 15.0
    var g3 := NeatGenome.create(config, tracker)
    g3.fitness = 10.0
    var species := NeatSpecies.new(0, g1)
    species.add_member(g2)
    species.add_member(g3)
    var best := species.get_best_genome()
    assert_approx(best.fitness, 15.0)


func test_stagnation() -> void:
    _setup()
    var g1 := NeatGenome.create(config, tracker)
    g1.fitness = 10.0
    var species := NeatSpecies.new(0, g1)

    # First update: sets best
    species.update_best_fitness()
    assert_eq(species.generations_without_improvement, 0)
    assert_approx(species.best_fitness_ever, 10.0)

    # Same fitness again: stagnation++
    species.update_best_fitness()
    assert_eq(species.generations_without_improvement, 1)

    # Better fitness: reset stagnation
    g1.fitness = 20.0
    species.update_best_fitness()
    assert_eq(species.generations_without_improvement, 0)
    assert_approx(species.best_fitness_ever, 20.0)

    # Check stagnation flag
    assert_false(species.is_stagnant(15))
    for i in 16:
        species.update_best_fitness()
    assert_true(species.is_stagnant(15))


func test_sorted_members() -> void:
    _setup()
    var g1 := NeatGenome.create(config, tracker)
    g1.fitness = 5.0
    var g2 := NeatGenome.create(config, tracker)
    g2.fitness = 15.0
    var g3 := NeatGenome.create(config, tracker)
    g3.fitness = 10.0
    var species := NeatSpecies.new(0, g1)
    species.add_member(g2)
    species.add_member(g3)
    var sorted := species.get_sorted_members()
    assert_approx(sorted[0].fitness, 15.0)
    assert_approx(sorted[1].fitness, 10.0)
    assert_approx(sorted[2].fitness, 5.0)


func test_speciate_identical() -> void:
    _setup()
    config.compatibility_threshold = 3.0
    var population: Array = []
    for i in 10:
        var g := NeatGenome.create(config, tracker)
        g.create_basic()
        population.append(g)

    var result: Dictionary = NeatSpecies.speciate(population, [], config, 0)
    # All identical genomes should be in 1 species
    assert_eq(result.species.size(), 1)
    assert_eq(result.species[0].members.size(), 10)


func test_speciate_different() -> void:
    _setup()
    config.compatibility_threshold = 0.1  # Very strict threshold

    var population: Array = []
    for i in 5:
        var g := NeatGenome.create(config, tracker)
        g.create_basic()
        # Add different topology to each
        for j in (i + 1) * 2:
            g.mutate_add_node()
            g.mutate_add_connection()
        population.append(g)

    var result: Dictionary = NeatSpecies.speciate(population, [], config, 0)
    # With very strict threshold and different topologies, should get multiple species
    assert_gt(result.species.size(), 1)


func test_speciate_removes_empty() -> void:
    _setup()
    # Create a species with no matching members this generation
    var old_genome := NeatGenome.create(config, tracker)
    old_genome.create_basic()
    # Mutate heavily so nothing matches
    for i in 20:
        old_genome.mutate_add_node()
        old_genome.mutate_add_connection()
    var old_species := NeatSpecies.new(0, old_genome)

    # New population of identical, unmutated genomes
    var population: Array = []
    for i in 5:
        var g := NeatGenome.create(config, tracker)
        g.create_basic()
        population.append(g)

    config.compatibility_threshold = 0.1  # Very strict
    var result: Dictionary = NeatSpecies.speciate(population, [old_species], config, 1)
    # Old species should have been removed (no members matched)
    for species in result.species:
        assert_gt(species.members.size(), 0)


func test_speciate_across_gens() -> void:
    _setup()
    config.compatibility_threshold = 5.0  # Loose threshold

    # Gen 1: create population and speciate
    var population: Array = []
    for i in 10:
        var g := NeatGenome.create(config, tracker)
        g.create_basic()
        population.append(g)
    var result: Dictionary = NeatSpecies.speciate(population, [], config, 0)
    var species_gen1: Array = result.species

    # Gen 2: slightly mutate and re-speciate
    var pop2: Array = []
    for genome in population:
        var child = genome.copy()
        child.mutate_weights()
        pop2.append(child)
    var result2: Dictionary = NeatSpecies.speciate(pop2, species_gen1, config, result.next_id)
    # Should still have species (mutations were small)
    assert_gt(result2.species.size(), 0)


func test_threshold_too_few() -> void:
    _setup()
    config.compatibility_threshold = 5.0
    config.target_species_count = 4
    config.threshold_step = 0.3
    # 2 species, target is 4 → should decrease threshold
    var species_list: Array = [
        NeatSpecies.new(0, NeatGenome.create(config, tracker)),
        NeatSpecies.new(1, NeatGenome.create(config, tracker)),
    ]
    NeatSpecies.adjust_compatibility_threshold(species_list, config)
    assert_approx(config.compatibility_threshold, 4.7, 0.01)


func test_threshold_too_many() -> void:
    _setup()
    config.compatibility_threshold = 3.0
    config.target_species_count = 2
    config.threshold_step = 0.3
    var species_list: Array = []
    for i in 5:
        species_list.append(NeatSpecies.new(i, NeatGenome.create(config, tracker)))
    NeatSpecies.adjust_compatibility_threshold(species_list, config)
    assert_approx(config.compatibility_threshold, 3.3, 0.01)


func test_threshold_clamp() -> void:
    _setup()
    config.compatibility_threshold = 0.4
    config.threshold_step = 0.5
    # Too few species → decrease, but clamp at 0.3
    var species_list: Array = [
        NeatSpecies.new(0, NeatGenome.create(config, tracker)),
    ]
    NeatSpecies.adjust_compatibility_threshold(species_list, config)
    assert_approx(config.compatibility_threshold, 0.3, 0.01)
