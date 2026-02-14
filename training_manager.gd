extends Node

## Training Manager - Thin dispatcher that delegates to active mode objects.

signal training_status_changed(status: String)
signal stats_updated(stats: Dictionary)

enum Mode { HUMAN, TRAINING, PLAYBACK, GENERATION_PLAYBACK, ARCHIVE_PLAYBACK, COEVOLUTION, SANDBOX, COMPARISON, RTNEAT, TEAMS }

var current_mode: Mode = Mode.HUMAN
var _active_mode: TrainingModeBase = null

# Training components
var evolution = null
var current_batch_start: int = 0

# References
var main_scene: Node2D
var player: CharacterBody2D

# Configuration (centralized in TrainingConfig)
var config: RefCounted = preload("res://ai/training_config.gd").new()
var arena_pool: RefCounted = preload("res://ai/arena_pool.gd").new()
var population_size: int:
	get: return config.population_size
	set(v): config.population_size = v
var max_generations: int:
	get: return config.max_generations
	set(v): config.max_generations = v
var time_scale: float:
	get: return config.time_scale
	set(v): config.time_scale = v
var parallel_count: int:
	get: return config.parallel_count
	set(v): config.parallel_count = v
var evals_per_individual: int:
	get: return config.evals_per_individual
	set(v): config.evals_per_individual = v

# Rolling evaluation
var next_individual: int = 0
var evaluated_count: int = 0
var current_eval_seed: int = 0

# Stats tracking (delegated to StatsTracker)
var stats_tracker: RefCounted = preload("res://ai/stats_tracker.gd").new()

# Extracted modules
var migration_mgr: RefCounted = preload("res://ai/migration_manager.gd").new()
var metrics_writer: RefCounted = preload("res://ai/metrics_writer.gd").new()
var playback_mgr: RefCounted = preload("res://ai/playback_manager.gd").new()
var training_ui: RefCounted = preload("res://ai/training_ui.gd").new()
var training_overrides: Dictionary = {}
const SandboxTrainingModeScript = preload("res://modes/sandbox_training_mode.gd")

# Multi-objective tracking (NSGA-II)
var use_nsga2: bool:
	get: return config.use_nsga2
	set(v): config.use_nsga2 = v

# NEAT topology evolution
var use_neat: bool:
	get: return config.use_neat
	set(v): config.use_neat = v

# Elman recurrent memory
var use_memory: bool:
	get: return config.use_memory
	set(v): config.use_memory = v

# MAP-Elites quality-diversity archive
var use_map_elites: bool:
	get: return config.use_map_elites
	set(v): config.use_map_elites = v
var map_elites_archive: MapElites = null

# Co-evolution (Track A)
var coevolution = null
var CoevolutionScript = preload("res://ai/coevolution.gd")
var EnemyAIControllerScript = preload("res://ai/enemy_ai_controller.gd")
var coevo_enemy_fitness: Dictionary = {}
var coevo_enemy_stats: Dictionary = {}
var coevo_is_hof_generation: bool = false

# rtNEAT continuous evolution
var rtneat_mgr = null

# Team battle mode
var TeamManagerScript = null  # Lazy-loaded to avoid headless parse issues
var team_mgr = null

# Lineage tracking
var lineage_tracker: RefCounted = null
var LineageTrackerScript = preload("res://ai/lineage_tracker.gd")

# Co-evolution paths (aliases from config)
var ENEMY_POPULATION_PATH: String:
	get: return config.ENEMY_POPULATION_PATH
var ENEMY_HOF_PATH: String:
	get: return config.ENEMY_HOF_PATH

# Pre-generated events for each seed
var generation_events_by_seed: Array = []

# Path aliases
var BEST_NETWORK_PATH: String:
	get: return config.BEST_NETWORK_PATH
var POPULATION_PATH: String:
	get: return config.POPULATION_PATH
var MIGRATION_POOL_DIR: String:
	get: return config.MIGRATION_POOL_DIR

# Stats
var generation: int = 0
var best_fitness: float = 0.0
var all_time_best: float = 0.0

# Early stopping
var stagnation_limit: int = 10
var generations_without_improvement: int = 0
var best_avg_fitness: float = 0.0

# Curriculum learning
var CurriculumManagerScript = preload("res://ai/curriculum_manager.gd")
var curriculum: RefCounted = preload("res://ai/curriculum_manager.gd").new()

