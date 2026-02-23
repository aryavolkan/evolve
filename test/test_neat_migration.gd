extends "res://test/test_base.gd"

## Tests for NEAT island model migration: genome serialization, inject_immigrant, migration I/O.

var config: NeatConfig
var tracker: NeatInnovation


func _setup() -> void:
    config = NeatConfig.new()
    config.input_count = 3
    config.output_count = 2
    config.use_bias = false
    config.allow_recurrent = false
    config.population_size = 10
    tracker = NeatInnovation.new()


func run_tests() -> void:
    _test("serialize_empty_genome", test_serialize_empty)
    _test("serialize_roundtrip_basic", test_serialize_roundtrip_basic)
    _test("serialize_roundtrip_mutated", test_serialize_roundtrip_mutated)
    _test("serialize_preserves_fitness", test_serialize_preserves_fitness)
    _test("serialize_preserves_disabled", test_serialize_preserves_disabled)
    _test("deserialize_invalid_data", test_deserialize_invalid)
    _test("inject_immigrant_replaces_worst", test_inject_replaces_worst)
    _test("inject_immigrant_empty_pop", test_inject_empty_pop)
    _test("save_best_roundtrip", test_save_best_roundtrip)
    _test("save_load_population", test_save_load_population)
    _test("save_load_preserves_generation", test_save_load_preserves_generation)


func test_serialize_empty() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    var data := genome.serialize()
    assert_eq(data.nodes.size(), 5)  # 3 inputs + 2 outputs
    assert_eq(data.connections.size(), 0)
    assert_true(data.has("fitness"))


func test_serialize_roundtrip_basic() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    genome.fitness = 42.5

    var data := genome.serialize()
    var restored := NeatGenome.deserialize(data, config, tracker)

    assert_eq(restored.node_genes.size(), genome.node_genes.size())
    assert_eq(restored.connection_genes.size(), genome.connection_genes.size())
    assert_approx(restored.fitness, 42.5)

    # Verify node IDs match
    for i in genome.node_genes.size():
        assert_eq(restored.node_genes[i].id, genome.node_genes[i].id)
        assert_eq(restored.node_genes[i].type, genome.node_genes[i].type)
        assert_approx(restored.node_genes[i].bias, genome.node_genes[i].bias)

    # Verify connections match
    for i in genome.connection_genes.size():
        assert_eq(restored.connection_genes[i].in_id, genome.connection_genes[i].in_id)
        assert_eq(restored.connection_genes[i].out_id, genome.connection_genes[i].out_id)
        assert_approx(restored.connection_genes[i].weight, genome.connection_genes[i].weight)
        assert_eq(restored.connection_genes[i].innovation, genome.connection_genes[i].innovation)
        assert_eq(restored.connection_genes[i].enabled, genome.connection_genes[i].enabled)


func test_serialize_roundtrip_mutated() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    # Add hidden nodes and extra connections
    genome.mutate_add_node()
    genome.mutate_add_node()
    genome.mutate_add_connection()

    var data := genome.serialize()
    var restored := NeatGenome.deserialize(data, config, tracker)

    assert_eq(restored.node_genes.size(), genome.node_genes.size())
    assert_eq(restored.connection_genes.size(), genome.connection_genes.size())

    # Check hidden nodes survived
    var orig_hidden := genome.node_genes.filter(func(n): return n.type == 1).size()
    var rest_hidden := restored.node_genes.filter(func(n): return n.type == 1).size()
    assert_eq(rest_hidden, orig_hidden)


func test_serialize_preserves_fitness() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.fitness = 12345.6
    var data := genome.serialize()
    var restored := NeatGenome.deserialize(data, config, tracker)
    assert_approx(restored.fitness, 12345.6, 0.1)


func test_serialize_preserves_disabled() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    genome.connection_genes[0].enabled = false

    var data := genome.serialize()
    var restored := NeatGenome.deserialize(data, config, tracker)
    assert_false(restored.connection_genes[0].enabled)
    assert_true(restored.connection_genes[1].enabled)


func test_deserialize_invalid() -> void:
    _setup()
    # Empty dict should produce empty genome without crashing
    var restored := NeatGenome.deserialize({}, config, tracker)
    assert_eq(restored.node_genes.size(), 0)
    assert_eq(restored.connection_genes.size(), 0)
    assert_approx(restored.fitness, 0.0)


func test_inject_replaces_worst() -> void:
    _setup()
    var evo := NeatEvolution.new(config)

    # Set ascending fitness values
    for i in config.population_size:
        evo.set_fitness(i, float(i) * 10.0)

    # Individual 0 has fitness 0 — should be replaced
    var immigrant := NeatGenome.create(config, tracker)
    immigrant.create_basic()
    immigrant.fitness = 999.0

    evo.inject_immigrant(immigrant)

    # Worst (0) should be replaced; immigrant should be in population
    var found := false
    for genome in evo.population:
        if genome.fitness == 999.0:
            found = true
            break
    assert_true(found, "Immigrant should be in population")

    # Original worst (0.0) should be gone
    var zero_found := false
    for genome in evo.population:
        if genome.fitness == 0.0:
            zero_found = true
            break
    assert_false(zero_found, "Original worst should be replaced")


func test_inject_empty_pop() -> void:
    _setup()
    var evo := NeatEvolution.new(config)
    evo.population.clear()

    var immigrant := NeatGenome.create(config, tracker)
    immigrant.fitness = 100.0

    # Should not crash on empty population
    evo.inject_immigrant(immigrant)
    assert_eq(evo.population.size(), 0)


func test_save_best_roundtrip() -> void:
    _setup()
    var evo := NeatEvolution.new(config)
    for i in config.population_size:
        evo.set_fitness(i, float(i) * 10.0)
    evo.evolve()

    var path := "user://test_best_genome.json"
    evo.save_best(path)

    # Read back and verify
    assert_true(FileAccess.file_exists(path), "Best genome file should exist")
    var file := FileAccess.open(path, FileAccess.READ)
    var json := JSON.new()
    assert_eq(json.parse(file.get_as_text()), OK, "File should be valid JSON")
    file.close()
    var data: Dictionary = json.data
    assert_true(data.has("nodes"), "Should have nodes")
    assert_true(data.has("connections"), "Should have connections")
    assert_true(data.has("fitness"), "Should have fitness")

    # Clean up
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_save_load_population() -> void:
    _setup()
    var evo := NeatEvolution.new(config)
    for i in config.population_size:
        evo.set_fitness(i, float(i) * 10.0)
    evo.evolve()

    var path := "user://test_population.json"
    evo.save_population(path)

    # Create a fresh evolution and load into it
    var evo2 := NeatEvolution.new(config)
    var success := evo2.load_population(path)
    assert_true(success, "load_population should return true")
    assert_eq(evo2.population.size(), config.population_size)
    assert_approx(evo2.all_time_best_fitness, evo.all_time_best_fitness, 0.1)

    # Clean up
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_save_load_preserves_generation() -> void:
    _setup()
    var evo := NeatEvolution.new(config)
    for i in config.population_size:
        evo.set_fitness(i, float(i))
    evo.evolve()
    evo.evolve()  # gen 2

    var path := "user://test_pop_gen.json"
    evo.save_population(path)

    var evo2 := NeatEvolution.new(config)
    evo2.load_population(path)
    assert_eq(evo2.generation, 2)

    # Clean up
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
