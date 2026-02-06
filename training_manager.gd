extends Node

## Training Manager - Runs 10 visible arenas in parallel for AI training.

signal training_status_changed(status: String)
signal stats_updated(stats: Dictionary)

enum Mode { HUMAN, TRAINING, PLAYBACK, GENERATION_PLAYBACK }

var current_mode: Mode = Mode.HUMAN

# Training components
var evolution = null
var current_batch_start: int = 0

# References
var main_scene: Node2D
var player: CharacterBody2D

# Configuration
var population_size: int = 100
var max_generations: int = 100
var time_scale: float = 1.0
var parallel_count: int = 20  # Number of parallel arenas (5x4 grid)
var evals_per_individual: int = 2  # Run each network multiple times with different seeds

# Rolling evaluation - next individual to evaluate
var next_individual: int = 0
var evaluated_count: int = 0
var current_eval_seed: int = 0  # Which seed we're currently evaluating

# Fitness tracking - accumulate across multiple seeds
var fitness_accumulator: Dictionary = {}  # {individual_index: [seed1_fitness, seed2_fitness, ...]}

# Pre-generated events for each seed (all individuals see same scenarios)
var generation_events_by_seed: Array = []  # [{obstacles, enemy_spawns, powerup_spawns}, ...]

# Paths
const BEST_NETWORK_PATH := "user://best_network.nn"
const POPULATION_PATH := "user://population.evo"
const SWEEP_CONFIG_PATH := "user://sweep_config.json"

# Sweep config (loaded from file for hyperparameter search)
var _sweep_config: Dictionary = {}
var _worker_id: String = ""  # Worker ID for parallel sweep runs

# Stats
var generation: int = 0
var best_fitness: float = 0.0
var all_time_best: float = 0.0

# Early stopping (based on average fitness, not all-time best)
var stagnation_limit: int = 10
var generations_without_improvement: int = 0
var best_avg_fitness: float = 0.0  # Best average fitness seen so far

# Generation rollback (disabled - trust elitism, accept normal variance)
var previous_avg_fitness: float = 0.0
var rerun_count: int = 0
const MAX_RERUNS: int = 0  # Disabled - rollback wastes compute and reduces diversity

# Generation playback state
var playback_generation: int = 1
var max_playback_generation: int = 1
var generation_networks: Array = []

# Parallel training instances
var eval_instances: Array = []  # Array of {viewport, scene, controller, index, time, done}
var training_container: Control  # Container for all training viewports
var ai_controller = null  # For playback mode

# Metric history for graphing
var history_best_fitness: Array[float] = []
var history_avg_fitness: Array[float] = []
var history_min_fitness: Array[float] = []
var history_avg_kill_score: Array[float] = []
var history_avg_powerup_score: Array[float] = []
var history_avg_survival_score: Array[float] = []

# Per-generation accumulators
var generation_total_kill_score: float = 0.0
var generation_total_powerup_score: float = 0.0
var generation_total_survival_score: float = 0.0

# Pause state
var is_paused: bool = false
var pause_overlay: Control = null
var saved_time_scale: float = 1.0
var training_complete: bool = false  # Shows results screen at end

# Fullscreen arena view
var fullscreen_arena_index: int = -1  # -1 = grid view, 0+ = fullscreen arena slot

