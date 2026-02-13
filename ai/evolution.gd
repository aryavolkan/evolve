extends RefCounted

## Manages a population of neural networks and evolves them.
## Supports single-objective (fitness-proportionate with elitism) or
## multi-objective NSGA-II selection (3 objectives: survival, kills, powerups).

signal generation_complete(generation: int, best_fitness: float, avg_fitness: float, min_fitness: float)

var NeuralNetworkScript = preload("res://ai/neural_network.gd")
const NSGA2 = preload("res://ai/nsga2.gd")

var population: Array = []
var fitness_scores: PackedFloat32Array
var generation: int = 0

# NSGA-II multi-objective mode
var use_nsga2: bool = false

# Elman recurrent memory
var use_memory: bool = false
var objective_scores: Array = []  # Array of Vector3 per individual (survival, kills, powerups)
var pareto_front: Array = []  # Current generation's Pareto front [{index, objectives}]
var last_hypervolume: float = 0.0  # For stagnation detection in NSGA-II mode
var _last_num_fronts: int = 0  # Cached front count from last evolve

# Evolution parameters
var population_size: int
var elite_count: int
var mutation_rate: float
var mutation_strength: float
var crossover_rate: float

# Base parameters (for adaptive mutation reset)
var base_mutation_rate: float
var base_mutation_strength: float

# Adaptive mutation tracking
var stagnant_generations: int = 0
var last_best_fitness: float = 0.0
const STAGNATION_THRESHOLD: int = 3  # Generations without improvement to trigger adaptation
const MAX_MUTATION_BOOST: float = 3.0  # Maximum multiplier for mutation

# Network architecture
var input_size: int
var hidden_size: int
var output_size: int

# Best network tracking
var best_network = null
var best_fitness: float = 0.0
var all_time_best_network = null
var all_time_best_fitness: float = 0.0

# Lineage tracking (optional, set externally)
var lineage: RefCounted = null
var _lineage_ids: PackedInt32Array

# Backup for generation rollback
var backup_population: Array = []
var backup_generation: int = 0


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
	population_size = p_population_size
	input_size = p_input_size
	hidden_size = p_hidden_size
	output_size = p_output_size
	elite_count = p_elite_count
	mutation_rate = p_mutation_rate
	mutation_strength = p_mutation_strength
	crossover_rate = p_crossover_rate

	# Save base parameters for adaptive mutation
	base_mutation_rate = p_mutation_rate
	base_mutation_strength = p_mutation_strength

	fitness_scores.resize(population_size)
	objective_scores.resize(population_size)
	for i in population_size:
		objective_scores[i] = Vector3.ZERO
	initialize_population()


func enable_population_memory() -> void:
	## Enable Elman memory on all networks in the population.
	use_memory = true
	for net in population:
		net.enable_memory()


func initialize_population() -> void:
	## Create initial random population.
	population.clear()
	for i in population_size:
		var net = NeuralNetworkScript.new(input_size, hidden_size, output_size)
		population.append(net)
	generation = 0
	_seed_lineage()


func _seed_lineage() -> void:
	## Register initial population with lineage tracker if set.
	if lineage:
		var ids = lineage.record_seed(0, population_size)
		_lineage_ids.resize(population_size)
		for i in population_size:
			_lineage_ids[i] = ids[i]


func set_fitness(index: int, fitness: float) -> void:
	## Set the fitness score for a specific individual.
	fitness_scores[index] = fitness
	if lineage and index < _lineage_ids.size():
		lineage.update_fitness(_lineage_ids[index], fitness)


func set_objectives(index: int, objectives: Vector3) -> void:
	## Set the 3 objective scores for an individual (survival, kills, powerups).
	## Also sets scalar fitness as the sum for backward compatibility.
	objective_scores[index] = objectives
	var total: float = objectives.x + objectives.y + objectives.z
	fitness_scores[index] = total
	if lineage and index < _lineage_ids.size():
		lineage.update_fitness(_lineage_ids[index], total)


func get_objectives(index: int) -> Vector3:
	## Get the 3 objective scores for an individual.
	return objective_scores[index]


func get_individual(index: int):
	## Get a network from the population.
	return population[index]


func save_backup() -> void:
	## Save current population state before evolving.
	backup_population.clear()
	for net in population:
		backup_population.append(net.clone())
	backup_generation = generation


