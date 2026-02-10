extends RefCounted
## Tracks fitness accumulation across seeds, metric history, and generation score breakdowns.
## Extracted from training_manager.gd to reduce its responsibility.

# Fitness tracking — accumulate across multiple seeds per individual
var fitness_accumulator: Dictionary = {}  # {individual_index: [seed1_fitness, seed2_fitness, ...]}

# Multi-objective tracking (NSGA-II)
var objective_accumulator: Dictionary = {}  # {individual_index: [Vector3(survival, kills, powerups), ...per seed]}

# MAP-Elites behavior tracking
var behavior_accumulator: Dictionary = {}  # {individual_index: [{kills, powerups_collected, survival_time}, ...per seed]}

# Per-generation score breakdown accumulators
var generation_total_kill_score: float = 0.0
var generation_total_powerup_score: float = 0.0
var generation_total_survival_score: float = 0.0

# Metric history for graphing
var history_best_fitness: Array[float] = []
var history_avg_fitness: Array[float] = []
var history_min_fitness: Array[float] = []
var history_avg_kill_score: Array[float] = []
var history_avg_powerup_score: Array[float] = []
var history_avg_survival_score: Array[float] = []


func reset() -> void:
	## Clear all accumulators and history for a new training run.
	fitness_accumulator.clear()
	objective_accumulator.clear()
	behavior_accumulator.clear()
	generation_total_kill_score = 0.0
	generation_total_powerup_score = 0.0
	generation_total_survival_score = 0.0
	history_best_fitness.clear()
	history_avg_fitness.clear()
	history_min_fitness.clear()
	history_avg_kill_score.clear()
	history_avg_powerup_score.clear()
	history_avg_survival_score.clear()


func clear_accumulators() -> void:
	## Clear per-generation accumulators (between generations, not history).
	fitness_accumulator.clear()
	objective_accumulator.clear()
	behavior_accumulator.clear()


func record_eval_result(individual_index: int, fitness: float, kill_score: float, powerup_score: float, survival_score: float) -> void:
	## Record a single evaluation result for an individual.
	if not fitness_accumulator.has(individual_index):
		fitness_accumulator[individual_index] = []
	fitness_accumulator[individual_index].append(fitness)

	if not objective_accumulator.has(individual_index):
		objective_accumulator[individual_index] = []
	objective_accumulator[individual_index].append(Vector3(survival_score, kill_score, powerup_score))

	# Accumulate generation totals
	generation_total_kill_score += kill_score
	generation_total_powerup_score += powerup_score
	generation_total_survival_score += survival_score


func record_behavior(individual_index: int, kills: float, powerups_collected: float, survival_time: float) -> void:
	## Record MAP-Elites behavior data for an individual evaluation.
	if not behavior_accumulator.has(individual_index):
		behavior_accumulator[individual_index] = []
	behavior_accumulator[individual_index].append({
		"kills": kills,
		"powerups_collected": powerups_collected,
		"survival_time": survival_time,
	})


func record_generation(best: float, avg: float, min_fit: float, population_size: int, evals_per_individual: int) -> Dictionary:
	## Record end-of-generation metrics and return the score breakdown averages.
	## Call this from _on_generation_complete.
	history_best_fitness.append(best)
	history_avg_fitness.append(avg)
	history_min_fitness.append(min_fit)

	var total_evals := population_size * evals_per_individual
	var avg_kill_score := generation_total_kill_score / total_evals
	var avg_powerup_score := generation_total_powerup_score / total_evals
	var avg_survival_score := generation_total_survival_score / total_evals
	history_avg_kill_score.append(avg_kill_score)
	history_avg_powerup_score.append(avg_powerup_score)
	history_avg_survival_score.append(avg_survival_score)

	# Reset generation accumulators for next generation
	generation_total_kill_score = 0.0
	generation_total_powerup_score = 0.0
	generation_total_survival_score = 0.0

	return {
		"avg_kill_score": avg_kill_score,
		"avg_powerup_score": avg_powerup_score,
		"avg_survival_score": avg_survival_score,
	}


func get_avg_fitness(individual_index: int) -> float:
	## Get average fitness across seeds for an individual.
	var scores: Array = fitness_accumulator.get(individual_index, [0.0])
	var total: float = 0.0
	for s in scores:
		total += s
	return total / scores.size()


func get_avg_objectives(individual_index: int) -> Vector3:
	## Get average objectives across seeds for an individual (NSGA-II).
	var obj_scores: Array = objective_accumulator.get(individual_index, [Vector3.ZERO])
	var avg_obj := Vector3.ZERO
	for o in obj_scores:
		avg_obj += o
	avg_obj /= obj_scores.size()
	return avg_obj


func get_avg_behavior(individual_index: int) -> Dictionary:
	## Get average behavior stats across seeds for MAP-Elites.
	var beh_list: Array = behavior_accumulator.get(individual_index, [])
	if beh_list.is_empty():
		return {}
	var avg_kills: float = 0.0
	var avg_powerups: float = 0.0
	var avg_survival: float = 0.0
	for s in beh_list:
		avg_kills += s.kills
		avg_powerups += s.powerups_collected
		avg_survival += s.survival_time
	avg_kills /= beh_list.size()
	avg_powerups /= beh_list.size()
	avg_survival /= beh_list.size()
	return {
		"kills": avg_kills,
		"powerups_collected": avg_powerups,
		"survival_time": avg_survival,
	}


func get_max_history_value() -> float:
	## Get max value across all history arrays (for graph scaling).
	var max_val = 100.0  # Minimum scale
	for v in history_best_fitness:
		max_val = maxf(max_val, v)
	for v in history_avg_fitness:
		max_val = maxf(max_val, v)
	for v in history_avg_survival_score:
		max_val = maxf(max_val, v)
	for v in history_avg_kill_score:
		max_val = maxf(max_val, v)
	for v in history_avg_powerup_score:
		max_val = maxf(max_val, v)
	# Round up to nice number
	if max_val <= 100:
		return 100.0
	elif max_val <= 500:
		return ceilf(max_val / 100.0) * 100.0
	else:
		return ceilf(max_val / 500.0) * 500.0
