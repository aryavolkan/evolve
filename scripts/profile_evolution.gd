extends SceneTree

## Profile evolution performance to identify bottlenecks.
## Run with: godot --headless --path ~/projects/evolve --script scripts/profile_evolution.gd

func _init() -> void:
	print("=== Evolution Performance Profiler ===")
	
	# Load configurations
	var config = preload("res://ai/training_config.gd").new()
	config.population_size = 100
	config.use_neat = true
	config.use_nsga2 = true
	config.use_memory = true
	config.hidden_size = 32
	
	# Test NEAT Evolution
	print("\n[NEAT Evolution Profiling]")
	var neat_config = preload("res://ai/neat_config.gd").new()
	neat_config.population_size = 100
	neat_config.input_count = 86
	neat_config.output_count = 6
	# neat_config doesn't have hidden_size, it uses hidden nodes dynamically
	neat_config.use_bias = true
	
	var neat_evo = preload("res://ai/neat_evolution.gd").new(neat_config)
	
	# Profile speciation
	var speciation_start = Time.get_ticks_usec()
	for i in 5:
		neat_evo._apply_mo_fitness()
		var spec_result = preload("res://ai/neat_species.gd").speciate(
			neat_evo.population, 
			neat_evo.species_list, 
			neat_config, 
			neat_evo._next_species_id
		)
	var speciation_time = (Time.get_ticks_usec() - speciation_start) / 1000000.0
	print("Speciation (5 iterations): %.3fs (%.3fs per gen)" % [speciation_time, speciation_time / 5.0])
	
	# Profile NSGA2
	print("\n[NSGA2 Profiling]")
	var objectives = []
	for i in 100:
		objectives.append(Vector3(randf() * 100, randf() * 100, randf() * 100))
	
	# GDScript version
	var nsga2_gd_start = Time.get_ticks_usec()
	for i in 10:
		var fronts = preload("res://ai/nsga2.gd").non_dominated_sort(objectives)
	var nsga2_gd_time = (Time.get_ticks_usec() - nsga2_gd_start) / 1000000.0
	print("NSGA2 GDScript (10 iterations): %.3fs" % nsga2_gd_time)
	
	# Rust version if available
	if ClassDB.class_exists(&"RustNsga2"):
		var rust_nsga2 = ClassDB.instantiate(&"RustNsga2")
		if rust_nsga2:
			var nsga2_rust_start = Time.get_ticks_usec()
			for i in 10:
				var fronts = rust_nsga2.non_dominated_sort(objectives)
			var nsga2_rust_time = (Time.get_ticks_usec() - nsga2_rust_start) / 1000000.0
			print("NSGA2 Rust (10 iterations): %.3fs (%.1fx speedup)" % [nsga2_rust_time, nsga2_gd_time / nsga2_rust_time])
	
	# Profile Neural Network forward pass
	print("\n[Neural Network Forward Pass Profiling]")
	var nn_factory = preload("res://ai/neural_network_factory.gd")
	var inputs = PackedFloat32Array()
	inputs.resize(86)
	for i in 86:
		inputs[i] = randf()
	
	# Create networks
	var gdscript_nn = preload("res://ai/neural_network.gd").new(86, 32, 6)
	var rust_nn = null
	if nn_factory.is_rust_available():
		rust_nn = nn_factory.create(86, 32, 6)
	
	# GDScript forward pass
	var gd_forward_start = Time.get_ticks_usec()
	for i in 10000:
		var out = gdscript_nn.forward(inputs)
	var gd_forward_time = (Time.get_ticks_usec() - gd_forward_start) / 1000000.0
	print("GDScript NN forward (10k passes): %.3fs" % gd_forward_time)
	
	# Rust forward pass
	if rust_nn:
		var rust_forward_start = Time.get_ticks_usec()
		for i in 10000:
			var out = rust_nn.forward(inputs)
		var rust_forward_time = (Time.get_ticks_usec() - rust_forward_start) / 1000000.0
		print("Rust NN forward (10k passes): %.3fs (%.1fx speedup)" % [rust_forward_time, gd_forward_time / rust_forward_time])
	
	# Profile genome operations
	print("\n[NEAT Genome Operations Profiling]")
	var genome_a = preload("res://ai/neat_genome.gd").create(neat_config, neat_evo.innovation_tracker)
	var genome_b = preload("res://ai/neat_genome.gd").create(neat_config, neat_evo.innovation_tracker)
	genome_a.create_basic()
	genome_b.create_basic()
	
	# Mutation
	var mutation_start = Time.get_ticks_usec()
	for i in 1000:
		var g = genome_a.copy()
		g.mutate(neat_config)
	var mutation_time = (Time.get_ticks_usec() - mutation_start) / 1000000.0
	print("NEAT mutation (1k genomes): %.3fs" % mutation_time)
	
	# Crossover
	var crossover_start = Time.get_ticks_usec()
	for i in 1000:
		var child = preload("res://ai/neat_genome.gd").crossover(genome_a, genome_b)
	var crossover_time = (Time.get_ticks_usec() - crossover_start) / 1000000.0
	print("NEAT crossover (1k operations): %.3fs" % crossover_time)
	
	# Distance calculation
	var distance_start = Time.get_ticks_usec()
	for i in 10000:
		var dist = genome_a.distance(genome_b, neat_config)
	var distance_time = (Time.get_ticks_usec() - distance_start) / 1000000.0
	print("NEAT distance (10k calculations): %.3fs" % distance_time)
	
	print("\n=== Profiling Complete ===")
	quit()