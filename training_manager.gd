extends Node

## Training Manager - Runs 10 visible arenas in parallel for AI training.

signal training_status_changed(status: String)
signal stats_updated(stats: Dictionary)

enum Mode { HUMAN, TRAINING, PLAYBACK, GENERATION_PLAYBACK, ARCHIVE_PLAYBACK, COEVOLUTION, SANDBOX, COMPARISON, RTNEAT }

var current_mode: Mode = Mode.HUMAN

# Training components
var evolution = null
var current_batch_start: int = 0

# References
var main_scene: Node2D
var player: CharacterBody2D

# Configuration (centralized in TrainingConfig)
var config: RefCounted = preload("res://ai/training_config.gd").new()
var arena_pool: RefCounted = preload("res://ai/arena_pool.gd").new()
var population_size: int = 150
var max_generations: int = 100
var time_scale: float = 1.0
var parallel_count: int = 20  # Number of parallel arenas (5x4 grid)
var evals_per_individual: int = 2  # Run each network multiple times with different seeds

# Rolling evaluation - next individual to evaluate
var next_individual: int = 0
var evaluated_count: int = 0
var current_eval_seed: int = 0  # Which seed we're currently evaluating

# Stats tracking (delegated to StatsTracker)
var stats_tracker: RefCounted = preload("res://ai/stats_tracker.gd").new()

# Extracted modules
var migration_mgr: RefCounted = preload("res://ai/migration_manager.gd").new()
var metrics_writer: RefCounted = preload("res://ai/metrics_writer.gd").new()
var playback_mgr: RefCounted = preload("res://ai/playback_manager.gd").new()
var training_ui: RefCounted = preload("res://ai/training_ui.gd").new()

# Multi-objective tracking (NSGA-II)
var use_nsga2: bool = false

# NEAT topology evolution
var use_neat: bool = false

# Elman recurrent memory
var use_memory: bool = false

# MAP-Elites quality-diversity archive
var use_map_elites: bool = true
var map_elites_archive: MapElites = null

# Co-evolution (Track A)
var coevolution = null  # CoEvolution coordinator (dual-population)
var CoevolutionScript = preload("res://ai/coevolution.gd")
var EnemyAIControllerScript = preload("res://ai/enemy_ai_controller.gd")
var coevo_enemy_fitness: Dictionary = {}  # {enemy_index: [fitness_values_from_evals]}
var coevo_enemy_stats: Dictionary = {}    # {enemy_index: {damage, proximity, survival, dir_changes}}
var coevo_is_hof_generation: bool = false  # True when evaluating against Hall of Fame

# rtNEAT continuous evolution
var rtneat_mgr = null  # RtNeatManager instance

# Co-evolution paths (aliases from config)
var ENEMY_POPULATION_PATH: String:
	get: return config.ENEMY_POPULATION_PATH
var ENEMY_HOF_PATH: String:
	get: return config.ENEMY_HOF_PATH

# Pre-generated events for each seed (all individuals see same scenarios)
var generation_events_by_seed: Array = []  # [{obstacles, enemy_spawns, powerup_spawns}, ...]

# Path aliases (constants live in config)
var BEST_NETWORK_PATH: String:
	get: return config.BEST_NETWORK_PATH
var POPULATION_PATH: String:
	get: return config.POPULATION_PATH

# Island model migration path alias
var MIGRATION_POOL_DIR: String:
	get: return config.MIGRATION_POOL_DIR

# Stats
var generation: int = 0
var best_fitness: float = 0.0
var all_time_best: float = 0.0

# Early stopping (based on average fitness, not all-time best)
var stagnation_limit: int = 10
var generations_without_improvement: int = 0
var best_avg_fitness: float = 0.0  # Best average fitness seen so far

# Curriculum learning - progressive difficulty stages (delegated to CurriculumManager)
var CurriculumManagerScript = preload("res://ai/curriculum_manager.gd")
var curriculum: RefCounted = preload("res://ai/curriculum_manager.gd").new()

# Backward-compatible accessors for tests and external code
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

# Expose CURRICULUM_STAGES for test compatibility — reads from CurriculumManager
var CURRICULUM_STAGES: Array[Dictionary]:
	get: return CurriculumManagerScript.STAGES

# Generation rollback (disabled - trust elitism, accept normal variance)
var previous_avg_fitness: float = 0.0
var rerun_count: int = 0
const MAX_RERUNS: int = 0  # Disabled - rollback wastes compute and reduces diversity

# Backward-compatible accessors for playback state (delegate to playback_mgr)
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
var eval_instances: Array = []  # Array of {slot_index, scene, controller, index, time, done}
var ai_controller = null  # For playback mode

# Metric history and per-generation accumulators — delegated to stats_tracker
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

# Fullscreen arena view (delegated to arena_pool)
var fullscreen_arena_index: int:
	get: return arena_pool.fullscreen_index if arena_pool else -1
	set(v):
		if arena_pool:
			arena_pool.fullscreen_index = v

# Backward-compatible accessor for training_container
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
	# Wire training_ui signals
	training_ui.setup(stats_tracker, arena_pool)
	training_ui.heatmap_cell_clicked.connect(_on_heatmap_cell_clicked)
	training_ui.replay_best_requested.connect(_start_best_replay)
	training_ui.training_exited.connect(_on_training_exited)


var _space_was_pressed: bool = false


func _input(event: InputEvent) -> void:
	if current_mode != Mode.TRAINING and current_mode != Mode.COEVOLUTION:
		return

	# ESC exits fullscreen
	if event.is_action_pressed("ui_cancel") and arena_pool.fullscreen_index >= 0:
		arena_pool.exit_fullscreen()
		get_viewport().set_input_as_handled()
		return

	# Mouse click toggles fullscreen
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_index = arena_pool.get_slot_at_position(event.position)

		if arena_pool.fullscreen_index >= 0:
			# In fullscreen - only exit if clicking outside the arena
			if clicked_index != arena_pool.fullscreen_index:
				arena_pool.exit_fullscreen()
				get_viewport().set_input_as_handled()
		else:
			# In grid view - enter fullscreen if clicking on an arena
			if clicked_index >= 0:
				arena_pool.enter_fullscreen(clicked_index)
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Handle SPACE for pause toggle (runs even when paused due to PROCESS_MODE_ALWAYS)
	var space_pressed = Input.is_physical_key_pressed(KEY_SPACE)
	if space_pressed and not _space_was_pressed:
		if current_mode == Mode.TRAINING or current_mode == Mode.COEVOLUTION:
			toggle_pause()
	_space_was_pressed = space_pressed


