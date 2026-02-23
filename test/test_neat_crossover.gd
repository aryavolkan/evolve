extends "res://test/test_base.gd"

## Tests for NEAT crossover between genomes.

var config: NeatConfig
var tracker: NeatInnovation


func _setup() -> void:
    config = NeatConfig.new()
    config.input_count = 3
    config.output_count = 2
    config.use_bias = false
    config.allow_recurrent = false
    config.disabled_gene_inherit_rate = 0.75
    tracker = NeatInnovation.new()


func _run_tests() -> void:
    _test("crossover_produces_valid_genome", test_valid_genome)
    _test("crossover_preserves_io_nodes", test_preserves_io_nodes)
    _test("crossover_inherits_matching_genes", test_inherits_matching)
    _test("crossover_fitter_parent_disjoint", test_fitter_disjoint)
    _test("crossover_equal_fitness_both_disjoint", test_equal_fitness_disjoint)
    _test("crossover_child_has_correct_refs", test_child_refs)
    _test("crossover_identical_parents", test_identical_parents)
    _test("crossover_different_topology", test_different_topology)
    _test("crossover_disabled_gene_handling", test_disabled_gene)
    _test("crossover_child_independence", test_child_independence)


func test_valid_genome() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.fitness = 10.0
    var b := NeatGenome.create(config, tracker)
    b.create_basic()
    b.fitness = 5.0
    var child := NeatGenome.crossover(a, b)
    assert_gt(child.node_genes.size(), 0)
    assert_gt(child.connection_genes.size(), 0)


func test_preserves_io_nodes() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.fitness = 10.0
    var b := a.copy()
    b.fitness = 5.0
    var child := NeatGenome.crossover(a, b)
    var inputs: int = 0
    var outputs: int = 0
    for node in child.node_genes:
        if node.type == 0:
            inputs += 1
        elif node.type == 2:
            outputs += 1
    assert_eq(inputs, 3)
    assert_eq(outputs, 2)


func test_inherits_matching() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.fitness = 10.0
    var b := a.copy()
    b.fitness = 10.0
    # Both have same connections (matching genes)
    var child := NeatGenome.crossover(a, b)
    assert_eq(child.connection_genes.size(), a.connection_genes.size())


func test_fitter_disjoint() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.mutate_add_node()  # A has extra topology
    a.fitness = 100.0

    var b := NeatGenome.create(config, tracker)
    b.create_basic()
    b.fitness = 1.0

    var child := NeatGenome.crossover(a, b)
    # Child should have A's disjoint genes (the extra node connections)
    assert_gte(child.connection_genes.size(), b.connection_genes.size())


func test_equal_fitness_disjoint() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.mutate_add_node()
    a.fitness = 10.0

    var b := NeatGenome.create(config, tracker)
    b.create_basic()
    b.fitness = 10.0

    # With equal fitness, child may get disjoint from both
    var child := NeatGenome.crossover(a, b)
    assert_gte(child.connection_genes.size(), b.connection_genes.size())


func test_child_refs() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.fitness = 10.0
    var b := a.copy()
    b.fitness = 5.0
    var child := NeatGenome.crossover(a, b)
    assert_not_null(child.config)
    assert_not_null(child.innovation_tracker)


func test_identical_parents() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.fitness = 10.0
    var b := a.copy()
    b.fitness = 10.0
    var child := NeatGenome.crossover(a, b)
    assert_eq(child.connection_genes.size(), a.connection_genes.size())
    assert_eq(child.node_genes.size(), a.node_genes.size())


func test_different_topology() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.mutate_add_node()
    a.mutate_add_node()
    a.fitness = 50.0

    var b := NeatGenome.create(config, tracker)
    b.create_basic()
    b.fitness = 50.0

    var child := NeatGenome.crossover(a, b)
    # Should have hidden nodes from at least parent a (equal fitness = both disjoint)
    assert_gte(child.node_genes.size(), b.node_genes.size())


func test_disabled_gene() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.mutate_add_node()  # Disables one connection
    a.fitness = 10.0
    var b := a.copy()
    b.fitness = 10.0

    # Run many crossovers — disabled gene should sometimes be re-enabled
    var ever_enabled := false
    var ever_disabled := false
    for i in 50:
        var child := NeatGenome.crossover(a, b)
        for conn in child.connection_genes:
            if not conn.enabled:
                ever_disabled = true
            else:
                ever_enabled = true
    assert_true(ever_enabled, "Some genes should be enabled")
    # With disabled_gene_inherit_rate=0.75, most disabled stay disabled
    assert_true(ever_disabled, "Some genes should be disabled")


func test_child_independence() -> void:
    _setup()
    var a := NeatGenome.create(config, tracker)
    a.create_basic()
    a.fitness = 10.0
    var b := a.copy()
    b.fitness = 5.0
    var child := NeatGenome.crossover(a, b)
    # Mutating child should not affect parents
    if not child.connection_genes.is_empty():
        child.connection_genes[0].weight = 999.0
    assert_ne(a.connection_genes[0].weight, 999.0)
    assert_ne(b.connection_genes[0].weight, 999.0)
