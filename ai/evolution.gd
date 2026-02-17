extends "res://ai/evolution_base.gd"

## Manages a population of neural networks and evolves them.
## Supports single-objective (fitness-proportionate with elitism) or
## multi-objective NSGA-II selection (3 objectives: survival, kills, powerups).

var NeuralNetworkScript = preload("res://ai/neural_network.gd")
const NNFactory = preload("res://ai/neural_network_factory.gd")
const NSGA2 = preload("res://ai/nsga2.gd")

# Rust accelerated genetic operations (when available)
var _rust_genetic_ops = null
var _use_rust_genetic_ops: bool = false

# Rust accelerated NSGA-II (when available)
var _rust_nsga2 = null
var _use_rust_nsga2: bool = false

# NSGA-II multi-objective mode
var use_memory: bool = false
var objective_scores: Array = []  # Array of Vector3 per individual (survival, kills, powerups)
var pareto_front: Array = []  # Current generation's Pareto front [{index, objectives}]
var last_hypervolume: float = 0.0  # For stagnation detection in NSGA-II mode
var _last_num_fronts: int = 0  # Cached front count from last evolve

# Evolution parameters
var elite_count: int
var crossover_rate: float

# Network architecture
var input_size: int
var hidden_size: int
var output_size: int

# Best network tracking
var best_network = null
var all_time_best_network = null


func _init(
	p_population_size: int = 150,
	p_input_size: int = 70,
	p_hidden_size: int = 80,
	p_output_size: int = 6,
	p_elite_count: int = 20,
	p_mutation_rate: float = 0.30,
	p_mutation_strength: float = 0.09,
	p_crossover_rate: float = 0.73
) -> void:
	super._init(p_population_size, p_mutation_rate, p_mutation_strength)
	input_size = p_input_size
	hidden_size = p_hidden_size
	output_size = p_output_size
	elite_count = p_elite_count
	crossover_rate = p_crossover_rate

	objective_scores.resize(p_population_size)
	for i in p_population_size:
		objective_scores[i] = Vector3.ZERO

	# Initialize Rust genetic operations if available
	if ClassDB.class_exists(&"RustGeneticOps"):
		_rust_genetic_ops = ClassDB.instantiate(&"RustGeneticOps")
		if _rust_genetic_ops:
			_use_rust_genetic_ops = true
			print("[Evolution] ✓ Using Rust genetic operations for faster evolution")
		else:
			print("[Evolution] ⚠ RustGeneticOps class exists but couldn't instantiate")
	else:
		print("[Evolution] ⚠ RustGeneticOps not available, using GDScript implementation")

	# Initialize Rust NSGA-II if available
	if ClassDB.class_exists(&"RustNsga2"):
		_rust_nsga2 = ClassDB.instantiate(&"RustNsga2")
		if _rust_nsga2:
			_use_rust_nsga2 = true
			print("[Evolution] ✓ Using Rust NSGA-II for faster multi-objective sorting")
		else:
			print("[Evolution] ⚠ RustNsga2 class exists but couldn't instantiate")
	else:
		print("[Evolution] ⚠ RustNsga2 not available, using GDScript NSGA-II")

	initialize_population()


func enable_population_memory() -> void:
	## Enable Elman memory on all networks in the population.
	use_memory = true
	for net in population:
		NNFactory.enable_memory(net)


func initialize_population() -> void:
	## Create initial random population.
	## Uses RustNeuralNetwork when available for ~5-15× faster forward passes.
	population.clear()
	for i in population_size:
		var net = NNFactory.create(input_size, hidden_size, output_size)
		population.append(net)
	generation = 0
	seed_lineage(population_size)
	_reset_scores()


func set_objectives(index: int, objectives: Vector3) -> void:
	## Set the 3 objective scores for an individual (survival, kills, powerups).
	## Also sets scalar fitness as the sum for backward compatibility.
	objective_scores[index] = objectives
	var total: float = objectives.x + objectives.y + objectives.z
	super.set_fitness(index, total)


func get_objectives(index: int) -> Vector3:
	## Get the 3 objective scores for an individual.
	return objective_scores[index]


func get_individual(index: int):
	## Get a network from the population.
	return population[index]