func initialize(scene: Node2D) -> void:
	## Call this when the main scene is ready.
	main_scene = scene
	player = scene.get_node("Player")

	# Setup AI controller for playback
	ai_controller = AIControllerScript.new()
	ai_controller.set_player(player)

	# Setup playback manager with dependencies
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


func _load_sweep_config(fallback_pop_size: int = 150, fallback_max_gen: int = 100) -> void:
	## Load hyperparameters from sweep config via TrainingConfig.
	config.load_from_sweep(fallback_pop_size, fallback_max_gen)


func start_training(pop_size: int = 100, generations: int = 100) -> void:
	## Begin evolutionary training with parallel visible arenas.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	# Load sweep config (overrides defaults if present)
	_load_sweep_config(pop_size, generations)

	# Apply config values to local state
	population_size = config.population_size
	max_generations = config.max_generations
	evals_per_individual = config.evals_per_individual
	time_scale = config.time_scale
	parallel_count = config.parallel_count

	# Get input size from sensor
	var sensor_instance = AISensorScript.new()
	var input_size: int = sensor_instance.TOTAL_INPUTS

	# Initialize evolution system
	use_neat = config.use_neat
	use_memory = config.use_memory
	if use_neat:
		var neat_config := NeatConfig.new()
		neat_config.input_count = input_size
		neat_config.output_count = 6
		neat_config.population_size = population_size
		neat_config.crossover_rate = config.crossover_rate
		neat_config.weight_mutate_rate = config.mutation_rate
		neat_config.weight_perturb_strength = config.mutation_strength
		evolution = NeatEvolutionScript.new(neat_config)
	else:
		evolution = EvolutionScript.new(
			population_size,
			input_size,
			config.hidden_size,
			6,
			config.elite_count,
			config.mutation_rate,
			config.mutation_strength,
			config.crossover_rate
		)
		evolution.use_nsga2 = use_nsga2
		if use_memory:
			evolution.enable_population_memory()

	evolution.generation_complete.connect(_on_generation_complete)

	# Clean up any leftover pause state
	if training_ui.pause_overlay:
		training_ui.destroy_pause_overlay()
	training_ui.is_paused = false
	training_ui.training_complete = false

	current_mode = Mode.TRAINING
	current_batch_start = 0
	generation = 0
	generations_without_improvement = 0
	best_avg_fitness = 0.0
	previous_avg_fitness = 0.0
	rerun_count = 0
	current_eval_seed = 0
	curriculum.reset()
	curriculum.enabled = config.curriculum_enabled
	use_nsga2 = config.use_nsga2
	stats_tracker.reset()
	use_map_elites = config.use_map_elites
	if use_map_elites:
		map_elites_archive = MapElites.new(config.map_elites_grid_size)
	Engine.time_scale = time_scale

	# Hide the main game and show training arenas
	hide_main_game()
	create_training_container()

	# Generate events for all seeds upfront
	generate_all_seed_events()
	start_next_batch()

	training_status_changed.emit("Training started")
	var mem_label = "+memory" if use_memory else ""
	var evo_type = ("NEAT" if use_neat else ("NSGA-II" if use_nsga2 else "Standard")) + mem_label
	print("Training started: pop=%d, max_gen=%d, parallel=%d, seeds=%d, early_stop=%d, evo=%s" % [
		population_size, max_generations, parallel_count, evals_per_individual, stagnation_limit, evo_type
	])


func start_coevolution_training(pop_size: int = 100, generations: int = 100) -> void:
	## Begin co-evolutionary training: player and enemy populations evolve together.
	## Each arena gets a player AI + enemy AI controlling all enemies.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	_load_sweep_config(pop_size, generations)

	# Apply config values to local state
	population_size = config.population_size
	max_generations = config.max_generations
	evals_per_individual = config.evals_per_individual
	time_scale = config.time_scale
	parallel_count = config.parallel_count

	# Get input size from player sensor
	var sensor_instance = AISensorScript.new()
	var input_size: int = sensor_instance.TOTAL_INPUTS

	# Initialize co-evolution coordinator (wraps two Evolution instances)
	coevolution = CoevolutionScript.new(
		population_size, input_size, config.hidden_size, 6,
		population_size,  # Enemy pop same size as player pop
		config.elite_count, config.mutation_rate, config.mutation_strength, config.crossover_rate
	)

	# Clean up any leftover pause state
	if training_ui.pause_overlay:
		training_ui.destroy_pause_overlay()
	training_ui.is_paused = false
	training_ui.training_complete = false

	current_mode = Mode.COEVOLUTION
	current_batch_start = 0
	generation = 0
	generations_without_improvement = 0
	best_avg_fitness = 0.0
	previous_avg_fitness = 0.0
	current_eval_seed = 0
	curriculum.reset()
	curriculum.enabled = config.curriculum_enabled
	stats_tracker.reset()
	coevo_enemy_fitness.clear()
	coevo_enemy_stats.clear()
	coevo_is_hof_generation = false
	Engine.time_scale = time_scale

	# Try to load existing enemy HoF
	coevolution.load_hall_of_fame(ENEMY_HOF_PATH)

	hide_main_game()
	create_training_container()

	generate_all_seed_events()
	_coevo_start_next_batch()

	training_status_changed.emit("Co-evolution training started")
	print("Co-evolution started: pop=%d, max_gen=%d, parallel=%d" % [
		population_size, max_generations, parallel_count
	])