# Backward-compatible curriculum accessors
var curriculum_enabled: bool:
	get: return curriculum.enabled if curriculum else true
	set(v):
		if curriculum:
			curriculum.enabled = v
var curriculum_stage: int:
	get: return curriculum.stage if curriculum else 0
	set(v):
		if curriculum:
			curriculum.stage = v
var curriculum_generations_at_stage: int:
	get: return curriculum.generations_at_stage if curriculum else 0
	set(v):
		if curriculum:
			curriculum.generations_at_stage = v
var CURRICULUM_STAGES: Array[Dictionary]:
	get: return CurriculumManagerScript.STAGES

# Generation rollback
var previous_avg_fitness: float = 0.0
var rerun_count: int = 0
const MAX_RERUNS: int = 0

# Backward-compatible playback accessors
var playback_generation: int:
	get: return playback_mgr.playback_generation
	set(v): playback_mgr.playback_generation = v
var max_playback_generation: int:
	get: return playback_mgr.max_playback_generation
	set(v): playback_mgr.max_playback_generation = v
var generation_networks: Array:
	get: return playback_mgr.generation_networks
var archive_playback_cell: Vector2i:
	get: return playback_mgr.archive_playback_cell
	set(v): playback_mgr.archive_playback_cell = v
var archive_playback_fitness: float:
	get: return playback_mgr.archive_playback_fitness
	set(v): playback_mgr.archive_playback_fitness = v
var sandbox_config: Dictionary:
	get: return playback_mgr.sandbox_config
	set(v): playback_mgr.sandbox_config = v
var comparison_strategies: Array:
	get: return playback_mgr.comparison_strategies
	set(v): playback_mgr.comparison_strategies = v
var comparison_instances: Array:
	get: return playback_mgr.comparison_instances
	set(v): playback_mgr.comparison_instances = v

# Parallel training instances
var eval_instances: Array = []
var ai_controller = null

# Metric history — delegated to stats_tracker
var history_best_fitness: Array[float]:
	get: return stats_tracker.history_best_fitness
var history_avg_fitness: Array[float]:
	get: return stats_tracker.history_avg_fitness
var history_min_fitness: Array[float]:
	get: return stats_tracker.history_min_fitness
var history_avg_kill_score: Array[float]:
	get: return stats_tracker.history_avg_kill_score
var history_avg_powerup_score: Array[float]:
	get: return stats_tracker.history_avg_powerup_score
var history_avg_survival_score: Array[float]:
	get: return stats_tracker.history_avg_survival_score
var generation_total_kill_score: float:
	get: return stats_tracker.generation_total_kill_score
var generation_total_powerup_score: float:
	get: return stats_tracker.generation_total_powerup_score
var generation_total_survival_score: float:
	get: return stats_tracker.generation_total_survival_score

# Pause state — delegated to training_ui
var is_paused: bool:
	get: return training_ui.is_paused
	set(v): training_ui.is_paused = v
var pause_overlay: Control:
	get: return training_ui.pause_overlay
	set(v): training_ui.pause_overlay = v
var training_complete: bool:
	get: return training_ui.training_complete
	set(v): training_ui.training_complete = v

# Fullscreen arena view
var fullscreen_arena_index: int:
	get: return arena_pool.fullscreen_index if arena_pool else -1
	set(v):
		if arena_pool:
			arena_pool.fullscreen_index = v
var training_container: Control:
	get: return arena_pool.container if arena_pool else null