func evolve() -> void:
	## Create the next generation based on fitness scores.
	## Uses NSGA-II multi-objective selection when use_nsga2 is true,
	## otherwise uses the original single-objective fitness-proportionate selection.

	# Save backup before evolving (for potential rollback)
	save_backup()

	if use_nsga2:
		_evolve_nsga2()
	else:
		_evolve_single_objective()


func _evolve_single_objective() -> void:
	## Original single-objective evolution with elitism and tournament selection.
	if population_size == 0:
		return

	# --- Sort: use Rust argsort (packed array, no dict overhead) when available ---
	var sorted_indices: PackedInt32Array
	if _use_rust_genetic_ops:
		sorted_indices = _rust_genetic_ops.argsort_fitness(fitness_scores)
	else:
		# GDScript fallback: build dict array and sort
		var indexed_fitness: Array = []
		for i in population_size:
			indexed_fitness.append({"index": i, "fitness": fitness_scores[i]})
		indexed_fitness.sort_custom(func(a, b): return a.fitness > b.fitness)
		sorted_indices.resize(indexed_fitness.size())
		for i in indexed_fitness.size():
			sorted_indices[i] = indexed_fitness[i].index

	# Track best
	best_fitness = fitness_scores[sorted_indices[0]]
	best_network = NNFactory.clone_network(population[sorted_indices[0]])

	if best_fitness > all_time_best_fitness:
		all_time_best_fitness = best_fitness
		all_time_best_network = NNFactory.clone_network(best_network)

	# --- Stats: single-pass via Rust when available ---
	var min_fitness: float
	var avg_fitness: float
	if _use_rust_genetic_ops:
		var stats: Vector3 = _rust_genetic_ops.fitness_stats(fitness_scores)
		# stats.x = sum, stats.y = min, stats.z = max
		avg_fitness = stats.x / population_size if population_size > 0 else 0.0
		min_fitness = stats.y
	else:
		var total_fitness := 0.0
		min_fitness = INF
		for i in population_size:
			total_fitness += fitness_scores[i]
			min_fitness = minf(min_fitness, fitness_scores[i])
		avg_fitness = total_fitness / population_size if population_size > 0 else 0.0

	cache_stats(min_fitness, avg_fitness, best_fitness)
	track_stagnation(best_fitness)
	apply_adaptive_mutation()

	# Create new population
	var new_population: Array = []
	var new_lineage_ids: PackedInt32Array
	if lineage:
		new_lineage_ids.resize(population_size)

	# Save old lineage ID mapping before building new population
	var old_lid := _lineage_ids.duplicate() if lineage else PackedInt32Array()

	# Elitism: keep top performers unchanged (sorted_indices already sorted desc)
	var actual_elite := mini(elite_count, sorted_indices.size())
	for i in actual_elite:
		var elite_idx: int = sorted_indices[i]
		var elite = NNFactory.clone_network(population[elite_idx])
		new_population.append(elite)
		if lineage:
			new_lineage_ids[i] = lineage.record_birth(
				generation + 1,
				old_lid[elite_idx] if elite_idx < old_lid.size() else -1,
				-1,
				fitness_scores[elite_idx],
				"elite"
			)

	# --- Parent selection: batch pre-select all parents with Rust when available ---
	var num_offspring := population_size - actual_elite
	var parent_a_indices: PackedInt32Array
	var parent_b_indices: PackedInt32Array
	if _use_rust_genetic_ops and num_offspring > 0:
		parent_a_indices = _rust_genetic_ops.batch_tournament_select_packed(fitness_scores, num_offspring, 3)
		parent_b_indices = _rust_genetic_ops.batch_tournament_select_packed(fitness_scores, num_offspring, 3)
	else:
		# Fallback: build indexed_fitness for GDScript tournament_select
		var indexed_fitness: Array = []
		for i in population_size:
			indexed_fitness.append({"index": i, "fitness": fitness_scores[i]})
		parent_a_indices.resize(num_offspring)
		parent_b_indices.resize(num_offspring)
		for i in num_offspring:
			parent_a_indices[i] = tournament_select(indexed_fitness)
			parent_b_indices[i] = tournament_select(indexed_fitness)

	# Fill rest with offspring
	for i in num_offspring:
		if new_population.size() >= population_size:
			break
		var parent_a_idx: int = parent_a_indices[i]
		if parent_a_idx == -1:
			break
		var child

		if randf() < crossover_rate:
			var parent_b_idx: int = parent_b_indices[i]
			if parent_b_idx == -1:
				parent_b_idx = parent_a_idx
			child = NNFactory.crossover(population[parent_a_idx], population[parent_b_idx])
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				var lid_b: int = old_lid[parent_b_idx] if parent_b_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, lid_b, 0.0, "crossover")
		else:
			child = NNFactory.clone_network(population[parent_a_idx])
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, -1, 0.0, "mutation")

		NNFactory.mutate_network(child, mutation_rate, mutation_strength)
		new_population.append(child)

	population = new_population
	if lineage:
		_lineage_ids = new_lineage_ids
	generation += 1

	# Reset fitness scores
	_reset_scores()

	generation_complete.emit(generation, best_fitness, avg_fitness, min_fitness)