func stop_coevolution_training() -> void:
	## Stop co-evolution training and save progress.
	if current_mode != Mode.COEVOLUTION:
		return

	if training_ui.is_paused:
		training_ui.destroy_pause_overlay()
		training_ui.is_paused = false

	current_mode = Mode.HUMAN
	Engine.time_scale = 1.0

	eval_instances.clear()
	arena_pool.destroy()

	show_main_game()

	if coevolution:
		coevolution.save_populations(POPULATION_PATH, ENEMY_POPULATION_PATH)
		coevolution.save_hall_of_fame(ENEMY_HOF_PATH)
		coevolution.player_evolution.save_best(BEST_NETWORK_PATH)
		var stats = coevolution.get_stats()
		print("Saved co-evolution (player best: %.1f, enemy best: %.1f)" % [
			stats.player.best_fitness, stats.enemy.best_fitness
		])

	training_status_changed.emit("Co-evolution stopped")


func start_rtneat(rtneat_config: Dictionary = {}) -> void:
	## Begin rtNEAT mode: continuous real-time evolution in a single shared arena.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	current_mode = Mode.RTNEAT
	Engine.time_scale = 1.0

	var RtNeatManagerScript = load("res://ai/rtneat_manager.gd")
	rtneat_mgr = RtNeatManagerScript.new()
	rtneat_mgr.setup(main_scene, rtneat_config)

	# Hide the main player (agents replace it)
	player.visible = false
	player.set_physics_process(false)

	# Create overlay
	var RtNeatOverlayScript = load("res://ui/rtneat_overlay.gd")
	var overlay_node = RtNeatOverlayScript.new()
	overlay_node.name = "RtNeatOverlay"
	main_scene.get_node("CanvasLayer/UI").add_child(overlay_node)
	overlay_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	rtneat_mgr.overlay = overlay_node

	rtneat_mgr.start()

	training_status_changed.emit("rtNEAT started")
	print("rtNEAT started: %d agents" % rtneat_config.get("agent_count", 30))


func stop_rtneat() -> void:
	## Stop rtNEAT mode.
	if current_mode != Mode.RTNEAT:
		return

	if rtneat_mgr:
		# Save best before stopping
		rtneat_mgr.population.save_best(BEST_NETWORK_PATH)
		rtneat_mgr.stop()
		rtneat_mgr = null

	current_mode = Mode.HUMAN
	Engine.time_scale = 1.0

	# Restore main player
	player.visible = true
	player.set_physics_process(true)
	player.enable_ai_control(false)
	main_scene.training_mode = false

	training_status_changed.emit("rtNEAT stopped")


func generate_all_seed_events() -> void:
	## Pre-generate events for all evaluation seeds this generation.
	generation_events_by_seed.clear()
	var MainScene = load("res://main.gd")
	var curr_config = get_current_curriculum_config()
	for seed_idx in evals_per_individual:
		var seed_val = generation * 1000 + seed_idx  # Unique seed per generation+seed combo
		var events = MainScene.generate_random_events(seed_val, curr_config)
		generation_events_by_seed.append(events)


func stop_training() -> void:
	## Stop training and save progress.
	if current_mode != Mode.TRAINING:
		# If in coevolution mode, delegate to stop_coevolution_training
		if current_mode == Mode.COEVOLUTION:
			stop_coevolution_training()
		return

	# Clean up pause state first
	if training_ui.is_paused:
		training_ui.destroy_pause_overlay()
		training_ui.is_paused = false

	current_mode = Mode.HUMAN
	Engine.time_scale = 1.0

	# Cleanup training instances and visual layer
	eval_instances.clear()
	arena_pool.destroy()

	# Show main game again
	show_main_game()

	if evolution:
		evolution.save_best(BEST_NETWORK_PATH)
		evolution.save_population(POPULATION_PATH)
		print("Saved best network (fitness: %.1f)" % evolution.get_all_time_best_fitness())

	training_status_changed.emit("Training stopped")


func hide_main_game() -> void:
	## Hide the main game elements during training.
	main_scene.visible = false
	player.set_physics_process(false)
	# Hide the CanvasLayer UI (it renders independently of the scene)
	var canvas_layer = main_scene.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.visible = false


func show_main_game() -> void:
	## Show the main game elements after training.
	main_scene.visible = true
	player.set_physics_process(true)
	player.enable_ai_control(false)
	# Show the CanvasLayer UI
	var canvas_layer = main_scene.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.visible = true
	# Reset the game
	main_scene.get_tree().paused = false


func get_window_size() -> Vector2:
	## Get current window size reliably.
	return arena_pool.get_window_size() if arena_pool else get_viewport().get_visible_rect().size


func create_training_container() -> void:
	## Create a CanvasLayer with SubViewports for parallel training.
	arena_pool.setup(get_tree(), parallel_count)


func get_grid_dimensions() -> Dictionary:
	## Calculate optimal grid dimensions for current parallel count.
	return arena_pool.get_grid_dimensions()


func create_eval_instance(individual_index: int, _grid_x: int = 0, _grid_y: int = 0) -> Dictionary:
	## Create a SubViewport with a game instance for evaluation.
	var slot = arena_pool.create_slot()
	var viewport = slot.viewport
	var slot_index = slot.index

	# Instantiate game scene with preset events for current seed
	var scene: Node2D = MainScenePacked.instantiate()
	scene.set_training_mode(true, get_current_curriculum_config())
	if generation_events_by_seed.size() > current_eval_seed:
		var events = generation_events_by_seed[current_eval_seed]
		# Deep copy spawn arrays since they get modified during gameplay
		var enemy_copy = events.enemy_spawns.duplicate(true)
		var powerup_copy = events.powerup_spawns.duplicate(true)
		scene.set_preset_events(events.obstacles, enemy_copy, powerup_copy)
	viewport.add_child(scene)

	# Get player and configure for AI
	var scene_player: CharacterBody2D = scene.get_node("Player")
	scene_player.enable_ai_control(true)

	# Create AI controller
	var controller = AIControllerScript.new()
	controller.set_player(scene_player)
	if use_neat:
		controller.set_network(evolution.get_network(individual_index))
	else:
		controller.set_network(evolution.get_individual(individual_index))
		controller.network.reset_memory()

	# Hide UI elements we don't need
	var ui = scene.get_node("CanvasLayer/UI")
	for child in ui.get_children():
		if child.name not in ["ScoreLabel", "LivesLabel"]:
			child.visible = false

	# Add index label
	var index_label = Label.new()
	index_label.text = "#%d" % individual_index
	index_label.position = Vector2(5, 80)
	index_label.add_theme_font_size_override("font_size", 14)
	index_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	ui.add_child(index_label)

	return {
		"slot_index": slot_index,
		"viewport": viewport,
		"scene": scene,
		"player": scene_player,
		"controller": controller,
		"index": individual_index,
		"time": 0.0,
		"done": false
	}