func restore_backup() -> void:
	## Restore population from backup (for re-running a generation).
	if backup_population.is_empty():
		return
	population.clear()
	for net in backup_population:
		population.append(net.clone())
	generation = backup_generation
	# Reset fitness scores
	for i in population_size:
		fitness_scores[i] = 0.0


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

	# Find best performers
	var indexed_fitness: Array = []
	for i in population_size:
		indexed_fitness.append({"index": i, "fitness": fitness_scores[i]})

	indexed_fitness.sort_custom(func(a, b): return a.fitness > b.fitness)

	# Track best
	best_fitness = indexed_fitness[0].fitness
	best_network = population[indexed_fitness[0].index].clone()

	if best_fitness > all_time_best_fitness:
		all_time_best_fitness = best_fitness
		all_time_best_network = best_network.clone()

	# Calculate average and min fitness
	var total_fitness := 0.0
	var min_fitness := INF
	for i in population_size:
		total_fitness += fitness_scores[i]
		min_fitness = minf(min_fitness, fitness_scores[i])
	var avg_fitness := total_fitness / population_size

	# Adaptive mutation: increase mutation when stagnating
	if best_fitness > last_best_fitness * 1.01:  # 1% improvement threshold
		stagnant_generations = 0
		mutation_rate = base_mutation_rate
		mutation_strength = base_mutation_strength
	else:
		stagnant_generations += 1

	last_best_fitness = best_fitness

	# Boost mutation if stagnating
	_apply_adaptive_mutation()

	# Create new population
	var new_population: Array = []
	var new_lineage_ids: PackedInt32Array
	if lineage:
		new_lineage_ids.resize(population_size)

	# Save old lineage ID mapping before building new population
	var old_lid := _lineage_ids.duplicate() if lineage else PackedInt32Array()

	# Elitism: keep top performers unchanged
	for i in elite_count:
		var elite = population[indexed_fitness[i].index].clone()
		new_population.append(elite)
		if lineage:
			var src_idx: int = indexed_fitness[i].index
			new_lineage_ids[i] = lineage.record_birth(generation + 1, old_lid[src_idx] if src_idx < old_lid.size() else -1, -1, indexed_fitness[i].fitness, "elite")

	# Fill rest with offspring
	while new_population.size() < population_size:
		var parent_a_idx: int = _select_parent_index(indexed_fitness)
		var child

		if randf() < crossover_rate:
			var parent_b_idx: int = _select_parent_index(indexed_fitness)
			child = population[parent_a_idx].crossover_with(population[parent_b_idx])
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				var lid_b: int = old_lid[parent_b_idx] if parent_b_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, lid_b, 0.0, "crossover")
		else:
			child = population[parent_a_idx].clone()
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, -1, 0.0, "mutation")

		child.mutate(mutation_rate, mutation_strength)
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

	# Non-dominated sorting
	var fronts := NSGA2.non_dominated_sort(objective_scores)
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
	best_network = population[best_idx].clone()

	if best_fitness > all_time_best_fitness:
		all_time_best_fitness = best_fitness
		all_time_best_network = best_network.clone()

	var avg_fitness := total_fitness / population_size

	# Adaptive mutation using hypervolume for stagnation detection
	var hv := _compute_hypervolume()
	if hv > last_hypervolume * 1.01:
		stagnant_generations = 0
		mutation_rate = base_mutation_rate
		mutation_strength = base_mutation_strength
	else:
		stagnant_generations += 1
	last_hypervolume = hv

	_apply_adaptive_mutation()

	# Build crowding distance map for tournament selection
	var crowding_map: Dictionary = {}
	for front in fronts:
		var distances := NSGA2.crowding_distance(front, objective_scores)
		for i in front.size():
			crowding_map[front[i]] = distances[i]

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
		new_population.append(population[idx].clone())
		if lineage:
			new_lineage_ids[new_population.size() - 1] = lineage.record_birth(generation + 1, old_lid[idx] if idx < old_lid.size() else -1, -1, fitness_scores[idx], "elite")

	# Fill rest with offspring via NSGA-II tournament selection
	while new_population.size() < population_size:
		var parent_a_idx := NSGA2.tournament_select(objective_scores, fronts, crowding_map)
		var child

		if randf() < crossover_rate:
			var parent_b_idx := NSGA2.tournament_select(objective_scores, fronts, crowding_map)
			child = population[parent_a_idx].crossover_with(population[parent_b_idx])
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				var lid_b: int = old_lid[parent_b_idx] if parent_b_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, lid_b, 0.0, "crossover")
		else:
			child = population[parent_a_idx].clone()
			if lineage:
				var lid_a: int = old_lid[parent_a_idx] if parent_a_idx < old_lid.size() else -1
				new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, -1, 0.0, "mutation")

		child.mutate(mutation_rate, mutation_strength)
		new_population.append(child)

	population = new_population
	if lineage:
		_lineage_ids = new_lineage_ids
	generation += 1

	# Reset scores
	_reset_scores()

	generation_complete.emit(generation, best_fitness, avg_fitness, min_fitness)


