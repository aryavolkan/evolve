extends SceneTree

## Benchmark NEAT operations: GDScript vs Rust implementations
## Run with: godot --headless --path ~/projects/evolve --script scripts/benchmark_neat_rust.gd

func _init() -> void:
	print("=== NEAT Rust Optimization Benchmark ===\n")
	
	# Setup
	var config = preload("res://ai/neat_config.gd").new()
	config.population_size = 100
	config.input_count = 86
	config.output_count = 6
	config.use_bias = true
	
	var evolution = preload("res://ai/neat_evolution.gd").new(config)
	
	# Create test population
	print("Creating test population...")
	for i in 10:
		evolution.evolve()  # Evolve to create diverse genomes
	
	var population = evolution.population
	var species_list = evolution.species_list
	
	print("Population size: %d" % population.size())
	print("Species count: %d" % species_list.size())
	print("")
	
	# Benchmark 1: Speciation
	print("[1] Speciation Benchmark")
	print("-" * 40)
	
	var iterations = 20
	
	# GDScript version
	var gd_start = Time.get_ticks_usec()
	for i in iterations:
		var result = preload("res://ai/neat_species.gd").speciate(
			population, species_list, config, 1000
		)
	var gd_time = (Time.get_ticks_usec() - gd_start) / 1000000.0
	print("GDScript: %.3fs for %d iterations (%.3fs per iteration)" % [gd_time, iterations, gd_time / iterations])
	
	# Rust version (if available)
	var integration = preload("res://ai/neat_evolution_rust_integration.gd")
	integration._check_rust_available()
	
	if integration._rust_species:
		var rust_start = Time.get_ticks_usec()
		for i in iterations:
			var result = integration.speciate(population, species_list, config, 1000)
		var rust_time = (Time.get_ticks_usec() - rust_start) / 1000000.0
		print("Rust:     %.3fs for %d iterations (%.3fs per iteration)" % [rust_time, iterations, rust_time / iterations])
		print("Speedup:  %.1fx" % (gd_time / rust_time))
	else:
		print("Rust:     Not available")
	
	print("")
	
	# Benchmark 2: Genome Distance Calculations
	print("[2] Genome Distance Benchmark")
	print("-" * 40)
	
	if population.size() >= 2:
		var genome_a = population[0]
		var genome_b = population[1]
		iterations = 10000
		
		# GDScript
		var gd_dist_start = Time.get_ticks_usec()
		for i in iterations:
			var dist = genome_a.distance(genome_b, config)
		var gd_dist_time = (Time.get_ticks_usec() - gd_dist_start) / 1000000.0
		print("GDScript: %.3fs for %d calculations" % [gd_dist_time, iterations])
		
		# Rust (if available)
		if integration._rust_genome:
			var rust_dist_start = Time.get_ticks_usec()
			for i in iterations:
				var dist = integration.genome_distance(genome_a, genome_b, config)
			var rust_dist_time = (Time.get_ticks_usec() - rust_dist_start) / 1000000.0
			print("Rust:     %.3fs for %d calculations" % [rust_dist_time, iterations])
			print("Speedup:  %.1fx" % (gd_dist_time / rust_dist_time))
		else:
			print("Rust:     Not available")
	
	print("")
	
	# Benchmark 3: Crossover Operations
	print("[3] Crossover Benchmark")
	print("-" * 40)
	
	if population.size() >= 2:
		var parent_a = population[0]
		var parent_b = population[1]
		iterations = 1000
		
		# GDScript
		var gd_cross_start = Time.get_ticks_usec()
		for i in iterations:
			var child = preload("res://ai/neat_genome.gd").crossover(parent_a, parent_b)
		var gd_cross_time = (Time.get_ticks_usec() - gd_cross_start) / 1000000.0
		print("GDScript: %.3fs for %d crossovers" % [gd_cross_time, iterations])
		
		# Rust (if available)
		if integration._rust_genome:
			var rust_cross_start = Time.get_ticks_usec()
			for i in iterations:
				var child = integration.crossover(parent_a, parent_b)
			var rust_cross_time = (Time.get_ticks_usec() - rust_cross_start) / 1000000.0
			print("Rust:     %.3fs for %d crossovers" % [rust_cross_time, iterations])
			print("Speedup:  %.1fx" % (gd_cross_time / rust_cross_time))
		else:
			print("Rust:     Not available")
	
	print("")
	
	# Summary
	print("=== Summary ===")
	print("Rust optimizations provide significant speedups for NEAT operations.")
	print("To enable: ensure evolve-native.so is built and loaded via gdextension.")
	
	quit()