func _evolve_nsga2() -> void:
	## NSGA-II multi-objective evolution.
	## Selection based on Pareto dominance and crowding distance.
	if population_size == 0:
		return

	# Non-dominated sorting — use Rust O(MN²) impl when available (same algo, much faster)
	var fronts: Array
	if _use_rust_nsga2:
		# RustNsga2.non_dominated_sort returns Array of PackedInt32Array (fronts)
		var raw_fronts: Array = _rust_nsga2.non_dominated_sort(objective_scores)
		# Convert PackedInt32Array fronts back to plain Arrays for GDScript compat
		fronts = []
		for front_packed in raw_fronts:
			var front_arr: Array = []
			for idx in front_packed:
				front_arr.append(idx)
			fronts.append(front_arr)
	else:
		fronts = NSGA2.non_dominated_sort(objective_scores)
	_last_num_fronts = fronts.size()
	pareto_front = NSGA2.get_pareto_front(objective_scores)

	# Track best network: highest sum of objectives (backward compat)
	var best_sum := -INF
	var best_idx := 0
	var total_fitness := 0.0
	var min_fitness := INF
	for i in population_size:
		var s: float = objective_scores[i].x + objective_scores[i].y + objective_scores[i].z
		total_fitness += s
		min_fitness = minf(min_fitness, s)
		if s > best_sum:
			best_sum = s
			best_idx = i

	best_fitness = best_sum
	best_network = NNFactory.clone_network(population[best_idx])

	if best_fitness > all_time_best_fitness:
		all_time_best_fitness = best_fitness
		all_time_best_network = NNFactory.clone_network(best_network)

	var avg_fitness := total_fitness / population_size

	cache_stats(min_fitness, avg_fitness, best_fitness)

	# Adaptive mutation using hypervolume for stagnation detection
	var hv := _compute_hypervolume()
	if hv > last_hypervolume * 1.01:
		stagnant_generations = 0
		mutation_rate = base_mutation_rate
		mutation_strength = base_mutation_strength
	else:
		stagnant_generations += 1
	last_hypervolume = hv

	apply_adaptive_mutation()

	# Build crowding distance map and rank lookup for tournament selection
	var crowding_map: Dictionary = {}
	for front in fronts:
		var distances := NSGA2.crowding_distance(front, objective_scores)
		for i in front.size():
			crowding_map[front[i]] = distances[i]

	# Precompute rank map for O(1) rank lookup in tournament selection
	var rank_map := NSGA2.build_rank_map(fronts, population_size)

	# NSGA-II selection: fill new population front by front
	var selected_indices := NSGA2.select(objective_scores, population_size)

	# Create new population using selected individuals as parents
	var new_population: Array = []
	var new_lineage_ids: PackedInt32Array
	if lineage:
		new_lineage_ids.resize(population_size)
	var old_lid := _lineage_ids.duplicate() if lineage else PackedInt32Array()

	# Elitism: keep front 0 individuals (up to elite_count)
	var elite_indices: Array = []
	if not fronts.is_empty():
		for idx in fronts[0]:
			if elite_indices.size() >= elite_count:
				break
			elite_indices.append(idx)

	for idx in elite_indices:
		new_population.append(NNFactory.clone_network(population[idx]))
		if lineage:
			new_lineage_ids[new_population.size() - 1] = lineage.record_birth(
				generation + 1,
				old_lid[idx] if idx < old_lid.size() else -1,
				-1,
				fitness_scores[idx],
				"elite"
			)

	# Fill rest with offspring via NSGA-II tournament selection
	while new_population.size() < population_size:
		var parent_a_idx := NSGA2.tournament_select(objective_scores, fronts, crowding_map, null, rank_map)
		var child

		if randf() < crossover_rate:
			var parent_b_idx := NSGA2.tournament_select(objective_scores, fronts, crowding_map, null, rank_map)
			child = NNFactory.crossover(population[parent_a_idx], population[parent_b_idx])
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				var lid_b: int = old_lid[parent_b_idx] if parent_b_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, lid_b, 0.0, "crossover")
		else:
			child = NNFactory.clone_network(population[parent_a_idx])
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, -1, 0.0, "mutation")

		NNFactory.mutate_network(child, mutation_rate, mutation_strength)
		new_population.append(child)

	population = new_population
	if lineage:
		_lineage_ids = new_lineage_ids
	generation += 1

	# Reset scores
	_reset_scores()

	generation_complete.emit(generation, best_fitness, avg_fitness, min_fitness)


