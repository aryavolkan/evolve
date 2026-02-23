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
var NeuralNetworkScript = preload("res://ai/neural_network.gd")

# Enemy network architecture constants
const ENEMY_INPUT_SIZE: int = 16   # From EnemySensor.TOTAL_INPUTS
const ENEMY_HIDDEN_SIZE: int = 16  # Smaller than player (32), enemies are simpler
const ENEMY_OUTPUT_SIZE: int = 8   # 8 directional preferences (N, NE, E, SE, S, SW, W, NW)

# Hall of Fame constants
const HOF_SIZE: int = 5              # Top-5 enemy networks archived per generation
const HOF_EVAL_INTERVAL: int = 5     # Evaluate players against HoF every N generations

var player_evolution = null  # Evolution instance for player population
var enemy_evolution = null   # Evolution instance for enemy population

# Hall of Fame: archived top enemy networks to prevent Red Queen cycling
var hall_of_fame: Array = []  # Array of {network, fitness, generation}


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
    ## Updates Hall of Fame before evolving enemies (so elite networks are archived).
    update_hall_of_fame()
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


# ============================================================
# Hall of Fame
# ============================================================

func update_hall_of_fame() -> void:
    ## Archive the top HOF_SIZE enemy networks from the current generation.
    ## Call after fitness is set but before evolve() mutates the population.
    var indexed: Array = []
    for i in enemy_evolution.population_size:
        indexed.append({"index": i, "fitness": enemy_evolution.fitness_scores[i]})
    indexed.sort_custom(func(a, b): return a.fitness > b.fitness)

    for i in mini(HOF_SIZE, indexed.size()):
        var net = enemy_evolution.get_individual(indexed[i].index).clone()
        hall_of_fame.append({
            "network": net,
            "fitness": indexed[i].fitness,
            "generation": get_generation(),
        })

    # Trim to keep only the best HOF_SIZE across all generations
    # Sort by fitness descending, keep top HOF_SIZE
    hall_of_fame.sort_custom(func(a, b): return a.fitness > b.fitness)
    if hall_of_fame.size() > HOF_SIZE:
        hall_of_fame.resize(HOF_SIZE)


func should_eval_against_hof() -> bool:
    ## Returns true if the current generation should evaluate players against HoF.
    if hall_of_fame.is_empty():
        return false
    return get_generation() > 0 and get_generation() % HOF_EVAL_INTERVAL == 0


func get_hof_networks() -> Array:
    ## Return the Hall of Fame enemy networks for evaluation.
    var networks: Array = []
    for entry in hall_of_fame:
        networks.append(entry.network)
    return networks


func get_hof_size() -> int:
    return hall_of_fame.size()


# ============================================================
# Adversarial Fitness Calculation
# ============================================================

static func compute_enemy_fitness(
    damage_dealt: float,
    proximity_pressure: float,
    player_survival_time: float,
    forced_direction_changes: float
) -> float:
    ## Calculate enemy fitness from arena evaluation results.
    ##
    ## Components:
    ##   +damage_dealt: hits landed on the player (lives lost × 1000)
    ##   +proximity_pressure: time-averaged closeness to player (0-1 scale × 100)
    ##   -player_survival_time: seconds the player survived (penalty)
    ##   +forced_direction_changes: times player changed move direction significantly
    ##
    ## Higher is better for enemies.
    var fitness := 0.0
    fitness += damage_dealt * 1000.0             # Each hit is very valuable
    fitness += proximity_pressure * 100.0         # Reward pressure
    fitness -= player_survival_time * 5.0         # Penalize long player survival
    fitness += forced_direction_changes * 10.0    # Reward forcing evasion
    # Clamp to prevent negative fitness (evolution works better with non-negative)
    return maxf(fitness, 0.0)


# ============================================================
# Save / Load
# ============================================================

func save_populations(player_path: String, enemy_path: String) -> void:
    ## Save both populations to disk.
    player_evolution.save_population(player_path)
    enemy_evolution.save_population(enemy_path)


func load_populations(player_path: String, enemy_path: String) -> bool:
    ## Load both populations from disk. Returns true if both loaded successfully.
    var player_ok: bool = player_evolution.load_population(player_path)
    var enemy_ok: bool = enemy_evolution.load_population(enemy_path)
    return player_ok and enemy_ok


func save_hall_of_fame(path: String) -> void:
    ## Save Hall of Fame networks to disk.
    var file := FileAccess.open(path, FileAccess.WRITE)
    if not file:
        return
    file.store_32(hall_of_fame.size())
    for entry in hall_of_fame:
        file.store_float(entry.fitness)
        file.store_32(entry.generation)
        var weights: PackedFloat32Array = entry.network.get_weights()
        file.store_32(weights.size())
        for w in weights:
            file.store_float(w)
    file.close()


func load_hall_of_fame(path: String) -> bool:
    ## Load Hall of Fame networks from disk. Returns true on success.
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return false
    hall_of_fame.clear()
    var count := file.get_32()
    for i in count:
        var fitness := file.get_float()
        var gen := file.get_32()
        var weight_count := file.get_32()
        var weights := PackedFloat32Array()
        weights.resize(weight_count)
        for j in weight_count:
            weights[j] = file.get_float()
        var net = NeuralNetworkScript.new(ENEMY_INPUT_SIZE, ENEMY_HIDDEN_SIZE, ENEMY_OUTPUT_SIZE)
        net.set_weights(weights)
        hall_of_fame.append({
            "network": net,
            "fitness": fitness,
            "generation": gen,
        })
    file.close()
    return true
