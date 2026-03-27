extends RefCounted
class_name TrainingModeBase

## Base class for training manager modes.
## Each mode implements enter/exit/process/handle_input.
## ctx is a reference to the training_manager node.

## Score awarded per second of survival. survival_score = survival_time * SURVIVAL_UNIT_SCORE
## Independent of kill/powerup scores.
const SURVIVAL_UNIT_SCORE: float = 1000.0

var ctx  # training_manager reference


func enter(context) -> void:
    ctx = context


func exit() -> void:
    pass


func process(_delta: float) -> void:
    pass


func handle_input(_event: InputEvent) -> void:
    pass


func get_eval_states() -> Array:
    return []


# ============================================================
# Metrics helpers (shared by StandardTrainingMode and CoevolutionMode)
# ============================================================

func write_metrics_for_wandb() -> void:
    ## Write W&B metrics JSON. Call at end of each generation and at training stop.
    ctx.metrics_writer.write_wandb_metrics(_build_wandb_state(), ctx.config.get_metrics_path())


func _build_wandb_state() -> Dictionary:
    var state := {
        "generation": ctx.generation,
        "best_fitness": ctx.best_fitness,
        "avg_fitness": ctx.history_avg_fitness[-1] if ctx.history_avg_fitness.size() > 0 else 0.0,
        "min_fitness": ctx.history_min_fitness[-1] if ctx.history_min_fitness.size() > 0 else 0.0,
        "avg_kill_score": (
                ctx.history_avg_kill_score[-1] if ctx.history_avg_kill_score.size() > 0 else 0.0),
        "avg_powerup_score": (
                ctx.history_avg_powerup_score[-1]
                if ctx.history_avg_powerup_score.size() > 0 else 0.0),
        "avg_survival_score": (
                ctx.history_avg_survival_score[-1]
                if ctx.history_avg_survival_score.size() > 0 else 0.0),
        "all_time_best": ctx.all_time_best,
        "generations_without_improvement": ctx.generations_without_improvement,
        "population_size": ctx.population_size,
        "evals_per_individual": ctx.evals_per_individual,
        "time_scale": ctx.time_scale,
        "training_complete": ctx.training_ui.training_complete,
        "curriculum_stage": ctx.curriculum_stage,
        "curriculum_enabled": ctx.config.curriculum_enabled,
        "curriculum_label": ctx.get_curriculum_label(),
        "use_nsga2": ctx.use_nsga2,
        "pareto_front_size": ctx.evolution.pareto_front.size() if ctx.evolution and ctx.use_nsga2 else 0,
        "hypervolume": ctx.evolution.last_hypervolume if ctx.evolution and ctx.use_nsga2 else 0.0,
        "use_neat": ctx.use_neat,
        "neat_species_count": (
                ctx.evolution.get_stats().species_count if ctx.evolution and ctx.use_neat else 0),
        "neat_compatibility_threshold": (
                ctx.evolution.get_stats().compatibility_threshold
                if ctx.evolution and ctx.use_neat else 0.0),
        "use_memory": ctx.use_memory,
        "use_map_elites": ctx.use_map_elites,
        "map_elites_occupied": ctx.map_elites_archive.get_occupied_count() if ctx.map_elites_archive else 0,
        "map_elites_coverage": ctx.map_elites_archive.get_coverage() if ctx.map_elites_archive else 0.0,
        "map_elites_best": ctx.map_elites_archive.get_best_fitness() if ctx.map_elites_archive else 0.0,
    }
    if ctx.coevolution:
        var e_stats = ctx.coevolution.enemy_evolution.get_stats()
        state["coevolution"] = true
        state["enemy_best_fitness"] = e_stats.best_fitness
        state["enemy_all_time_best"] = e_stats.all_time_best
        state["enemy_avg_fitness"] = e_stats.current_avg
        state["enemy_min_fitness"] = e_stats.current_min
        state["hof_size"] = ctx.coevolution.get_hof_size()
        state["is_hof_generation"] = ctx.coevo_is_hof_generation
    return state