func _apply_adaptive_mutation() -> void:
	## Boost mutation rate when stagnating.
	if stagnant_generations >= STAGNATION_THRESHOLD:
		var mutation_boost := minf(1.0 + (stagnant_generations - STAGNATION_THRESHOLD + 1) * 0.5, MAX_MUTATION_BOOST)
		mutation_rate = minf(base_mutation_rate * mutation_boost, 0.5)
		mutation_strength = base_mutation_strength * mutation_boost
		print("  Adaptive mutation: %.0fx boost (stagnant %d gens)" % [mutation_boost, stagnant_generations])


func _reset_scores() -> void:
	## Reset all fitness and objective scores.
	for i in population_size:
		fitness_scores[i] = 0.0
		objective_scores[i] = Vector3.ZERO


func _compute_hypervolume() -> float:
	## Compute 2D hypervolume (survival vs kills) for stagnation tracking.
	if pareto_front.is_empty():
		return 0.0
	var front_2d: Array = []
	for entry in pareto_front:
		var obj: Vector3 = entry.objectives
		front_2d.append(Vector2(obj.x, obj.y))
	return NSGA2.hypervolume_2d(front_2d, Vector2.ZERO)


func _select_parent_index(indexed_fitness: Array) -> int:
	## Tournament selection: pick best of 3 random individuals. Returns population index.
	var tournament_size := 3
	var best_idx := -1
	var best_fit := -INF

	for i in tournament_size:
		var candidate = indexed_fitness[randi() % indexed_fitness.size()]
		if candidate.fitness > best_fit:
			best_fit = candidate.fitness
			best_idx = candidate.index

	return best_idx


func select_parent(indexed_fitness: Array):
	## Tournament selection: pick best of 3 random individuals.
	return population[_select_parent_index(indexed_fitness)]


func get_best_network():
	## Get the best network from the current generation.
	return best_network


func get_all_time_best():
	## Get the best network ever found.
	return all_time_best_network


func get_generation() -> int:
	return generation


func get_best_fitness() -> float:
	return best_fitness


func get_all_time_best_fitness() -> float:
	return all_time_best_fitness


func save_best(path: String) -> void:
	## Save the all-time best network.
	if all_time_best_network:
		all_time_best_network.save_to_file(path)


func save_generation_best(base_path: String) -> void:
	## Save the best network for the current generation.
	## Creates files like user://gen_001.nn, user://gen_002.nn, etc.
	if best_network:
		var gen_path := base_path.replace(".nn", "_gen_%03d.nn" % generation)
		best_network.save_to_file(gen_path)


func load_best(path: String) -> void:
	## Load a network and set it as the best.
	var net = NeuralNetworkScript.load_from_file(path)
	if net:
		all_time_best_network = net
		all_time_best_fitness = 0.0  # Unknown fitness


func save_population(path: String) -> void:
	## Save entire population state.
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


func load_population(path: String) -> bool:
	## Load population state.
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
	var weight_count: int = population[0].get_weight_count()
	for i in population_size:
		var weights := PackedFloat32Array()
		weights.resize(weight_count)
		for j in weight_count:
			weights[j] = file.get_float()
		population[i].set_weights(weights)

	# Load all-time best
	var has_best := file.get_8()
	if has_best:
		all_time_best_network = NeuralNetworkScript.new(input_size, hidden_size, output_size)
		if use_memory:
			all_time_best_network.enable_memory()
		var weights := PackedFloat32Array()
		weights.resize(weight_count)
		for j in weight_count:
			weights[j] = file.get_float()
		all_time_best_network.set_weights(weights)
		best_network = all_time_best_network.clone()

	file.close()
	return true


func get_stats() -> Dictionary:
	## Get current evolution statistics.
	var min_fit := INF
	var max_fit := -INF
	var total := 0.0

	for f in fitness_scores:
		min_fit = minf(min_fit, f)
		max_fit = maxf(max_fit, f)
		total += f

	var stats := {
		"generation": generation,
		"population_size": population_size,
		"best_fitness": best_fitness,
		"all_time_best": all_time_best_fitness,
		"current_min": min_fit,
		"current_max": max_fit,
		"current_avg": total / population_size if population_size > 0 else 0.0
	}

	if use_nsga2:
		stats["pareto_front_size"] = pareto_front.size()
		stats["hypervolume"] = last_hypervolume
		stats["num_fronts"] = _last_num_fronts

	return stats