# Preloaded scripts
var NeuralNetworkScript = preload("res://ai/neural_network.gd")
var AISensorScript = preload("res://ai/sensor.gd")
var AIControllerScript = preload("res://ai/ai_controller.gd")
var EvolutionScript = preload("res://ai/evolution.gd")
var NeatEvolutionScript = preload("res://ai/neat_evolution.gd")
var NeatNetworkScript = preload("res://ai/neat_network.gd")
var MainScenePacked = preload("res://main.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	training_ui.setup(stats_tracker, arena_pool)
	training_ui.heatmap_cell_clicked.connect(_on_heatmap_cell_clicked)
	training_ui.replay_best_requested.connect(_start_best_replay)
	training_ui.training_exited.connect(_on_training_exited)


func _input(event: InputEvent) -> void:
	if _active_mode:
		_active_mode.handle_input(event)


func initialize(scene: Node2D) -> void:
	main_scene = scene
	player = scene.get_node("Player")

	ai_controller = AIControllerScript.new()
	ai_controller.set_player(player)

	playback_mgr.setup({
		"main_scene": main_scene,
		"player": player,
		"ai_controller": ai_controller,
		"arena_pool": arena_pool,
		"NeuralNetworkScript": NeuralNetworkScript,
		"AIControllerScript": AIControllerScript,
		"MainScenePacked": MainScenePacked,
		"BEST_NETWORK_PATH": BEST_NETWORK_PATH,
		"hide_main_game": hide_main_game,
		"show_main_game": show_main_game,
	})
	playback_mgr.status_changed.connect(func(s): training_status_changed.emit(s))


# ============================================================
# Mode transitions
# ============================================================

func _change_mode(mode_enum: Mode, mode_instance: TrainingModeBase = null) -> void:
	if _active_mode:
		_active_mode.exit()
	current_mode = mode_enum
	_active_mode = mode_instance
	if _active_mode:
		_active_mode.enter(self)


# ============================================================
# Public API — start/stop modes
# ============================================================

func _load_sweep_config(fallback_pop_size: int = 150, fallback_max_gen: int = 100) -> void:
	config.load_from_sweep(fallback_pop_size, fallback_max_gen)


func start_training(pop_size: int = 100, generations: int = 100) -> void:
	if not main_scene:
		push_error("Training manager not initialized")
		return
	var mode = StandardTrainingMode.new()
	mode.pop_size = pop_size
	mode.max_generations = generations
	_change_mode(Mode.TRAINING, mode)


func stop_training() -> void:
	if current_mode != Mode.TRAINING:
		if current_mode == Mode.COEVOLUTION:
			stop_coevolution_training()
		return
	_change_mode(Mode.HUMAN)


func start_coevolution_training(pop_size: int = 100, generations: int = 100) -> void:
	if not main_scene:
		push_error("Training manager not initialized")
		return
	var mode = CoevolutionMode.new()
	mode.pop_size = pop_size
	mode.max_generations = generations
	_change_mode(Mode.COEVOLUTION, mode)


func stop_coevolution_training() -> void:
	if current_mode != Mode.COEVOLUTION:
		return
	_change_mode(Mode.HUMAN)


func start_rtneat(rtneat_config: Dictionary = {}) -> void:
	if not main_scene:
		push_error("Training manager not initialized")
		return
	var mode = RtNeatMode.new()
	mode.rtneat_config = rtneat_config
	_change_mode(Mode.RTNEAT, mode)


func stop_rtneat() -> void:
	if current_mode != Mode.RTNEAT:
		return
	_change_mode(Mode.HUMAN)


func start_rtneat_teams(rtneat_config: Dictionary = {}) -> void:
	if not main_scene:
		push_error("Training manager not initialized")
		return
	var mode = TeamsMode.new()
	mode.teams_config = rtneat_config
	_change_mode(Mode.TEAMS, mode)


func stop_rtneat_teams() -> void:
	if current_mode != Mode.TEAMS:
		return
	_change_mode(Mode.HUMAN)


func start_playback() -> void:
	_change_mode(Mode.PLAYBACK, PlaybackMode.new())


func stop_playback() -> void:
	_change_mode(Mode.HUMAN)


func start_generation_playback() -> void:
	_change_mode(Mode.GENERATION_PLAYBACK, GenerationPlaybackMode.new())


func advance_generation_playback() -> void:
	playback_mgr.advance_generation_playback()


func start_archive_playback(cell: Vector2i) -> void:
	if current_mode == Mode.TRAINING:
		stop_training()
	var mode = ArchivePlaybackMode.new()
	mode.cell = cell
	_change_mode(Mode.ARCHIVE_PLAYBACK, mode)


func stop_archive_playback() -> void:
	_change_mode(Mode.HUMAN)


func start_sandbox(sandbox_cfg: Dictionary) -> void:
	var mode = SandboxMode.new()
	mode.sandbox_cfg = sandbox_cfg
	_change_mode(Mode.SANDBOX, mode)


func stop_sandbox() -> void:
	if current_mode != Mode.SANDBOX:
		return
	_change_mode(Mode.HUMAN)


func start_sandbox_training(config: Dictionary) -> void:
	if not main_scene:
		push_error("Training manager not initialized")
		return
	var mode = SandboxTrainingModeScript.new()
	mode.sandbox_cfg = config
	mode.pop_size = config.get("population_size", population_size)
	mode.max_generations = config.get("max_generations", max_generations)
	_change_mode(Mode.TRAINING, mode)


func start_comparison(strategies: Array) -> void:
	var mode = ComparisonMode.new()
	mode.strategies = strategies
	_change_mode(Mode.COMPARISON, mode)


func stop_comparison() -> void:
	if current_mode != Mode.COMPARISON:
		return
	_change_mode(Mode.HUMAN)


# ============================================================
# Physics process — dispatches to active mode
# ============================================================

func _physics_process(delta: float) -> void:
	if current_mode == Mode.HUMAN:
		return
	if training_ui.is_paused:
		return
	if _active_mode:
		_active_mode.process(delta)


# ============================================================
# Shared helpers (used by mode objects via ctx)
# ============================================================

func generate_all_seed_events() -> void:
	generation_events_by_seed.clear()
	var MainScene = load("res://main.gd")
	var curr_config = get_current_curriculum_config()
	for seed_idx in evals_per_individual:
		var seed_val = generation * 1000 + seed_idx
		var events = MainScene.generate_random_events(seed_val, curr_config, training_overrides)
		generation_events_by_seed.append(events)


func hide_main_game() -> void:
	main_scene.visible = false
	player.set_physics_process(false)
	var canvas_layer = main_scene.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.visible = false


func show_main_game() -> void:
	main_scene.visible = true
	player.set_physics_process(true)
	player.enable_ai_control(false)
	var canvas_layer = main_scene.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.visible = true
	main_scene.get_tree().paused = false


func get_window_size() -> Vector2:
	return arena_pool.get_window_size() if arena_pool else get_viewport().get_visible_rect().size


func create_training_container() -> void:
	arena_pool.setup(get_tree(), parallel_count)


func get_grid_dimensions() -> Dictionary:
	return arena_pool.get_grid_dimensions()


func reset_game() -> void:
	playback_mgr.reset_game()


func set_training_overrides(overrides: Dictionary) -> void:
	training_overrides = overrides.duplicate(true) if overrides else {}


func clear_training_overrides() -> void:
	training_overrides.clear()


func get_training_overrides() -> Dictionary:
	return training_overrides


func apply_training_overrides_to_scene(scene: Node2D) -> void:
	if training_overrides.is_empty():
		return
	if scene.has_method("apply_sandbox_overrides"):
		scene.apply_sandbox_overrides(training_overrides)


# ============================================================
# Curriculum learning
# ============================================================

func get_current_curriculum_config() -> Dictionary:
	if not training_overrides.is_empty():
		var override_config: Dictionary = {}
		if training_overrides.has("enemy_types"):
			override_config["enemy_types"] = training_overrides.get("enemy_types", [])
		if training_overrides.has("powerup_types"):
			override_config["powerup_types"] = training_overrides.get("powerup_types", [])
		if training_overrides.has("arena_scale"):
			override_config["arena_scale"] = training_overrides.get("arena_scale", 1.0)
		if not override_config.is_empty():
			return override_config
	return curriculum.get_current_config()


func check_curriculum_advancement() -> bool:
	var advanced = curriculum.check_advancement(history_avg_fitness)
	if advanced:
		generations_without_improvement = 0
		best_avg_fitness = 0.0
	return advanced


func get_curriculum_label() -> String:
	return curriculum.get_label()


# ============================================================
# Pause (thin delegation to training_ui)
# ============================================================

func toggle_pause() -> void:
	if current_mode != Mode.TRAINING and current_mode != Mode.COEVOLUTION:
		return
	training_ui.toggle_pause(_build_pause_state(), eval_instances)


func _show_training_complete(reason: String) -> void:
	if evolution:
		evolution.save_best(BEST_NETWORK_PATH)
		evolution.save_population(POPULATION_PATH)
	if coevolution:
		coevolution.player_evolution.save_best(BEST_NETWORK_PATH)
		coevolution.save_populations(POPULATION_PATH, ENEMY_POPULATION_PATH)
		coevolution.save_hall_of_fame(ENEMY_HOF_PATH)
	training_ui.show_complete(reason, _build_pause_state(), eval_instances)


# Backward-compatible alias
func show_training_complete(reason: String) -> void:
	_show_training_complete(reason)


func pause_training() -> void:
	training_ui.pause(_build_pause_state(), eval_instances)


func resume_training() -> void:
	training_ui.resume(eval_instances)


func destroy_pause_overlay() -> void:
	training_ui.destroy_pause_overlay()


func _build_pause_state() -> Dictionary:
	var state := {
		"generation": generation,
		"best_fitness": best_fitness,
		"all_time_best": all_time_best,
		"avg_fitness": history_avg_fitness[-1] if history_avg_fitness.size() > 0 else 0.0,
		"generations_without_improvement": generations_without_improvement,
		"stagnation_limit": stagnation_limit,
	}
	if use_map_elites and map_elites_archive and map_elites_archive.get_occupied_count() > 0:
		state["has_heatmap"] = true
		state["heatmap_data"] = {
			"grid": map_elites_archive.get_archive_grid(),
			"grid_size": map_elites_archive.grid_size,
			"best_fitness": map_elites_archive.get_best_fitness(),
			"behavior_mins": map_elites_archive.behavior_mins,
			"behavior_maxs": map_elites_archive.behavior_maxs,
		}
	else:
		state["has_heatmap"] = false
	return state


# ============================================================
# Signal handlers
# ============================================================

func _on_heatmap_cell_clicked(cell: Vector2i) -> void:
	if not map_elites_archive:
		return
	var elite = map_elites_archive.get_elite(cell)
	if elite == null:
		print("No elite at cell (%d, %d)" % [cell.x, cell.y])
		return

	if training_ui.is_paused:
		training_ui.destroy_pause_overlay()
		training_ui.is_paused = false

	current_mode = Mode.HUMAN
	if _active_mode:
		_active_mode.exit()
		_active_mode = null
	Engine.time_scale = 1.0
	eval_instances.clear()
	arena_pool.destroy()

	show_main_game()
	start_archive_playback(cell)


func _on_training_exited() -> void:
	if current_mode == Mode.COEVOLUTION:
		stop_coevolution_training()
	else:
		stop_training()


func _start_best_replay() -> void:
	if training_ui.is_paused:
		training_ui.destroy_pause_overlay()
		training_ui.is_paused = false

	eval_instances.clear()
	arena_pool.destroy()

	show_main_game()
	Engine.time_scale = 1.0

	var network = null
	var genome = null
	if use_neat and evolution and evolution.all_time_best_genome:
		genome = evolution.all_time_best_genome
		network = NeatNetworkScript.from_genome(genome)
	else:
		network = NeuralNetworkScript.load_from_file(BEST_NETWORK_PATH)

	if not network:
		push_error("No best network available for replay")
		current_mode = Mode.HUMAN
		_active_mode = null
		training_status_changed.emit("Training complete (no network to replay)")
		return

	current_mode = Mode.PLAYBACK
	_active_mode = null  # Playback driven by ai_controller directly
	ai_controller.set_network(network)
	player.enable_ai_control(true)
	playback_mgr.reset_game()

	if main_scene.network_visualizer:
		if genome and network is NeatNetwork:
			main_scene.network_visualizer.set_neat_data(genome, network)
		else:
			main_scene.network_visualizer.set_fixed_network(network)
		main_scene.network_visualizer.visible = true

	training_status_changed.emit("Replaying best network (fitness: %.1f)" % all_time_best)
	print("Auto-replaying best network (fitness: %.1f)" % all_time_best)


# ============================================================
# Metrics (thin delegation to metrics_writer)
# ============================================================

func _build_wandb_state() -> Dictionary:
	var state = {
		"generation": generation,
		"best_fitness": best_fitness,
		"avg_fitness": history_avg_fitness[-1] if history_avg_fitness.size() > 0 else 0.0,
		"min_fitness": history_min_fitness[-1] if history_min_fitness.size() > 0 else 0.0,
		"avg_kill_score": history_avg_kill_score[-1] if history_avg_kill_score.size() > 0 else 0.0,
		"avg_powerup_score": history_avg_powerup_score[-1] if history_avg_powerup_score.size() > 0 else 0.0,
		"avg_survival_score": history_avg_survival_score[-1] if history_avg_survival_score.size() > 0 else 0.0,
		"all_time_best": all_time_best,
		"generations_without_improvement": generations_without_improvement,
		"population_size": population_size,
		"evals_per_individual": evals_per_individual,
		"time_scale": time_scale,
		"training_complete": training_ui.training_complete,
		"curriculum_stage": curriculum_stage,
		"curriculum_label": get_curriculum_label(),
		"use_nsga2": use_nsga2,
		"pareto_front_size": evolution.pareto_front.size() if evolution and use_nsga2 else 0,
		"hypervolume": evolution.last_hypervolume if evolution and use_nsga2 else 0.0,
		"use_neat": use_neat,
		"neat_species_count": evolution.get_stats().species_count if evolution and use_neat else 0,
		"neat_compatibility_threshold": evolution.get_stats().compatibility_threshold if evolution and use_neat else 0.0,
		"use_memory": use_memory,
		"use_map_elites": use_map_elites,
		"map_elites_occupied": map_elites_archive.get_occupied_count() if map_elites_archive else 0,
		"map_elites_coverage": map_elites_archive.get_coverage() if map_elites_archive else 0.0,
		"map_elites_best": map_elites_archive.get_best_fitness() if map_elites_archive else 0.0,
	}
	if coevolution:
		var e_stats = coevolution.enemy_evolution.get_stats()
		state["coevolution"] = true
		state["enemy_best_fitness"] = e_stats.best_fitness
		state["enemy_all_time_best"] = e_stats.all_time_best
		state["enemy_avg_fitness"] = e_stats.current_avg
		state["enemy_min_fitness"] = e_stats.current_min
		state["hof_size"] = coevolution.get_hof_size()
		state["is_hof_generation"] = coevo_is_hof_generation
	return state


func _write_metrics_for_wandb() -> void:
	metrics_writer.write_wandb_metrics(_build_wandb_state(), config.get_metrics_path())


# ============================================================
# Public API — stats and state
# ============================================================

func get_stats() -> Dictionary:
	var stats := {
		"mode": Mode.keys()[current_mode],
		"generation": generation,
		"evaluated_count": evaluated_count,
		"population_size": population_size,
		"best_fitness": best_fitness,
		"all_time_best": all_time_best,
		"current_score": main_scene.score if main_scene else 0.0,
		"playback_generation": playback_mgr.playback_generation,
		"max_playback_generation": playback_mgr.max_playback_generation,
		"stagnation": generations_without_improvement,
		"stagnation_limit": stagnation_limit,
		"curriculum_stage": curriculum_stage,
		"curriculum_label": get_curriculum_label(),
		"use_neat": use_neat,
		"use_map_elites": use_map_elites,
		"map_elites_occupied": map_elites_archive.get_occupied_count() if map_elites_archive else 0,
		"map_elites_coverage": map_elites_archive.get_coverage() if map_elites_archive else 0.0,
	}
	if coevolution:
		stats["enemy_best_fitness"] = coevolution.enemy_evolution.get_best_fitness()
		stats["enemy_all_time_best"] = coevolution.enemy_evolution.get_all_time_best_fitness()
		stats["hof_size"] = coevolution.get_hof_size()
		stats["is_hof_generation"] = coevo_is_hof_generation
	return stats


func get_mode() -> Mode:
	return current_mode


func is_ai_active() -> bool:
	return current_mode != Mode.HUMAN


const _ConstantsScript = preload("res://constants.gd")
const SPEED_STEPS: Array[float] = _ConstantsScript.TIME_SCALE_STEPS

func adjust_speed(delta: float) -> void:
	var current_idx := SPEED_STEPS.find(time_scale)
	if current_idx == -1:
		current_idx = 2
	if delta > 0 and current_idx < SPEED_STEPS.size() - 1:
		current_idx += 1
	elif delta < 0 and current_idx > 0:
		current_idx -= 1
	time_scale = SPEED_STEPS[current_idx]
	Engine.time_scale = time_scale
	print("Training speed: %.2fx" % time_scale)


func get_max_history_value() -> float:
	return stats_tracker.get_max_history_value()


# Backward-compatible public aliases
func update_training_stats_display() -> void:
	if _active_mode and _active_mode is StandardTrainingMode:
		_active_mode._update_training_stats_display()
