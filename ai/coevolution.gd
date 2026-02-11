extends RefCounted

## Co-evolution coordinator.
## Manages two populations (player and enemy) that co-evolve adversarially.
## This is a coordinator wrapping two Evolution instances — it does not replace
## the existing Evolution class but adds dual-population lifecycle management.
##
## Enemy network architecture: 16 inputs → 16 hidden → 8 outputs
## (smaller than player networks since enemies have simpler perception).
##
## Adversarial fitness:
##   - Player fitness: unchanged (existing fitness function)
##   - Enemy fitness: damage dealt to player + proximity pressure - time player survived
##
## Actual fitness computation happens at evaluation time (training_manager A3),
## not in this coordinator. This class manages population structure and evolution.

signal generation_complete(generation: int, player_best: float, enemy_best: float)

var EvolutionScript = preload("res://ai/evolution.gd")

# Enemy network architecture constants
const ENEMY_INPUT_SIZE: int = 16   # From EnemySensor.TOTAL_INPUTS
const ENEMY_HIDDEN_SIZE: int = 16  # Smaller than player (32), enemies are simpler
const ENEMY_OUTPUT_SIZE: int = 8   # 8 directional preferences (N, NE, E, SE, S, SW, W, NW)

var player_evolution = null  # Evolution instance for player population
var enemy_evolution = null   # Evolution instance for enemy population


func _init(
	player_pop_size: int = 100,
	player_input_size: int = 86,
	player_hidden_size: int = 32,
	player_output_size: int = 6,
	enemy_pop_size: int = 100,
	p_elite_count: int = 5,
	p_mutation_rate: float = 0.15,
	p_mutation_strength: float = 0.3,
	p_crossover_rate: float = 0.7
) -> void:
	player_evolution = EvolutionScript.new(
		player_pop_size, player_input_size, player_hidden_size, player_output_size,
		p_elite_count, p_mutation_rate, p_mutation_strength, p_crossover_rate
	)
	enemy_evolution = EvolutionScript.new(
		enemy_pop_size, ENEMY_INPUT_SIZE, ENEMY_HIDDEN_SIZE, ENEMY_OUTPUT_SIZE,
		p_elite_count, p_mutation_rate, p_mutation_strength, p_crossover_rate
	)


func get_player_network(index: int):
	## Get a player neural network by population index.
	return player_evolution.get_individual(index)


func get_enemy_network(index: int):
	## Get an enemy neural network by population index.
	return enemy_evolution.get_individual(index)


func set_player_fitness(index: int, fitness: float) -> void:
	## Set fitness for a player individual.
	player_evolution.set_fitness(index, fitness)


func set_enemy_fitness(index: int, fitness: float) -> void:
	## Set fitness for an enemy individual.
	enemy_evolution.set_fitness(index, fitness)


func evolve_both() -> void:
	## Evolve both populations simultaneously.
	## Call after all fitness scores are set for both populations.
	player_evolution.evolve()
	enemy_evolution.evolve()
	generation_complete.emit(
		get_generation(),
		player_evolution.get_best_fitness(),
		enemy_evolution.get_best_fitness()
	)


func evolve_players() -> void:
	## Evolve only the player population.
	player_evolution.evolve()


func evolve_enemies() -> void:
	## Evolve only the enemy population.
	enemy_evolution.evolve()


func get_generation() -> int:
	## Returns the player generation (both should stay in sync).
	return player_evolution.get_generation()


func get_player_population_size() -> int:
	return player_evolution.population_size


func get_enemy_population_size() -> int:
	return enemy_evolution.population_size


func get_stats() -> Dictionary:
	## Combined stats for both populations.
	return {
		"generation": get_generation(),
		"player": player_evolution.get_stats(),
		"enemy": enemy_evolution.get_stats(),
	}


func save_populations(player_path: String, enemy_path: String) -> void:
	## Save both populations to disk.
	player_evolution.save_population(player_path)
	enemy_evolution.save_population(enemy_path)


func load_populations(player_path: String, enemy_path: String) -> bool:
	## Load both populations from disk. Returns true if both loaded successfully.
	var player_ok: bool = player_evolution.load_population(player_path)
	var enemy_ok: bool = enemy_evolution.load_population(enemy_path)
	return player_ok and enemy_ok