# Preloaded scripts
var NeuralNetworkScript = preload("res://ai/neural_network.gd")
var AISensorScript = preload("res://ai/sensor.gd")
var AIControllerScript = preload("res://ai/ai_controller.gd")
var EvolutionScript = preload("res://ai/evolution.gd")
var MainScenePacked = preload("res://main.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


var _space_was_pressed: bool = false


func _input(event: InputEvent) -> void:
	if current_mode != Mode.TRAINING:
		return

	# ESC exits fullscreen
	if event.is_action_pressed("ui_cancel") and fullscreen_arena_index >= 0:
		exit_fullscreen()
		get_viewport().set_input_as_handled()
		return

	# Mouse click toggles fullscreen
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_index = get_arena_at_position(event.position)

		if fullscreen_arena_index >= 0:
			# In fullscreen - only exit if clicking outside the arena
			if clicked_index != fullscreen_arena_index:
				exit_fullscreen()
				get_viewport().set_input_as_handled()
		else:
			# In grid view - enter fullscreen if clicking on an arena
			if clicked_index >= 0:
				enter_fullscreen(clicked_index)
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Handle SPACE for pause toggle (runs even when paused due to PROCESS_MODE_ALWAYS)
	var space_pressed = Input.is_physical_key_pressed(KEY_SPACE)
	if space_pressed and not _space_was_pressed:
		if current_mode == Mode.TRAINING:
			toggle_pause()
	_space_was_pressed = space_pressed


func initialize(scene: Node2D) -> void:
	## Call this when the main scene is ready.
	main_scene = scene
	player = scene.get_node("Player")

	# Setup AI controller for playback
	ai_controller = AIControllerScript.new()
	ai_controller.set_player(player)


func _load_sweep_config() -> void:
	## Load hyperparameters from sweep config if available (for W&B sweeps)
	_sweep_config.clear()

	# Check for worker ID from command line args
	_worker_id = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--worker-id="):
			_worker_id = arg.substr(12)  # len("--worker-id=") = 12
			print("Worker ID: ", _worker_id)
			break

	# Try worker-specific config first, then fall back to default
	var config_path = SWEEP_CONFIG_PATH
	if _worker_id != "":
		var worker_config_path = "user://sweep_config_%s.json" % _worker_id
		if FileAccess.file_exists(worker_config_path):
			config_path = worker_config_path

	if not FileAccess.file_exists(config_path):
		return

	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		return

	_sweep_config = json.data
	print("Loaded sweep config from %s: %s" % [config_path, _sweep_config])


func start_training(pop_size: int = 100, generations: int = 100) -> void:
	## Begin evolutionary training with parallel visible arenas.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	# Load sweep config (overrides defaults if present)
	_load_sweep_config()

	# Apply sweep config or use defaults
	population_size = int(_sweep_config.get("population_size", pop_size))
	max_generations = int(_sweep_config.get("max_generations", generations))
	evals_per_individual = int(_sweep_config.get("evals_per_individual", evals_per_individual))
	time_scale = float(_sweep_config.get("time_scale", 8.0))  # Default to 8x speed for training

	var hidden_size = int(_sweep_config.get("hidden_size", 32))
	var elite_count = int(_sweep_config.get("elite_count", 10))
	var mutation_rate = float(_sweep_config.get("mutation_rate", 0.20))
	var mutation_strength = float(_sweep_config.get("mutation_strength", 0.3))
	var crossover_rate = float(_sweep_config.get("crossover_rate", 0.7))

	# Get input size from sensor
	var sensor_instance = AISensorScript.new()
	var input_size: int = sensor_instance.TOTAL_INPUTS

	# Initialize evolution with sweep params
	evolution = EvolutionScript.new(
		population_size,
		input_size,
		hidden_size,
		6,
		elite_count,
		mutation_rate,
		mutation_strength,
		crossover_rate
	)

	evolution.generation_complete.connect(_on_generation_complete)

	# Clean up any leftover pause state
	if pause_overlay:
		destroy_pause_overlay()
	is_paused = false
	training_complete = false

	current_mode = Mode.TRAINING
	current_batch_start = 0
	generation = 0
	generations_without_improvement = 0
	best_avg_fitness = 0.0
	previous_avg_fitness = 0.0
	rerun_count = 0
	current_eval_seed = 0
	fitness_accumulator.clear()
	Engine.time_scale = time_scale

	# Clear metric history
	history_best_fitness.clear()
	history_avg_fitness.clear()
	history_min_fitness.clear()
	history_avg_kill_score.clear()
	history_avg_powerup_score.clear()
	history_avg_survival_score.clear()
	generation_total_kill_score = 0.0
	generation_total_powerup_score = 0.0
	generation_total_survival_score = 0.0

	# Hide the main game and show training arenas
	hide_main_game()
	create_training_container()

	# Generate events for all seeds upfront
	generate_all_seed_events()
	start_next_batch()

	training_status_changed.emit("Training started")
	print("Training started: pop=%d, max_gen=%d, parallel=%d, seeds=%d, early_stop=%d" % [
		population_size, max_generations, parallel_count, evals_per_individual, stagnation_limit
	])


func generate_all_seed_events() -> void:
	## Pre-generate events for all evaluation seeds this generation.
	generation_events_by_seed.clear()
	var MainScene = load("res://main.gd")
	for seed_idx in evals_per_individual:
		var seed_val = generation * 1000 + seed_idx  # Unique seed per generation+seed combo
		var events = MainScene.generate_random_events(seed_val)
		generation_events_by_seed.append(events)


func stop_training() -> void:
	## Stop training and save progress.
	if current_mode != Mode.TRAINING:
		return

	# Clean up pause state first
	if is_paused:
		destroy_pause_overlay()
		is_paused = false

	# Reset fullscreen state
	fullscreen_arena_index = -1

	current_mode = Mode.HUMAN
	Engine.time_scale = 1.0

	# Disconnect resize signal
	if get_tree().root.size_changed.is_connected(_on_training_window_resized):
		get_tree().root.size_changed.disconnect(_on_training_window_resized)

	# Cleanup training instances
	cleanup_training_instances()
	if training_container:
		var canvas_layer = training_container.get_parent()
		canvas_layer.queue_free()
		training_container = null

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
	return get_viewport().get_visible_rect().size


func create_training_container() -> void:
	## Create a CanvasLayer with SubViewports for parallel training.
	# Use CanvasLayer to ensure proper screen-space positioning
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "TrainingCanvasLayer"
	canvas_layer.layer = 100  # On top of everything
	get_tree().root.add_child(canvas_layer)

	training_container = Control.new()
	training_container.name = "TrainingContainer"
	canvas_layer.add_child(training_container)

	# Background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.05, 0.05, 0.08, 1)
	training_container.add_child(bg)

	# Stats label at top
	var stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.position = Vector2(10, 8)
	stats_label.add_theme_font_size_override("font_size", 20)
	stats_label.add_theme_color_override("font_color", Color.YELLOW)
	training_container.add_child(stats_label)

	# Set initial size
	_update_container_size()

	# Connect to window resize
	get_tree().root.size_changed.connect(_on_training_window_resized)


func _update_container_size() -> void:
	var size = get_window_size()
	training_container.position = Vector2.ZERO
	training_container.size = size
	var bg = training_container.get_node_or_null("Background")
	if bg:
		bg.position = Vector2.ZERO
		bg.size = size


func _on_training_window_resized() -> void:
	## Update grid layout when window is resized.
	if current_mode != Mode.TRAINING or not training_container:
		return

	update_grid_layout()


func get_grid_dimensions() -> Dictionary:
	## Calculate optimal grid dimensions for current parallel count.
	var cols = 5
	var rows = ceili(float(parallel_count) / cols)
	return {"cols": cols, "rows": rows}


func update_grid_layout() -> void:
	## Recalculate and apply grid positions/sizes for all arenas.
	if eval_instances.is_empty():
		return

	# Ensure container is correctly sized first
	_update_container_size()

	# If in fullscreen mode, apply fullscreen layout instead
	if fullscreen_arena_index >= 0:
		_apply_fullscreen_layout()
		return

	var size = get_window_size()
	var grid = get_grid_dimensions()
	var cols = grid.cols
	var rows = grid.rows
	var gap = 4
	var top_margin = 40

	# Simple calculation: divide available space evenly
	var arena_w = (size.x - gap * (cols + 1)) / cols
	var arena_h = (size.y - top_margin - gap * (rows + 1)) / rows

	for i in eval_instances.size():
		var col: int = i % cols
		var row: int = int(i / cols)
		var x = gap + col * (arena_w + gap)
		var y = top_margin + gap + row * (arena_h + gap)
		eval_instances[i].container.position = Vector2(x, y)
		eval_instances[i].container.size = Vector2(arena_w, arena_h)


func get_arena_at_position(pos: Vector2) -> int:
	## Return the slot index of the arena at the given screen position, or -1 if none.
	for i in eval_instances.size():
		var container = eval_instances[i].container
		if not is_instance_valid(container):
			continue
		var rect = Rect2(container.position, container.size)
		if rect.has_point(pos):
			return i
	return -1


func enter_fullscreen(slot_index: int) -> void:
	## Expand the arena at slot_index to fullscreen.
	if slot_index < 0 or slot_index >= eval_instances.size():
		return

	fullscreen_arena_index = slot_index

	# Hide all other arena containers
	for i in eval_instances.size():
		if i != slot_index and is_instance_valid(eval_instances[i].container):
			eval_instances[i].container.visible = false

	# Emit size_changed to trigger proper layout update
	get_tree().root.size_changed.emit()


func exit_fullscreen() -> void:
	## Return from fullscreen to grid view.
	fullscreen_arena_index = -1

	# Show all arena containers
	for i in eval_instances.size():
		if is_instance_valid(eval_instances[i].container):
			eval_instances[i].container.visible = true

	# Emit size_changed to trigger proper layout update
	get_tree().root.size_changed.emit()


func _apply_fullscreen_layout() -> void:
	## Position the fullscreen arena to fill the screen below the stats bar.
	if fullscreen_arena_index < 0 or fullscreen_arena_index >= eval_instances.size():
		return

	var container = eval_instances[fullscreen_arena_index].container
	if not is_instance_valid(container):
		return

	var win_size = get_window_size()
	var top_margin = 40
	var gap = 4

	var new_pos = Vector2(gap, top_margin + gap)
	var new_size = Vector2(win_size.x - gap * 2, win_size.y - top_margin - gap * 2)

	# Set position and size (same as grid layout does)
	container.position = new_pos
	container.size = new_size


func create_eval_instance(individual_index: int, grid_x: int, grid_y: int) -> Dictionary:
	## Create a SubViewport with a game instance for evaluation.
	var container = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow clicks to pass through for fullscreen toggle
	training_container.add_child(container)

	# Set initial position and size immediately (don't wait for deferred update)
	var size = get_window_size()
	var grid = get_grid_dimensions()
	var cols = grid.cols
	var rows = grid.rows
	var gap = 4
	var top_margin = 40
	var arena_w = (size.x - gap * (cols + 1)) / cols
	var arena_h = (size.y - top_margin - gap * (rows + 1)) / rows
	var x = gap + grid_x * (arena_w + gap)
	var y = top_margin + gap + grid_y * (arena_h + gap)
	container.position = Vector2(x, y)
	container.size = Vector2(arena_w, arena_h)

	# Create SubViewport
	var viewport = SubViewport.new()
	viewport.size = Vector2(1280, 720)  # Internal resolution
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	container.add_child(viewport)

	# Instantiate game scene with preset events for current seed
	var scene: Node2D = MainScenePacked.instantiate()
	scene.set_training_mode(true)  # Simplified: only pawns
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
	controller.set_network(evolution.get_individual(individual_index))

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
		"container": container,
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

	var grid = get_grid_dimensions()
	for i in range(mini(parallel_count, population_size)):
		var grid_x: int = i % grid.cols
		var grid_y: int = i / grid.cols
		var instance = create_eval_instance(i, grid_x, grid_y)
		eval_instances.append(instance)

	# Restore fullscreen state if active
	if fullscreen_arena_index >= 0:
		# Hide all except fullscreen arena
		for i in eval_instances.size():
			if i != fullscreen_arena_index:
				eval_instances[i].container.visible = false
		# Trigger layout update
		get_tree().root.size_changed.emit()


func replace_eval_instance(slot_index: int, individual_index: int) -> void:
	## Replace a completed evaluation slot with a new individual.
	var old_eval = eval_instances[slot_index]
	var grid = get_grid_dimensions()
	var grid_x: int = slot_index % grid.cols
	var grid_y: int = int(slot_index / grid.cols)

	# Clean up old instance
	if is_instance_valid(old_eval.container):
		old_eval.container.queue_free()

	# Create new instance in same slot
	var new_instance = create_eval_instance(individual_index, grid_x, grid_y)
	eval_instances[slot_index] = new_instance

	# Handle fullscreen mode
	if fullscreen_arena_index >= 0:
		if slot_index == fullscreen_arena_index:
			# This is the fullscreen slot - trigger layout update
			get_tree().root.size_changed.emit()
		else:
			# Not the fullscreen slot - hide it
			new_instance.container.visible = false


func cleanup_training_instances() -> void:
	## Clean up completed evaluation instances.
	for eval in eval_instances:
		if is_instance_valid(eval.container):
			eval.container.queue_free()
	eval_instances.clear()


func _physics_process(delta: float) -> void:
	if current_mode == Mode.HUMAN:
		return

	# Don't process training when paused (SubViewport scenes are frozen)
	if is_paused:
		return

	if current_mode == Mode.TRAINING:
		_process_parallel_training(delta)
	elif current_mode == Mode.PLAYBACK:
		_process_playback()
	elif current_mode == Mode.GENERATION_PLAYBACK:
		_process_generation_playback()


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
			# Store fitness for this individual+seed combination
			var fitness: float = eval.scene.score
			if not fitness_accumulator.has(eval.index):
				fitness_accumulator[eval.index] = []
			fitness_accumulator[eval.index].append(fitness)

			# Accumulate stats for this generation (across all seeds)
			generation_total_kill_score += eval.scene.score_from_kills
			generation_total_powerup_score += eval.scene.score_from_powerups
			var survival_score = eval.scene.score - eval.scene.score_from_kills - eval.scene.score_from_powerups
			generation_total_survival_score += survival_score

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
			# Average fitness across seeds and set final fitness
			for idx in population_size:
				var scores: Array = fitness_accumulator.get(idx, [0.0])
				var avg_fitness: float = 0.0
				for s in scores:
					avg_fitness += s
				avg_fitness /= scores.size()
				evolution.set_fitness(idx, avg_fitness)

			# Debug: print fitness distribution before evolving
			var stats = evolution.get_stats()
			print("Gen %d complete: min=%.0f avg=%.0f max=%.0f best_ever=%.0f" % [
				generation, stats.current_min, stats.current_avg, stats.current_max, stats.all_time_best
			])

			evolution.evolve()
			generation = evolution.get_generation()

			# Reset for next generation
			current_eval_seed = 0
			fitness_accumulator.clear()
			evaluated_count = 0
			next_individual = 0

			if evolution.get_generation() >= max_generations:
				show_training_complete("Reached max generations (%d)" % max_generations)
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
	update_training_stats_display()

	stats_updated.emit(get_stats())


func update_training_stats_display() -> void:
	if not training_container:
		return

	var stats_label = training_container.get_node_or_null("StatsLabel")
	if stats_label:
		var best_current = 0.0
		for eval in eval_instances:
			if not eval.done and eval.scene.score > best_current:
				best_current = eval.scene.score

		var seed_info = "seed %d/%d" % [current_eval_seed + 1, evals_per_individual]

		# Show different controls hint based on fullscreen state
		var controls_hint: String
		if fullscreen_arena_index >= 0:
			controls_hint = "[Click/ESC]=Grid [-/+]=Speed [SPACE]=Pause [T]=Stop"
		else:
			controls_hint = "[Click]=Fullscreen [-/+]=Speed [SPACE]=Pause [T]=Stop"

		stats_label.text = "Gen %d (%s) | Progress: %d/%d | Best: %.0f | All-time: %.0f | Stagnant: %d/%d | Speed: %.1fx | %s" % [
			generation,
			seed_info,
			evaluated_count,
			population_size,
			best_current,
			all_time_best,
			generations_without_improvement,
			stagnation_limit,
			time_scale,
			controls_hint
		]


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

	# Record metrics for graphing
	history_best_fitness.append(best)
	history_avg_fitness.append(avg)
	history_min_fitness.append(min_fit)

	# Record score breakdown averages (divide by total evaluations across all seeds)
	var total_evals := population_size * evals_per_individual
	var avg_kill_score := generation_total_kill_score / total_evals
	var avg_powerup_score := generation_total_powerup_score / total_evals
	var avg_survival_score := generation_total_survival_score / total_evals
	history_avg_kill_score.append(avg_kill_score)
	history_avg_powerup_score.append(avg_powerup_score)
	history_avg_survival_score.append(avg_survival_score)

	# Reset accumulators for next generation
	generation_total_kill_score = 0.0
	generation_total_powerup_score = 0.0
	generation_total_survival_score = 0.0

	# Track stagnation based on average fitness (more robust than all-time best)
	if avg > best_avg_fitness:
		generations_without_improvement = 0
		best_avg_fitness = avg
	else:
		generations_without_improvement += 1

	print("Gen %3d | Best: %6.1f | Avg: %6.1f | Kill$: %.0f | Pwr$: %.0f | Stagnant: %d/%d" % [
		gen, best, avg, avg_kill_score, avg_powerup_score, generations_without_improvement, stagnation_limit
	])

	# Auto-save every generation
	evolution.save_best(BEST_NETWORK_PATH)
	evolution.save_population(POPULATION_PATH)

	# Write metrics for W&B bridge
	_write_metrics_for_wandb()

	# Early stopping if no improvement for stagnation_limit generations
	if generations_without_improvement >= stagnation_limit:
		print("Early stopping: No improvement for %d generations" % stagnation_limit)
		show_training_complete("Early stopping: No improvement for %d generations" % stagnation_limit)


func _write_metrics_for_wandb() -> void:
	## Write metrics to JSON for W&B Python bridge to read
	var metrics = {
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
		"training_complete": training_complete,
	}

	# Use worker-specific metrics file if worker ID is set
	var metrics_path = "user://metrics.json"
	if _worker_id != "":
		metrics_path = "user://metrics_%s.json" % _worker_id

	var file = FileAccess.open(metrics_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(metrics))
		file.close()


# Playback mode functions (unchanged from before)
func start_playback() -> void:
	## Watch the best trained network play.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	var network = NeuralNetworkScript.load_from_file(BEST_NETWORK_PATH)
	if not network:
		push_error("No saved network found at " + BEST_NETWORK_PATH)
		training_status_changed.emit("No trained network found")
		return

	current_mode = Mode.PLAYBACK
	Engine.time_scale = 1.0

	ai_controller.set_network(network)
	player.enable_ai_control(true)

	reset_game()
	training_status_changed.emit("Playback started")
	print("Playing back best network")


func stop_playback() -> void:
	## Return to human control.
	current_mode = Mode.HUMAN
	player.enable_ai_control(false)
	main_scene.get_tree().paused = false
	training_status_changed.emit("Playback stopped")


func start_generation_playback() -> void:
	## Play back all generations starting from gen 1.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	generation_networks.clear()
	var gen := 1
	while true:
		var path := BEST_NETWORK_PATH.replace(".nn", "_gen_%03d.nn" % gen)
		var network = NeuralNetworkScript.load_from_file(path)
		if not network:
			break
		generation_networks.append(network)
		gen += 1

	if generation_networks.is_empty():
		push_error("No generation networks found")
		training_status_changed.emit("No generation networks found")
		return

	max_playback_generation = generation_networks.size()
	playback_generation = 1

	current_mode = Mode.GENERATION_PLAYBACK
	Engine.time_scale = 1.0

	ai_controller.set_network(generation_networks[0])
	player.enable_ai_control(true)

	reset_game()
	training_status_changed.emit("Generation playback started")
	print("Playing back generation 1 of %d" % max_playback_generation)


func advance_generation_playback() -> void:
	## Move to the next generation in playback.
	if playback_generation >= max_playback_generation:
		main_scene.game_over_label.text = "ALL GENERATIONS COMPLETE\n\nPress [G] to restart\nPress [H] for human mode"
		main_scene.game_over_label.visible = true
		player.enable_ai_control(false)
		return

	playback_generation += 1
	ai_controller.set_network(generation_networks[playback_generation - 1])
	player.enable_ai_control(true)
	reset_game()
	print("Playing back generation %d of %d" % [playback_generation, max_playback_generation])


func _process_playback() -> void:
	# Get AI action and apply to player
	var action: Dictionary = ai_controller.get_action()
	player.set_ai_action(action.move_direction, action.shoot_direction)

	if main_scene.game_over:
		main_scene.game_over_label.text = "GAME OVER\nFinal Score: %d\n\nPress [P] to replay\nPress [H] for human mode" % int(main_scene.score)
		main_scene.game_over_label.visible = true
		player.enable_ai_control(false)


func _process_generation_playback() -> void:
	# Get AI action and apply to player
	var action: Dictionary = ai_controller.get_action()
	player.set_ai_action(action.move_direction, action.shoot_direction)

	if main_scene.game_over:
		main_scene.game_over_label.text = "GENERATION %d\nScore: %d\n\nPress [SPACE] for next gen\nPress [H] for human mode" % [playback_generation, int(main_scene.score)]
		main_scene.game_over_label.visible = true
		player.enable_ai_control(false)


func reset_game() -> void:
	## Reset game state for new evaluation.
	main_scene.get_tree().paused = false

	main_scene.score = 0.0
	main_scene.lives = 3
	main_scene.game_over = false
	main_scene.entering_name = false
	main_scene.next_spawn_score = 50.0
	main_scene.next_powerup_score = 30.0
	main_scene.slow_active = false
	main_scene.survival_time = 0.0
	main_scene.last_milestone = 0

	main_scene.game_over_label.visible = false
	main_scene.name_entry.visible = false
	main_scene.name_prompt.visible = false

	var arena_center = Vector2(main_scene.ARENA_WIDTH / 2, main_scene.ARENA_HEIGHT / 2)
	player.position = arena_center
	player.is_hit = false
	player.is_speed_boosted = false
	player.is_slow_active = false
	player.speed_boost_time = 0.0
	player.slow_time = 0.0
	player.velocity = Vector2.ZERO

	for enemy in main_scene.get_tree().get_nodes_in_group("enemy"):
		enemy.free()
	for powerup in main_scene.get_tree().get_nodes_in_group("powerup"):
		powerup.free()

	main_scene.spawn_initial_enemies()
	player.activate_invincibility(1.0)


func get_stats() -> Dictionary:
	return {
		"mode": Mode.keys()[current_mode],
		"generation": generation,
		"evaluated_count": evaluated_count,
		"population_size": population_size,
		"best_fitness": best_fitness,
		"all_time_best": all_time_best,
		"current_score": main_scene.score if main_scene else 0.0,
		"playback_generation": playback_generation,
		"max_playback_generation": max_playback_generation,
		"stagnation": generations_without_improvement,
		"stagnation_limit": stagnation_limit
	}


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


# Pause functionality with metric graphs
func toggle_pause() -> void:
	if current_mode != Mode.TRAINING:
		return

	# If training complete, SPACE exits to human mode
	if training_complete:
		stop_training()
		return

	if is_paused:
		resume_training()
	else:
		pause_training()


func show_training_complete(reason: String) -> void:
	## Show results screen at end of training. SPACE will exit.
	print("Training complete: %s" % reason)
	training_complete = true
	is_paused = true

	# Freeze all evals
	for eval in eval_instances:
		if is_instance_valid(eval.viewport):
			eval.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(eval.scene):
			eval.scene.set_physics_process(false)
			eval.scene.set_process(false)

	# Save final results
	if evolution:
		evolution.save_best(BEST_NETWORK_PATH)
		evolution.save_population(POPULATION_PATH)

	# Create pause overlay with completion message
	create_pause_overlay()
	# Update title to show completion
	if pause_overlay:
		var title = pause_overlay.get_node_or_null("Control")
		if not title:
			for child in pause_overlay.get_children():
				if child is Label and "PAUSED" in child.text:
					child.text = "TRAINING COMPLETE"
					break
		var stats_label = pause_overlay.get_node_or_null("StatsLabel")
		if stats_label:
			stats_label.text = "Reason: %s\n\nGeneration: %d\nBest Fitness: %.1f\nAll-time Best: %.1f\n\n[SPACE] to exit" % [
				reason,
				generation,
				best_fitness,
				all_time_best
			]


func pause_training() -> void:
	if is_paused:
		return

	is_paused = true
	# Pause each SubViewport to freeze game state
	for eval in eval_instances:
		if is_instance_valid(eval.viewport):
			eval.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(eval.scene):
			eval.scene.set_physics_process(false)
			eval.scene.set_process(false)
	create_pause_overlay()
	print("Training paused")


func resume_training() -> void:
	if not is_paused:
		return

	is_paused = false
	# Resume each SubViewport
	for eval in eval_instances:
		if is_instance_valid(eval.viewport):
			eval.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if is_instance_valid(eval.scene):
			eval.scene.set_physics_process(true)
			eval.scene.set_process(true)
	destroy_pause_overlay()
	print("Training resumed")


func create_pause_overlay() -> void:
	if pause_overlay:
		return

	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Semi-transparent background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	pause_overlay.add_child(bg)

	# Title
	var title = Label.new()
	title.text = "TRAINING PAUSED"
	title.position = Vector2(40, 30)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.YELLOW)
	pause_overlay.add_child(title)

	# Instructions
	var instructions = Label.new()
	instructions.text = "[SPACE] Resume  |  [T] Stop Training  |  [H] Human Mode"
	instructions.position = Vector2(40, 75)
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	pause_overlay.add_child(instructions)

	# Stats summary
	var stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.position = Vector2(40, 120)
	stats_label.add_theme_font_size_override("font_size", 18)
	stats_label.add_theme_color_override("font_color", Color.WHITE)
	stats_label.text = "Generation: %d\nBest Fitness: %.1f\nAll-time Best: %.1f\nAvg Fitness: %.1f\nStagnation: %d/%d" % [
		generation,
		best_fitness,
		all_time_best,
		history_avg_fitness[-1] if history_avg_fitness.size() > 0 else 0.0,
		generations_without_improvement,
		stagnation_limit
	]
	pause_overlay.add_child(stats_label)

	# Create graph panel
	var graph_panel = create_graph_panel()
	graph_panel.position = Vector2(40, 260)
	pause_overlay.add_child(graph_panel)

	# Add to training canvas layer
	if training_container:
		var canvas = training_container.get_parent()
		canvas.add_child(pause_overlay)


