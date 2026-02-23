extends RefCounted
class_name EvolutionBase

signal generation_complete(generation: int, best_fitness: float, avg_fitness: float, min_fitness: float)

const STAGNATION_THRESHOLD: int = 3
const MAX_MUTATION_BOOST: float = 3.0

var population: Array = []
var population_size: int = 0
var fitness_scores: PackedFloat32Array = PackedFloat32Array()
var generation: int = 0

var mutation_rate: float = 0.0
var mutation_strength: float = 0.0
var base_mutation_rate: float = 0.0
var base_mutation_strength: float = 0.0
var stagnant_generations: int = 0
var last_best_fitness: float = 0.0

var best_fitness: float = 0.0
var all_time_best_fitness: float = 0.0

var _last_min_fitness: float = 0.0
var _last_avg_fitness: float = 0.0
var _last_max_fitness: float = 0.0

var lineage: RefCounted = null
var _lineage_ids: PackedInt32Array = PackedInt32Array()

var backup_population: Array = []
var backup_generation: int = 0

var use_nsga2: bool = false


func _init(p_population_size: int = 0, p_mutation_rate: float = 0.0, p_mutation_strength: float = 0.0) -> void:
    configure_population_size(p_population_size)
    configure_mutation(p_mutation_rate, p_mutation_strength)


func configure_population_size(size: int) -> void:
    population_size = size
    fitness_scores.resize(maxi(size, 0))
    for i in fitness_scores.size():
        fitness_scores[i] = 0.0


func configure_mutation(rate: float, strength: float) -> void:
    mutation_rate = rate
    mutation_strength = strength
    base_mutation_rate = rate
    base_mutation_strength = strength


func set_lineage_tracker(tracker: RefCounted) -> void:
    lineage = tracker


func seed_lineage(count: int, generation_index: int = 0) -> void:
    if not lineage:
        return
    var ids = lineage.record_seed(generation_index, count)
    _lineage_ids.resize(count)
    for i in count:
        _lineage_ids[i] = ids[i]


func set_fitness(index: int, fitness: float) -> void:
    if index < 0 or index >= fitness_scores.size():
        return
    fitness_scores[index] = fitness
    if lineage and index < _lineage_ids.size():
        lineage.update_fitness(_lineage_ids[index], fitness)


func get_generation() -> int:
    return generation


func get_best_fitness() -> float:
    return best_fitness


func get_all_time_best_fitness() -> float:
    return all_time_best_fitness


func track_stagnation(current_best: float, improvement_threshold: float = 1.01) -> void:
    if current_best > last_best_fitness * improvement_threshold:
        stagnant_generations = 0
        mutation_rate = base_mutation_rate
        mutation_strength = base_mutation_strength
    else:
        stagnant_generations += 1
    last_best_fitness = current_best


func apply_adaptive_mutation() -> void:
    if stagnant_generations < STAGNATION_THRESHOLD:
        return
    var mutation_boost := minf(1.0 + (stagnant_generations - STAGNATION_THRESHOLD + 1) * 0.5, MAX_MUTATION_BOOST)
    mutation_rate = minf(base_mutation_rate * mutation_boost, 0.5)
    mutation_strength = base_mutation_strength * mutation_boost
    print("  Adaptive mutation: %.0fx boost (stagnant %d gens)" % [mutation_boost, stagnant_generations])


func cache_stats(min_fit: float, avg_fit: float, max_fit: float) -> void:
    _last_min_fitness = min_fit
    _last_avg_fitness = avg_fit
    _last_max_fitness = max_fit


func save_backup() -> void:
    backup_population.clear()
    for individual in population:
        backup_population.append(_clone_individual(individual))
    backup_generation = generation


func restore_backup() -> void:
    if backup_population.is_empty():
        return
    population.clear()
    for individual in backup_population:
        population.append(_clone_individual(individual))
    generation = backup_generation
    _reset_scores()


func tournament_select(indexed_fitness: Array, tournament_size: int = 3) -> int:
    if indexed_fitness.is_empty():
        return -1
    var best_idx := -1
    var best_fit := -INF
    for i in tournament_size:
        var candidate = indexed_fitness[randi() % indexed_fitness.size()]
        if candidate.fitness > best_fit:
            best_fit = candidate.fitness
            best_idx = candidate.index
    return best_idx


func get_elite_indices(indexed_fitness: Array, elite_count: int) -> Array:
    var elites: Array = []
    if elite_count <= 0:
        return elites
    for i in mini(elite_count, indexed_fitness.size()):
        elites.append(indexed_fitness[i].index)
    return elites


func _reset_scores() -> void:
    for i in fitness_scores.size():
        fitness_scores[i] = 0.0


func get_stats() -> Dictionary:
    var min_fit := _last_min_fitness
    var max_fit := _last_max_fitness
    var avg_fit := _last_avg_fitness

    var live_scores := _get_live_fitness_samples()
    var has_live_scores := false
    for score in live_scores:
        if score != 0.0:
            has_live_scores = true
            break

    if has_live_scores:
        min_fit = INF
        max_fit = -INF
        var total := 0.0
        var count := 0
        for score in live_scores:
            min_fit = minf(min_fit, score)
            max_fit = maxf(max_fit, score)
            total += score
            count += 1
        avg_fit = total / count if count > 0 else 0.0
        if min_fit == INF:
            min_fit = 0.0
        if max_fit == -INF:
            max_fit = 0.0

    var stats := {
        "generation": generation,
        "population_size": population_size,
        "best_fitness": best_fitness,
        "all_time_best": all_time_best_fitness,
        "current_min": min_fit,
        "current_max": max_fit,
        "current_avg": avg_fit,
    }

    var extra := _get_additional_stats()
    for key in extra.keys():
        stats[key] = extra[key]
    return stats


func save_best(path: String) -> void:
    var entity = _get_all_time_best_entity()
    if entity:
        _save_entity(path, entity)


func load_best(path: String) -> void:
    var entity = _load_entity(path)
    if entity:
        _set_all_time_best_entity(entity)
        all_time_best_fitness = 0.0


func save_population(path: String) -> void:
    _save_population_impl(path)


func load_population(path: String) -> bool:
    return _load_population_impl(path)


func _get_live_fitness_samples() -> Array:
    return fitness_scores


func _get_additional_stats() -> Dictionary:
    return {}


func _clone_individual(individual):
    push_error("_clone_individual must be implemented by subclasses")
    return null


func _get_all_time_best_entity():
    return null


func _set_all_time_best_entity(entity) -> void:
    pass


func _save_entity(path: String, entity) -> void:
    push_error("_save_entity must be implemented by subclasses")


func _load_entity(path: String):
    push_error("_load_entity must be implemented by subclasses")
    return null


func _save_population_impl(path: String) -> void:
    push_error("_save_population_impl must be implemented by subclasses")


func _load_population_impl(path: String) -> bool:
    push_error("_load_population_impl must be implemented by subclasses")
    return false