func start_next_batch() -> void:
	## Start evaluating individuals for current seed.
	cleanup_training_instances()

	# Reset rolling counters for this seed pass
	next_individual = mini(parallel_count, population_size)
	evaluated_count = 0

	var seed_label = "seed %d/%d" % [current_eval_seed + 1, evals_per_individual]
	print("Gen %d (%s): Evaluating %d individuals..." % [generation, seed_label, population_size])

	for i in range(mini(parallel_count, population_size)):
		var instance = create_eval_instance(i)
		eval_instances.append(instance)


func replace_eval_instance(slot_index: int, individual_index: int) -> void:
	## Replace a completed evaluation slot with a new individual.
	# Arena pool handles viewport replacement; we rebuild game/AI wiring
	var slot = arena_pool.replace_slot(slot_index)
	var viewport = slot.viewport

	# Instantiate game scene with preset events for current seed
	var scene: Node2D = MainScenePacked.instantiate()
	scene.set_training_mode(true, get_current_curriculum_config())
	if generation_events_by_seed.size() > current_eval_seed:
		var events = generation_events_by_seed[current_eval_seed]
		var enemy_copy = events.enemy_spawns.duplicate(true)
		var powerup_copy = events.powerup_spawns.duplicate(true)
		scene.set_preset_events(events.obstacles, enemy_copy, powerup_copy)
	viewport.add_child(scene)

	var scene_player: CharacterBody2D = scene.get_node("Player")
	scene_player.enable_ai_control(true)

	var controller = AIControllerScript.new()
	controller.set_player(scene_player)
	if use_neat:
		controller.set_network(evolution.get_network(individual_index))
	else:
		controller.set_network(evolution.get_individual(individual_index))
		controller.network.reset_memory()

	var ui = scene.get_node("CanvasLayer/UI")
	for child in ui.get_children():
		if child.name not in ["ScoreLabel", "LivesLabel"]:
			child.visible = false

	var index_label = Label.new()
	index_label.text = "#%d" % individual_index
	index_label.position = Vector2(5, 80)
	index_label.add_theme_font_size_override("font_size", 14)
	index_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	ui.add_child(index_label)

	eval_instances[slot_index] = {
		"slot_index": slot_index,
		"viewport": viewport,
		"scene": scene,
		"player": scene_player,
		"controller": controller,
		"index": individual_index,
		"time": 0.0,
		"done": false
	}


func cleanup_training_instances() -> void:
	## Clean up completed evaluation instances.
	arena_pool.cleanup_all()
	eval_instances.clear()


# ============================================================
# Co-evolution batch management
# ============================================================

func _coevo_start_next_batch() -> void:
	## Start evaluating player-enemy pairs for co-evolution.
	## Each arena gets one player AI and one enemy AI controlling all enemies.
	## Random sampling: each player is paired with a random enemy from opposing pop.
	cleanup_training_instances()

	next_individual = mini(parallel_count, population_size)
	evaluated_count = 0
	coevo_enemy_fitness.clear()
	coevo_enemy_stats.clear()

	var seed_label = "seed %d/%d" % [current_eval_seed + 1, evals_per_individual]
	print("Gen %d (%s): Co-evolving %d player-enemy pairs..." % [generation, seed_label, population_size])

	for i in range(mini(parallel_count, population_size)):
		var enemy_idx: int = _pick_enemy_index(i)
		var instance = _coevo_create_eval_instance(i, enemy_idx)
		eval_instances.append(instance)


func _pick_enemy_index(player_index: int) -> int:
	## Pick an enemy index for this player evaluation.
	## During HoF generations, we don't use this (HoF networks are used directly).
	## Otherwise: random sampling from enemy population.
	return randi() % population_size


