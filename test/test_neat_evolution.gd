extends "res://test/test_base.gd"

## Tests for NeatEvolution — the full NEAT evolution manager.

var config: NeatConfig


func _setup() -> void:
	config = NeatConfig.new()
	config.input_count = 3
	config.output_count = 2
	config.use_bias = false
	config.allow_recurrent = false
	config.population_size = 30
	config.elite_fraction = 0.1
	config.survival_fraction = 0.5
	config.crossover_rate = 0.75
	config.weight_mutate_rate = 0.8
	config.add_node_rate = 0.03
	config.add_connection_rate = 0.05
	config.compatibility_threshold = 3.0
	config.stagnation_threshold = 15
	config.stagnation_kill_threshold = 25
	config.min_species_protected = 2
	config.target_species_count = 4


func _run_tests() -> void:
	_test("neat_evo_init_creates_population", test_init_population)
	_test("neat_evo_get_individual", test_get_individual)
	_test("neat_evo_get_network", test_get_network)
	_test("neat_evo_set_fitness", test_set_fitness)
	_test("neat_evo_evolve_increments_generation", test_evolve_generation)
	_test("neat_evo_evolve_preserves_population_size", test_evolve_pop_size)
	_test("neat_evo_evolve_creates_species", test_evolve_species)
	_test("neat_evo_tracks_best", test_tracks_best)
	_test("neat_evo_tracks_all_time_best", test_tracks_all_time_best)
	_test("neat_evo_multiple_generations", test_multiple_generations)
	_test("neat_evo_get_stats", test_get_stats)
	_test("neat_evo_signal_emitted", test_signal_emitted)


func test_init_population() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	assert_eq(evo.population.size(), 30)
	assert_eq(evo.generation, 0)


func test_get_individual() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	var genome := evo.get_individual(0)
	assert_not_null(genome)
	assert_gt(genome.node_genes.size(), 0)


func test_get_network() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	var net := evo.get_network(0)
	assert_not_null(net)
	assert_eq(net.get_input_count(), 3)
	assert_eq(net.get_output_count(), 2)
	var outputs := net.forward(PackedFloat32Array([1.0, 0.0, -1.0]))
	assert_eq(outputs.size(), 2)


func test_set_fitness() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	evo.set_fitness(0, 42.0)
	assert_approx(evo.population[0].fitness, 42.0)


func test_evolve_generation() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	# Set some fitness values
	for i in config.population_size:
		evo.set_fitness(i, randf() * 100.0)
	evo.evolve()
	assert_eq(evo.generation, 1)


func test_evolve_pop_size() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	for i in config.population_size:
		evo.set_fitness(i, randf() * 100.0)
	evo.evolve()
	assert_eq(evo.population.size(), config.population_size)


func test_evolve_species() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	for i in config.population_size:
		evo.set_fitness(i, randf() * 100.0)
	evo.evolve()
	assert_gt(evo.get_species_count(), 0)


func test_tracks_best() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	evo.set_fitness(0, 999.0)
	for i in range(1, config.population_size):
		evo.set_fitness(i, 1.0)
	evo.evolve()
	assert_approx(evo.best_fitness, 999.0)
	assert_not_null(evo.best_genome)


func test_tracks_all_time_best() -> void:
	_setup()
	var evo := NeatEvolution.new(config)

	# Gen 1: high fitness
	evo.set_fitness(0, 500.0)
	for i in range(1, config.population_size):
		evo.set_fitness(i, 1.0)
	evo.evolve()
	assert_approx(evo.all_time_best_fitness, 500.0)

	# Gen 2: lower fitness — all_time should remain 500
	for i in config.population_size:
		evo.set_fitness(i, 10.0)
	evo.evolve()
	assert_gte(evo.all_time_best_fitness, 500.0)


func test_multiple_generations() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	for gen in 5:
		for i in config.population_size:
			evo.set_fitness(i, randf() * 100.0)
		evo.evolve()
	assert_eq(evo.generation, 5)
	assert_eq(evo.population.size(), config.population_size)


func test_get_stats() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	for i in config.population_size:
		evo.set_fitness(i, randf() * 100.0)
	evo.evolve()
	var stats: Dictionary = evo.get_stats()
	assert_eq(stats.generation, 1)
	assert_eq(stats.population_size, config.population_size)
	assert_gt(stats.species_count, 0)
	assert_true(stats.has("best_fitness"))
	assert_true(stats.has("all_time_best"))


func test_signal_emitted() -> void:
	_setup()
	var evo := NeatEvolution.new(config)
	var signal_received := [false]
	evo.generation_complete.connect(func(gen, best, avg): signal_received[0] = true)
	for i in config.population_size:
		evo.set_fitness(i, randf() * 100.0)
	evo.evolve()
	assert_true(signal_received[0], "generation_complete signal should be emitted")