func destroy_pause_overlay() -> void:
	if pause_overlay:
		pause_overlay.queue_free()
		pause_overlay = null


func create_graph_panel() -> Control:
	var panel = Control.new()
	panel.name = "GraphPanel"

	var window_size = get_window_size()
	var graph_width = window_size.x - 80
	var graph_height = window_size.y - 320

	# Graph background
	var graph_bg = ColorRect.new()
	graph_bg.size = Vector2(graph_width, graph_height)
	graph_bg.color = Color(0.1, 0.1, 0.15, 1)
	panel.add_child(graph_bg)

	# Graph border
	var border = ColorRect.new()
	border.size = Vector2(graph_width, graph_height)
	border.color = Color(0.3, 0.3, 0.4, 1)
	panel.add_child(border)

	var inner = ColorRect.new()
	inner.position = Vector2(2, 2)
	inner.size = Vector2(graph_width - 4, graph_height - 4)
	inner.color = Color(0.08, 0.08, 0.12, 1)
	panel.add_child(inner)

	# Graph title
	var graph_title = Label.new()
	graph_title.text = "Fitness Over Generations"
	graph_title.position = Vector2(10, 5)
	graph_title.add_theme_font_size_override("font_size", 16)
	graph_title.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(graph_title)

	# Legend
	var legend = create_legend()
	legend.position = Vector2(graph_width - 450, 5)
	panel.add_child(legend)

	# Draw the graph lines
	if history_best_fitness.size() > 1:
		var graph_area = Rect2(50, 35, graph_width - 70, graph_height - 60)
		var max_val = get_max_history_value()
		var min_val = 0.0

		# Y-axis labels
		for i in range(5):
			var y_val = lerpf(min_val, max_val, 1.0 - float(i) / 4.0)
			var y_pos = graph_area.position.y + graph_area.size.y * (float(i) / 4.0)
			var y_label = Label.new()
			y_label.text = "%.0f" % y_val
			y_label.position = Vector2(5, y_pos - 8)
			y_label.add_theme_font_size_override("font_size", 12)
			y_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			panel.add_child(y_label)

			# Grid line
			var grid_line = ColorRect.new()
			grid_line.position = Vector2(graph_area.position.x, y_pos)
			grid_line.size = Vector2(graph_area.size.x, 1)
			grid_line.color = Color(0.2, 0.2, 0.25, 0.5)
			panel.add_child(grid_line)

		# X-axis labels
		var x_step = maxi(1, history_best_fitness.size() / 10)
		for i in range(0, history_best_fitness.size(), x_step):
			var x_pos = graph_area.position.x + graph_area.size.x * (float(i) / (history_best_fitness.size() - 1))
			var x_label = Label.new()
			x_label.text = "%d" % (i + 1)
			x_label.position = Vector2(x_pos - 10, graph_area.position.y + graph_area.size.y + 5)
			x_label.add_theme_font_size_override("font_size", 12)
			x_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			panel.add_child(x_label)

		# Draw lines using Line2D
		var best_line = create_graph_line(history_best_fitness, graph_area, min_val, max_val, Color.GREEN)
		panel.add_child(best_line)

		var avg_line = create_graph_line(history_avg_fitness, graph_area, min_val, max_val, Color.YELLOW)
		panel.add_child(avg_line)

		var min_line = create_graph_line(history_min_fitness, graph_area, min_val, max_val, Color.RED)
		panel.add_child(min_line)

		# Survival score line (time-based score component)
		if history_avg_survival_score.size() > 1:
			var survival_line = create_graph_line(history_avg_survival_score, graph_area, min_val, max_val, Color.ORANGE)
			panel.add_child(survival_line)

		# Kill and powerup scores (already in same units as fitness/score)
		if history_avg_kill_score.size() > 1:
			var kills_line = create_graph_line(history_avg_kill_score, graph_area, min_val, max_val, Color.CYAN)
			panel.add_child(kills_line)

		if history_avg_powerup_score.size() > 1:
			var powerups_line = create_graph_line(history_avg_powerup_score, graph_area, min_val, max_val, Color.MAGENTA)
			panel.add_child(powerups_line)
	else:
		var no_data = Label.new()
		no_data.text = "Not enough data yet (need at least 2 generations)"
		no_data.position = Vector2(graph_width / 2 - 180, graph_height / 2)
		no_data.add_theme_font_size_override("font_size", 16)
		no_data.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		panel.add_child(no_data)

	return panel