func _coevo_create_eval_instance(player_index: int, enemy_index: int, _grid_x: int = 0, _grid_y: int = 0) -> Dictionary:
	## Create a SubViewport with a game instance for co-evolution evaluation.
	## Similar to create_eval_instance() but also wires enemy AI.
	var slot = arena_pool.create_slot()
	var viewport = slot.viewport
	var slot_index = slot.index

	var scene: Node2D = MainScenePacked.instantiate()
	scene.set_training_mode(true, get_current_curriculum_config())
	if generation_events_by_seed.size() > current_eval_seed:
		var events = generation_events_by_seed[current_eval_seed]
		var enemy_copy = events.enemy_spawns.duplicate(true)
		var powerup_copy = events.powerup_spawns.duplicate(true)
		scene.set_preset_events(events.obstacles, enemy_copy, powerup_copy)
	viewport.add_child(scene)

	# Player AI
	var scene_player: CharacterBody2D = scene.get_node("Player")
	scene_player.enable_ai_control(true)
	var controller = AIControllerScript.new()
	controller.set_player(scene_player)
	controller.set_network(coevolution.get_player_network(player_index))
	controller.network.reset_memory()

	# Enemy AI: get the network to use (current population or HoF)
	var enemy_network
	if coevo_is_hof_generation:
		var hof_nets = coevolution.get_hof_networks()
		enemy_network = hof_nets[enemy_index % hof_nets.size()] if not hof_nets.is_empty() else coevolution.get_enemy_network(enemy_index)
	else:
		enemy_network = coevolution.get_enemy_network(enemy_index)

	# Set enemy_ai_network on the scene so all spawned enemies auto-wire
	scene.enemy_ai_network = enemy_network

	var ui = scene.get_node("CanvasLayer/UI")
	for child in ui.get_children():
		if child.name not in ["ScoreLabel", "LivesLabel"]:
			child.visible = false

	var index_label = Label.new()
	index_label.text = "P#%d vs E#%d" % [player_index, enemy_index]
	index_label.position = Vector2(5, 80)
	index_label.add_theme_font_size_override("font_size", 14)
	index_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	ui.add_child(index_label)

	return {
		"slot_index": slot_index,
		"viewport": viewport,
		"scene": scene,
		"player": scene_player,
		"controller": controller,
		"index": player_index,
		"enemy_index": enemy_index,
		"time": 0.0,
		"done": false,
		"last_player_dir": Vector2.ZERO,
		"direction_changes": 0,
		"proximity_sum": 0.0,
		"proximity_samples": 0,
	}


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var current = node.get_parent()
	while current:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _coevo_replace_eval_instance(slot_index: int, player_index: int) -> void:
	## Replace a completed co-evolution slot with a new player-enemy pair.
	# Arena pool handles viewport replacement
	var slot = arena_pool.replace_slot(slot_index)
	var viewport = slot.viewport

	var enemy_idx: int = _pick_enemy_index(player_index)

	var scene: Node2D = MainScenePacked.instantiate()
	scene.set_training_mode(true, get_current_curriculum_config())
	if generation_events_by_seed.size() > current_eval_seed:
		var events = generation_events_by_seed[current_eval_seed]
		var enemy_copy = events.enemy_spawns.duplicate(true)
		var powerup_copy = events.powerup_spawns.duplicate(true)
		scene.set_preset_events(events.obstacles, enemy_copy, powerup_copy)
	viewport.add_child(scene)

	var scene_player: CharacterBody2D = scene.get_node("Player")
	scene_player.enable_ai_control(true)
	var controller = AIControllerScript.new()
	controller.set_player(scene_player)
	controller.set_network(coevolution.get_player_network(player_index))
	controller.network.reset_memory()

	var enemy_network
	if coevo_is_hof_generation:
		var hof_nets = coevolution.get_hof_networks()
		enemy_network = hof_nets[enemy_idx % hof_nets.size()] if not hof_nets.is_empty() else coevolution.get_enemy_network(enemy_idx)
	else:
		enemy_network = coevolution.get_enemy_network(enemy_idx)
	scene.enemy_ai_network = enemy_network

	var ui = scene.get_node("CanvasLayer/UI")
	for child in ui.get_children():
		if child.name not in ["ScoreLabel", "LivesLabel"]:
			child.visible = false

	var index_label = Label.new()
	index_label.text = "P#%d vs E#%d" % [player_index, enemy_idx]
	index_label.position = Vector2(5, 80)
	index_label.add_theme_font_size_override("font_size", 14)
	index_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	ui.add_child(index_label)

	eval_instances[slot_index] = {
		"slot_index": slot_index,
		"viewport": viewport,
		"scene": scene,
		"player": scene_player,
		"controller": controller,
		"index": player_index,
		"enemy_index": enemy_idx,
		"time": 0.0,
		"done": false,
		"last_player_dir": Vector2.ZERO,
		"direction_changes": 0,
		"proximity_sum": 0.0,
		"proximity_samples": 0,
	}


func _physics_process(delta: float) -> void:
	if current_mode == Mode.HUMAN:
		return

	# Don't process training when paused (SubViewport scenes are frozen)
	if training_ui.is_paused:
		return

	if current_mode == Mode.TRAINING:
		_process_parallel_training(delta)
	elif current_mode == Mode.COEVOLUTION:
		_process_coevolution_training(delta)
	elif current_mode == Mode.PLAYBACK:
		playback_mgr.process_playback()
	elif current_mode == Mode.GENERATION_PLAYBACK:
		playback_mgr.process_generation_playback()
	elif current_mode == Mode.ARCHIVE_PLAYBACK:
		playback_mgr.process_archive_playback()
	elif current_mode == Mode.SANDBOX:
		playback_mgr.process_sandbox()
	elif current_mode == Mode.COMPARISON:
		playback_mgr.process_comparison(delta)
	elif current_mode == Mode.RTNEAT:
		if rtneat_mgr:
			rtneat_mgr.process(delta)


func _process_parallel_training(delta: float) -> void:
	var active_count := 0

	for i in eval_instances.size():
		var eval = eval_instances[i]
		if eval.done:
			continue

		active_count += 1
		eval.time += delta

		# Drive AI controller
		var action: Dictionary = eval.controller.get_action()
		eval.player.set_ai_action(action.move_direction, action.shoot_direction)

		# Check if game over OR timeout (60 second max - faster iteration)
		var timed_out = eval.time >= 60.0
		if eval.scene.game_over or timed_out:
			# Record fitness and score breakdown via stats tracker
			var fitness: float = eval.scene.score
			var kill_score: float = eval.scene.score_from_kills
			var powerup_score: float = eval.scene.score_from_powerups
			var survival_score: float = eval.scene.score - kill_score - powerup_score
			stats_tracker.record_eval_result(eval.index, fitness, kill_score, powerup_score, survival_score)

			# Collect behavior stats for MAP-Elites
			if use_map_elites:
				stats_tracker.record_behavior(eval.index, eval.scene.kills, eval.scene.powerups_collected, eval.scene.survival_time)

			eval.done = true
			evaluated_count += 1
			active_count -= 1

			# Replace with next individual if available
			if next_individual < population_size:
				replace_eval_instance(i, next_individual)
				next_individual += 1

	# Check if all individuals complete for current seed
	if evaluated_count >= population_size:
		current_eval_seed += 1

		# Check if all seeds complete
		if current_eval_seed >= evals_per_individual:
			# Average fitness across seeds and set final fitness/objectives
			for idx in population_size:
				if use_nsga2:
					evolution.set_objectives(idx, stats_tracker.get_avg_objectives(idx))
				else:
					evolution.set_fitness(idx, stats_tracker.get_avg_fitness(idx))

			# Add to MAP-Elites archive before evolve() mutates the population
			if use_map_elites and map_elites_archive:
				metrics_writer.update_map_elites_archive(map_elites_archive, evolution, stats_tracker, population_size, use_neat)

			# Debug: print fitness distribution before evolving
			var stats = evolution.get_stats()
			print("Gen %d complete: min=%.0f avg=%.0f max=%.0f best_ever=%.0f" % [
				generation, stats.current_min, stats.current_avg, stats.current_max, stats.all_time_best
			])

			evolution.evolve()
			generation = evolution.get_generation()

			# Reset for next generation
			current_eval_seed = 0
			stats_tracker.clear_accumulators()
			evaluated_count = 0
			next_individual = 0

			if evolution.get_generation() >= max_generations:
				_show_training_complete("Reached max generations (%d)" % max_generations)
				_write_metrics_for_wandb()
				return

			# Generate new events for next generation
			generate_all_seed_events()
			start_next_batch()
		else:
			# Start next seed pass
			evaluated_count = 0
			next_individual = 0
			start_next_batch()

	# Update stats display
	_update_training_stats_display()

	stats_updated.emit(get_stats())