func _compute_hypervolume() -> float:
	## Compute 2D hypervolume (survival vs kills) for stagnation tracking.
	if pareto_front.is_empty():
		return 0.0
	var front_2d: Array = []
	for entry in pareto_front:
		var obj: Vector3 = entry.objectives
		front_2d.append(Vector2(obj.x, obj.y))
	return NSGA2.hypervolume_2d(front_2d, Vector2.ZERO)


func select_parent(indexed_fitness: Array):
	## Tournament selection: pick best of 3 random individuals.
	var idx := tournament_select(indexed_fitness)
	return population[idx] if idx >= 0 else null


func get_best_network():
	## Get the best network from the current generation.
	return best_network


func get_all_time_best():
	## Get the best network ever found.
	return all_time_best_network


func save_generation_best(base_path: String) -> void:
	## Save the best network for the current generation.
	## Creates files like user://gen_001.nn, user://gen_002.nn, etc.
	if best_network:
		var gen_path := base_path.replace(".nn", "_gen_%03d.nn" % generation)
		best_network.save_to_file(gen_path)


func _get_additional_stats() -> Dictionary:
	var extra := {}
	if use_nsga2:
		extra["pareto_front_size"] = pareto_front.size()
		extra["hypervolume"] = last_hypervolume
		extra["num_fronts"] = _last_num_fronts
	return extra


func _reset_scores() -> void:
	super._reset_scores()
	for i in objective_scores.size():
		objective_scores[i] = Vector3.ZERO


func _clone_individual(individual):
	return NNFactory.clone_network(individual)


func _get_all_time_best_entity():
	return all_time_best_network


func _set_all_time_best_entity(entity) -> void:
	all_time_best_network = entity


func _save_entity(path: String, entity) -> void:
	entity.save_to_file(path)


func _load_entity(path: String):
	return NNFactory.load_from_file(path)


func _save_population_impl(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return

	file.store_32(generation)
	file.store_32(population_size)
	file.store_float(best_fitness)
	file.store_float(all_time_best_fitness)

	# Save each network's weights
	for net in population:
		var weights: PackedFloat32Array = net.get_weights()
		for w in weights:
			file.store_float(w)

	# Save all-time best
	if all_time_best_network:
		file.store_8(1)
		var best_weights: PackedFloat32Array = all_time_best_network.get_weights()
		for w in best_weights:
			file.store_float(w)
	else:
		file.store_8(0)

	file.close()


func _load_population_impl(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false

	generation = file.get_32()
	var saved_pop_size := file.get_32()
	best_fitness = file.get_float()
	all_time_best_fitness = file.get_float()

	if saved_pop_size != population_size:
		file.close()
		return false  # Population size mismatch

	# Load each network
	var weight_count: int = population[0].get_weight_count() if not population.is_empty() else 0
	for i in population_size:
		var weights := PackedFloat32Array()
		weights.resize(weight_count)
		for j in weight_count:
			weights[j] = file.get_float()
		population[i].set_weights(weights)

	# Load all-time best
	var has_best := file.get_8()
	if has_best:
		all_time_best_network = NNFactory.create(input_size, hidden_size, output_size)
		if use_memory:
			NNFactory.enable_memory(all_time_best_network)
		var weights := PackedFloat32Array()
		weights.resize(weight_count)
		for j in weight_count:
			weights[j] = file.get_float()
		all_time_best_network.set_weights(weights)
		best_network = NNFactory.clone_network(all_time_best_network)

	file.close()
	return true
