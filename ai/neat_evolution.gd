extends RefCounted
class_name NeatEvolution

## NEAT evolution manager: manages a population of NeatGenomes,
## organizes them into species, and produces new generations via
## species-proportionate reproduction with crossover and mutation.

signal generation_complete(generation: int, best_fitness: float, avg_fitness: float)

var config: NeatConfig
var innovation_tracker: NeatInnovation
var population: Array = []  ## Array of NeatGenome
var species_list: Array = []  ## Array of NeatSpecies
var generation: int = 0
var best_genome: NeatGenome = null
var best_fitness: float = 0.0
var all_time_best_genome: NeatGenome = null
var all_time_best_fitness: float = 0.0
var _next_species_id: int = 0


func _init(p_config: NeatConfig) -> void:
	config = p_config
	innovation_tracker = NeatInnovation.new(p_config.input_count + p_config.output_count + int(p_config.use_bias))
	_initialize_population()


func _initialize_population() -> void:
	population.clear()
	for i in config.population_size:
		var genome := NeatGenome.create(config, innovation_tracker)
		genome.create_basic()
		population.append(genome)
	generation = 0


func get_individual(index: int) -> NeatGenome:
	return population[index]


func get_network(index: int) -> NeatNetwork:
	## Build a phenotype network for individual at index.
	return NeatNetwork.from_genome(population[index])


func set_fitness(index: int, fitness: float) -> void:
	population[index].fitness = fitness


func evolve() -> void:
	## Run one generation of NEAT evolution:
	## 1. Speciate
	## 2. Evaluate fitness sharing
	## 3. Track stagnation, cull stagnant species
	## 4. Allocate offspring per species
	## 5. Reproduce (crossover + mutation)
	## 6. Adjust compatibility threshold

	# 1. Speciate
	var spec_result: Dictionary = NeatSpecies.speciate(population, species_list, config, _next_species_id)
	species_list = spec_result.species
	_next_species_id = spec_result.next_id

	if species_list.is_empty():
		# Shouldn't happen, but reinitialize if it does
		_initialize_population()
		return

	# 2. Fitness sharing + track best
	var total_fitness: float = 0.0
	var gen_best_fitness: float = -INF
	var gen_best_genome: NeatGenome = null

	for species in species_list:
		species.calculate_adjusted_fitness()
		species.update_best_fitness()
		var sp_best = species.get_best_genome()
		if sp_best and sp_best.fitness > gen_best_fitness:
			gen_best_fitness = sp_best.fitness
			gen_best_genome = sp_best

	best_fitness = gen_best_fitness
	best_genome = gen_best_genome.copy() if gen_best_genome else null

	if best_fitness > all_time_best_fitness:
		all_time_best_fitness = best_fitness
		all_time_best_genome = best_genome.copy() if best_genome else null

	# 3. Cull stagnant species (protect top N)
	_cull_stagnant_species()

	if species_list.is_empty():
		_initialize_population()
		return

	# 4. Compute offspring allocation proportional to adjusted fitness
	var total_adjusted: float = 0.0
	for species in species_list:
		total_adjusted += species.get_total_adjusted_fitness()

	var new_population: Array = []

	# 5. Reproduce
	for species in species_list:
		var sp_adjusted: float = species.get_total_adjusted_fitness()
		var offspring_count: int
		if total_adjusted > 0:
			offspring_count = int(round(sp_adjusted / total_adjusted * config.population_size))
		else:
			offspring_count = int(ceil(float(config.population_size) / species_list.size()))

		offspring_count = maxi(offspring_count, 1)  # At least 1 offspring per species

		var sorted_members: Array = species.get_sorted_members()
		if sorted_members.is_empty():
			continue

		# Elite: keep best genome unchanged
		var elite_count: int = maxi(1, int(sorted_members.size() * config.elite_fraction))
		for i in mini(elite_count, offspring_count):
			new_population.append(sorted_members[i].copy())

		# Breeding pool: top survival_fraction
		var pool_size: int = maxi(1, int(sorted_members.size() * config.survival_fraction))
		var pool: Array = sorted_members.slice(0, pool_size)

		# Fill remaining offspring
		var remaining: int = offspring_count - mini(elite_count, offspring_count)
		for i in remaining:
			var child: NeatGenome
			if randf() < config.crossover_rate and pool.size() >= 2:
				var parent_a: NeatGenome = pool[randi() % pool.size()]
				var parent_b: NeatGenome
				# Rare interspecies crossover
				if randf() < config.interspecies_crossover_rate and species_list.size() > 1:
					var other_species = species_list[randi() % species_list.size()]
					if not other_species.members.is_empty():
						parent_b = other_species.members[randi() % other_species.members.size()]
					else:
						parent_b = pool[randi() % pool.size()]
				else:
					parent_b = pool[randi() % pool.size()]
				child = NeatGenome.crossover(parent_a, parent_b)
			else:
				child = pool[randi() % pool.size()].copy()

			child.mutate(config)
			new_population.append(child)

	# Trim or pad to exact population size
	while new_population.size() > config.population_size:
		new_population.pop_back()
	while new_population.size() < config.population_size:
		var filler = population[randi() % population.size()].copy()
		filler.mutate(config)
		new_population.append(filler)

	population = new_population
	generation += 1

	# Reset innovation cache for next generation
	innovation_tracker.reset_generation_cache()

	# 6. Adjust compatibility threshold
	NeatSpecies.adjust_compatibility_threshold(species_list, config)

	# Compute average fitness for signal
	var avg_fitness: float = 0.0
	for genome in population:
		avg_fitness += genome.fitness
	avg_fitness /= population.size() if not population.is_empty() else 1.0

	generation_complete.emit(generation, best_fitness, avg_fitness)


func _cull_stagnant_species() -> void:
	## Remove species that have stagnated too long.
	## Always protect the top min_species_protected species by best fitness.
	if species_list.size() <= config.min_species_protected:
		return

	# Sort species by best_fitness_ever descending
	var sorted_species := species_list.duplicate()
	sorted_species.sort_custom(func(a, b): return a.best_fitness_ever > b.best_fitness_ever)

	var surviving: Array = []
	for i in sorted_species.size():
		if i < config.min_species_protected:
			# Always keep top species
			surviving.append(sorted_species[i])
		elif sorted_species[i].is_stagnant(config.stagnation_kill_threshold):
			continue  # Kill stagnant species
		else:
			surviving.append(sorted_species[i])

	species_list = surviving


func get_species_count() -> int:
	return species_list.size()


func get_stats() -> Dictionary:
	return {
		"generation": generation,
		"population_size": population.size(),
		"species_count": species_list.size(),
		"best_fitness": best_fitness,
		"all_time_best": all_time_best_fitness,
		"compatibility_threshold": config.compatibility_threshold,
	}