func _process_coevolution_training(delta: float) -> void:
	## Process co-evolution: each arena has player AI + enemy AI.
	## Player fitness = game score (unchanged).
	## Enemy fitness = adversarial (damage dealt, proximity, player survival penalty).
	var active_count := 0

	for i in eval_instances.size():
		var eval = eval_instances[i]
		if eval.done:
			continue

		active_count += 1
		eval.time += delta

		# Drive player AI controller
		var action: Dictionary = eval.controller.get_action()
		eval.player.set_ai_action(action.move_direction, action.shoot_direction)

		# Track proximity pressure (average distance of nearest enemy to player)
		var nearest_dist := INF
		for enemy in eval.scene.get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(enemy) and _is_descendant_of(enemy, eval.scene):
				var d = enemy.global_position.distance_to(eval.player.global_position)
				nearest_dist = minf(nearest_dist, d)
		if nearest_dist < INF:
			var closeness := 1.0 - clampf(nearest_dist / 3840.0, 0.0, 1.0)
			eval.proximity_sum += closeness
			eval.proximity_samples += 1

		# Track direction changes (player movement direction changed significantly)
		var current_dir = eval.player.velocity.normalized()
		if current_dir.length() > 0.1 and eval.last_player_dir.length() > 0.1:
			var dot = current_dir.dot(eval.last_player_dir)
			if dot < 0.5:  # >60 degree change counts
				eval.direction_changes += 1
		eval.last_player_dir = current_dir

		# Check game over or timeout
		var timed_out = eval.time >= 60.0
		if eval.scene.game_over or timed_out:
			# Player fitness (same as standard training)
			var player_fitness: float = eval.scene.score
			var kill_score: float = eval.scene.score_from_kills
			var powerup_score: float = eval.scene.score_from_powerups
			var survival_score: float = eval.scene.score - kill_score - powerup_score
			stats_tracker.record_eval_result(eval.index, player_fitness, kill_score, powerup_score, survival_score)

			# Enemy adversarial fitness
			var damage_dealt: float = 3.0 - eval.scene.lives  # Lives lost (starts at 3)
			var avg_proximity: float = eval.proximity_sum / maxf(eval.proximity_samples, 1)
			var survival_time: float = eval.scene.survival_time
			var dir_changes: float = eval.direction_changes

			var enemy_fitness := CoevolutionScript.compute_enemy_fitness(
				damage_dealt, avg_proximity, survival_time, dir_changes
			)

			# Accumulate enemy fitness (each enemy may face multiple players)
			if not coevo_is_hof_generation:
				var eidx: int = eval.enemy_index
				if not coevo_enemy_fitness.has(eidx):
					coevo_enemy_fitness[eidx] = []
				coevo_enemy_fitness[eidx].append(enemy_fitness)

			eval.done = true
			evaluated_count += 1
			active_count -= 1

			if next_individual < population_size:
				_coevo_replace_eval_instance(i, next_individual)
				next_individual += 1

	# Check if all individuals evaluated for current seed
	if evaluated_count >= population_size:
		current_eval_seed += 1

		if current_eval_seed >= evals_per_individual:
			# Set player fitness
			for idx in population_size:
				coevolution.set_player_fitness(idx, stats_tracker.get_avg_fitness(idx))

			# Set enemy fitness (average across all pairings)
			if not coevo_is_hof_generation:
				for eidx in population_size:
					var scores: Array = coevo_enemy_fitness.get(eidx, [0.0])
					var avg_ef: float = 0.0
					for s in scores:
						avg_ef += s
					avg_ef /= scores.size()
					coevolution.set_enemy_fitness(eidx, avg_ef)

			# Print stats before evolving
			var p_stats = coevolution.player_evolution.get_stats()
			var e_stats = coevolution.enemy_evolution.get_stats()
			var hof_tag = " [HoF eval]" if coevo_is_hof_generation else ""
			print("Gen %d complete%s: P(min=%.0f avg=%.0f max=%.0f) E(min=%.0f avg=%.0f max=%.0f)" % [
				generation, hof_tag,
				p_stats.current_min, p_stats.current_avg, p_stats.current_max,
				e_stats.current_min, e_stats.current_avg, e_stats.current_max
			])

			# Evolve both populations
			coevolution.evolve_both()
			generation = coevolution.get_generation()
			best_fitness = coevolution.player_evolution.get_best_fitness()
			all_time_best = coevolution.player_evolution.get_all_time_best_fitness()

			# Track stagnation (player avg fitness)
			var avg = p_stats.current_avg
			if avg > best_avg_fitness:
				generations_without_improvement = 0
				best_avg_fitness = avg
			else:
				generations_without_improvement += 1

			# Record for graphing
			stats_tracker.record_generation(p_stats.current_max, avg, p_stats.current_min, population_size, evals_per_individual)

			# Check curriculum advancement
			check_curriculum_advancement()

			# Auto-save
			coevolution.player_evolution.save_best(BEST_NETWORK_PATH)
			coevolution.save_populations(POPULATION_PATH, ENEMY_POPULATION_PATH)
			coevolution.save_hall_of_fame(ENEMY_HOF_PATH)
			_write_metrics_for_wandb()

			# Early stopping
			if generations_without_improvement >= stagnation_limit:
				print("Early stopping: No improvement for %d generations" % stagnation_limit)
				_show_training_complete("Early stopping: No improvement for %d generations" % stagnation_limit)
				_write_metrics_for_wandb()
				return

			if generation >= max_generations:
				_show_training_complete("Reached max generations (%d)" % max_generations)
				_write_metrics_for_wandb()
				return

			# Reset for next generation
			current_eval_seed = 0
			stats_tracker.clear_accumulators()
			coevo_is_hof_generation = coevolution.should_eval_against_hof()
			generate_all_seed_events()
			_coevo_start_next_batch()
		else:
			# Next seed pass
			evaluated_count = 0
			next_individual = 0
			_coevo_start_next_batch()

	# Update stats display
	_update_coevo_stats_display()
	stats_updated.emit(get_stats())