func create_legend() -> Control:
	var legend = Control.new()

	var items = [
		{"label": "Best", "color": Color.GREEN},
		{"label": "Avg", "color": Color.YELLOW},
		{"label": "Min", "color": Color.RED},
		{"label": "Surv$", "color": Color.ORANGE},
		{"label": "Kill$", "color": Color.CYAN},
		{"label": "Pwr$", "color": Color.MAGENTA}
	]

	var x_offset = 0
	for item in items:
		var color_box = ColorRect.new()
		color_box.position = Vector2(x_offset, 2)
		color_box.size = Vector2(12, 12)
		color_box.color = item.color
		legend.add_child(color_box)

		var label = Label.new()
		label.text = item.label
		label.position = Vector2(x_offset + 16, 0)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", item.color)
		legend.add_child(label)

		x_offset += 70

	return legend


func create_graph_line(data: Array[float], area: Rect2, min_val: float, max_val: float, color: Color) -> Line2D:
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color
	line.antialiased = true

	var range_val = max_val - min_val
	if range_val <= 0:
		range_val = 1.0

	for i in data.size():
		var x = area.position.x + area.size.x * (float(i) / (data.size() - 1))
		var normalized = (data[i] - min_val) / range_val
		var y = area.position.y + area.size.y * (1.0 - normalized)
		line.add_point(Vector2(x, y))

	return line


func get_max_history_value() -> float:
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