# ============================================================
# Stats display (thin delegation to training_ui)
# ============================================================

func _update_coevo_stats_display() -> void:
	var best_current = 0.0
	for eval in eval_instances:
		if not eval.done and eval.scene.score > best_current:
			best_current = eval.scene.score

	var enemy_best_str = "?"
	if coevolution:
		enemy_best_str = "%.0f" % coevolution.enemy_evolution.get_best_fitness()

	training_ui.update_coevo_stats({
		"generation": generation,
		"current_eval_seed": current_eval_seed,
		"evals_per_individual": evals_per_individual,
		"evaluated_count": evaluated_count,
		"population_size": population_size,
		"best_current": best_current,
		"all_time_best": all_time_best,
		"generations_without_improvement": generations_without_improvement,
		"stagnation_limit": stagnation_limit,
		"coevo_is_hof_generation": coevo_is_hof_generation,
		"curriculum_enabled": curriculum_enabled,
		"curriculum_label": get_curriculum_label(),
		"enemy_best_str": enemy_best_str,
		"hof_size": coevolution.get_hof_size() if coevolution else 0,
		"time_scale": time_scale,
		"fullscreen": arena_pool.fullscreen_index >= 0,
	})


func _update_training_stats_display() -> void:
	var best_current = 0.0
	for eval in eval_instances:
		if not eval.done and eval.scene.score > best_current:
			best_current = eval.scene.score

	training_ui.update_training_stats({
		"generation": generation,
		"current_eval_seed": current_eval_seed,
		"evals_per_individual": evals_per_individual,
		"evaluated_count": evaluated_count,
		"population_size": population_size,
		"best_current": best_current,
		"all_time_best": all_time_best,
		"generations_without_improvement": generations_without_improvement,
		"stagnation_limit": stagnation_limit,
		"curriculum_enabled": curriculum_enabled,
		"curriculum_label": get_curriculum_label(),
		"use_nsga2": use_nsga2,
		"pareto_front_size": evolution.pareto_front.size() if evolution and use_nsga2 else 0,
		"use_neat": use_neat,
		"neat_species_count": evolution.get_stats().species_count if evolution and use_neat else 0,
		"neat_compat_threshold": evolution.get_stats().compatibility_threshold if evolution and use_neat else 0.0,
		"use_map_elites": use_map_elites,
		"me_occupied": map_elites_archive.get_occupied_count() if map_elites_archive else 0,
		"me_total": map_elites_archive.grid_size * map_elites_archive.grid_size if map_elites_archive else 0,
		"time_scale": time_scale,
		"fullscreen": arena_pool.fullscreen_index >= 0,
	})


# Backward-compatible public aliases
func update_training_stats_display() -> void:
	_update_training_stats_display()


# ============================================================
# Generation complete callback
# ============================================================

func _on_generation_complete(gen: int, best: float, avg: float, min_fit: float) -> void:
	generation = gen
	best_fitness = best
	all_time_best = evolution.get_all_time_best_fitness()

	# Check if this generation is worse than previous (and we haven't exceeded rerun limit)
	if previous_avg_fitness > 0 and avg < previous_avg_fitness and rerun_count < MAX_RERUNS:
		rerun_count += 1
		print("Gen %3d | Avg: %6.1f < Previous: %6.1f | RE-RUNNING (attempt %d/%d)" % [
			gen, avg, previous_avg_fitness, rerun_count, MAX_RERUNS
		])
		# Restore backup and re-run this generation
		evolution.restore_backup()
		generation = evolution.get_generation()
		return  # Don't record this failed attempt

	# Generation accepted - reset rerun counter
	rerun_count = 0
	previous_avg_fitness = avg

	# Record metrics for graphing (delegates to stats_tracker)
	var score_breakdown = stats_tracker.record_generation(best, avg, min_fit, population_size, evals_per_individual)
	var avg_kill_score: float = score_breakdown.avg_kill_score
	var avg_powerup_score: float = score_breakdown.avg_powerup_score

	# Track stagnation based on average fitness (more robust than all-time best)
	if avg > best_avg_fitness:
		generations_without_improvement = 0
		best_avg_fitness = avg
	else:
		generations_without_improvement += 1

	var curriculum_info = ""
	if curriculum_enabled:
		curriculum_info = " | %s" % get_curriculum_label()
	var neat_info = ""
	if use_neat and evolution:
		neat_info = " | Sp: %d" % evolution.get_species_count()
	var me_info = ""
	if use_map_elites and map_elites_archive:
		me_info = " | ME: %d (%.0f%%)" % [map_elites_archive.get_occupied_count(), map_elites_archive.get_coverage() * 100]
	print("Gen %3d | Best: %6.1f | Avg: %6.1f | Kill$: %.0f | Pwr$: %.0f | Stagnant: %d/%d%s%s%s" % [
		gen, best, avg, avg_kill_score, avg_powerup_score, generations_without_improvement, stagnation_limit, curriculum_info, neat_info, me_info
	])

	# Check curriculum advancement (before saving so metrics include new stage)
	check_curriculum_advancement()

	# Auto-save every generation
	evolution.save_best(BEST_NETWORK_PATH)
	evolution.save_population(POPULATION_PATH)

	# Island model migration (export best, import foreign genomes)
	if use_neat:
		migration_mgr.export_best(evolution, config.worker_id, generation, MIGRATION_POOL_DIR)
		migration_mgr.try_import(evolution, config.worker_id, generation, generations_without_improvement, MIGRATION_POOL_DIR)

	# Write metrics for W&B bridge
	_write_metrics_for_wandb()

	# Early stopping if no improvement for stagnation_limit generations
	if generations_without_improvement >= stagnation_limit:
		print("Early stopping: No improvement for %d generations" % stagnation_limit)
		_show_training_complete("Early stopping: No improvement for %d generations" % stagnation_limit)
		_write_metrics_for_wandb()


# ============================================================
# Metrics (thin delegation to metrics_writer)
# ============================================================

func _build_wandb_state() -> Dictionary:
	## Build the state dictionary for W&B metrics serialization.
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

	# Add co-evolution metrics if active
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
# Curriculum learning
# ============================================================

func get_current_curriculum_config() -> Dictionary:
	## Return the curriculum config for the current stage.
	return curriculum.get_current_config()


func check_curriculum_advancement() -> bool:
	## Check if agents should advance to the next curriculum stage.
	var advanced = curriculum.check_advancement(history_avg_fitness)
	if advanced:
		# Reset stagnation counter on advancement (new stage = fresh start)
		generations_without_improvement = 0
		best_avg_fitness = 0.0
	return advanced


func get_curriculum_label() -> String:
	## Get a display label for the current curriculum stage.
	return curriculum.get_label()


# ============================================================
# Playback modes (thin delegation to playback_mgr)
# ============================================================

func start_playback() -> void:
	current_mode = Mode.PLAYBACK
	playback_mgr.start_playback()


func stop_playback() -> void:
	current_mode = Mode.HUMAN
	playback_mgr.stop_playback()


func start_generation_playback() -> void:
	current_mode = Mode.GENERATION_PLAYBACK
	playback_mgr.start_generation_playback()


func advance_generation_playback() -> void:
	playback_mgr.advance_generation_playback()


func start_archive_playback(cell: Vector2i) -> void:
	# If we were in training mode, stop it first
	if current_mode == Mode.TRAINING:
		stop_training()
	current_mode = Mode.ARCHIVE_PLAYBACK
	playback_mgr.map_elites_archive = map_elites_archive
	playback_mgr.start_archive_playback(cell)


func stop_archive_playback() -> void:
	current_mode = Mode.HUMAN
	playback_mgr.stop_archive_playback()


func start_sandbox(sandbox_cfg: Dictionary) -> void:
	current_mode = Mode.SANDBOX
	playback_mgr.start_sandbox(sandbox_cfg)


func stop_sandbox() -> void:
	if current_mode != Mode.SANDBOX:
		return
	current_mode = Mode.HUMAN
	playback_mgr.stop_sandbox()


func start_comparison(strategies: Array) -> void:
	current_mode = Mode.COMPARISON
	playback_mgr.start_comparison(strategies)


func stop_comparison() -> void:
	if current_mode != Mode.COMPARISON:
		return
	current_mode = Mode.HUMAN
	playback_mgr.stop_comparison()


func reset_game() -> void:
	playback_mgr.reset_game()


# ============================================================
# Pause (thin delegation to training_ui)
# ============================================================

func toggle_pause() -> void:
	if current_mode != Mode.TRAINING and current_mode != Mode.COEVOLUTION:
		return
	training_ui.toggle_pause(_build_pause_state(), eval_instances)


func _show_training_complete(reason: String) -> void:
	## Save final results, then delegate to training_ui for display.
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
	## Build state dict for pause overlay display.
	var state := {
		"generation": generation,
		"best_fitness": best_fitness,
		"all_time_best": all_time_best,
		"avg_fitness": history_avg_fitness[-1] if history_avg_fitness.size() > 0 else 0.0,
		"generations_without_improvement": generations_without_improvement,
		"stagnation_limit": stagnation_limit,
	}
	# MAP-Elites heatmap data
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
# Signal handlers for extracted modules
# ============================================================

func _on_heatmap_cell_clicked(cell: Vector2i) -> void:
	## Handle click on a MAP-Elites heatmap cell during pause.
	if not map_elites_archive:
		return

	var elite = map_elites_archive.get_elite(cell)
	if elite == null:
		print("No elite at cell (%d, %d)" % [cell.x, cell.y])
		return

	# Exit training pause and start archive playback
	if training_ui.is_paused:
		training_ui.destroy_pause_overlay()
		training_ui.is_paused = false

	# Stop training mode processing
	current_mode = Mode.HUMAN
	Engine.time_scale = 1.0

	# Cleanup training instances and visual layer
	eval_instances.clear()
	arena_pool.destroy()

	# Show main game and start archive playback
	show_main_game()
	start_archive_playback(cell)


func _on_training_exited() -> void:
	## Handle SPACE press on training complete screen.
	if current_mode == Mode.COEVOLUTION:
		stop_coevolution_training()
	else:
		stop_training()


func _start_best_replay() -> void:
	## Tear down training grid and start fullscreen playback of best network.
	# Clean up pause state if any
	if training_ui.is_paused:
		training_ui.destroy_pause_overlay()
		training_ui.is_paused = false

	# Tear down training grid
	eval_instances.clear()
	arena_pool.destroy()

	# Show main game fullscreen
	show_main_game()
	Engine.time_scale = 1.0

	# Build network from best genome/weights
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
		training_status_changed.emit("Training complete (no network to replay)")
		return

	# Start playback
	current_mode = Mode.PLAYBACK
	ai_controller.set_network(network)
	player.enable_ai_control(true)
	playback_mgr.reset_game()

	# Show network topology visualizer
	if main_scene.network_visualizer:
		if genome and network is NeatNetwork:
			main_scene.network_visualizer.set_neat_data(genome, network)
		else:
			main_scene.network_visualizer.set_fixed_network(network)
		main_scene.network_visualizer.visible = true

	training_status_changed.emit("Replaying best network (fitness: %.1f)" % all_time_best)
	print("Auto-replaying best network (fitness: %.1f)" % all_time_best)


# ============================================================
# Public API
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


const SPEED_STEPS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0]

func adjust_speed(delta: float) -> void:
	## Adjust training speed up or down through discrete steps.
	var current_idx := SPEED_STEPS.find(time_scale)
	if current_idx == -1:
		current_idx = 2  # Default to 1.0x

	if delta > 0 and current_idx < SPEED_STEPS.size() - 1:
		current_idx += 1
	elif delta < 0 and current_idx > 0:
		current_idx -= 1

	time_scale = SPEED_STEPS[current_idx]
	Engine.time_scale = time_scale
	print("Training speed: %.2fx" % time_scale)


func get_max_history_value() -> float:
	return stats_tracker.get_max_history_value()
