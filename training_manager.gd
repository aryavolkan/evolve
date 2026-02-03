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
var population_size: int = 48
var max_generations: int = 100
var time_scale: float = 1.0
var parallel_count: int = 10  # Number of parallel arenas (5x2 grid)

# Rolling evaluation - next individual to evaluate
var next_individual: int = 0
var evaluated_count: int = 0

# Paths
const BEST_NETWORK_PATH := "user://best_network.nn"
const POPULATION_PATH := "user://population.evo"

# Stats
var generation: int = 0
var best_fitness: float = 0.0
var all_time_best: float = 0.0

# Early stopping
var stagnation_limit: int = 3
var generations_without_improvement: int = 0
var previous_all_time_best: float = 0.0

# Generation playback state
var playback_generation: int = 1
var max_playback_generation: int = 1
var generation_networks: Array = []

# Parallel training instances
var eval_instances: Array = []  # Array of {viewport, scene, controller, index, time, done}
var training_container: Control  # Container for all training viewports
var ai_controller = null  # For playback mode

# Preloaded scripts
var NeuralNetworkScript = preload("res://ai/neural_network.gd")
var AISensorScript = preload("res://ai/sensor.gd")
var AIControllerScript = preload("res://ai/ai_controller.gd")
var EvolutionScript = preload("res://ai/evolution.gd")
var MainScenePacked = preload("res://main.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func initialize(scene: Node2D) -> void:
	## Call this when the main scene is ready.
	main_scene = scene
	player = scene.get_node("Player")

	# Setup AI controller for playback
	ai_controller = AIControllerScript.new()
	ai_controller.set_player(player)


func start_training(pop_size: int = 50, generations: int = 100) -> void:
	## Begin evolutionary training with parallel visible arenas.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	population_size = pop_size
	max_generations = generations

	# Get input size from sensor
	var sensor_instance = AISensorScript.new()
	var input_size: int = sensor_instance.TOTAL_INPUTS

	# Initialize evolution
	evolution = EvolutionScript.new(
		population_size,
		input_size,
		32,
		6,
		5,     # Elite count
		0.15,  # Mutation rate
		0.3,   # Mutation strength
		0.7    # Crossover rate
	)

	evolution.generation_complete.connect(_on_generation_complete)

	current_mode = Mode.TRAINING
	current_batch_start = 0
	generation = 0
	generations_without_improvement = 0
	previous_all_time_best = 0.0
	Engine.time_scale = time_scale

	# Hide the main game and show training arenas
	hide_main_game()
	create_training_container()
	start_next_batch()

	training_status_changed.emit("Training started")
	print("Training started: pop=%d, max_gen=%d, parallel=%d, early_stop=%d" % [
		population_size, max_generations, parallel_count, stagnation_limit
	])


func stop_training() -> void:
	## Stop training and save progress.
	if current_mode != Mode.TRAINING:
		return

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


func update_grid_layout() -> void:
	## Recalculate and apply grid positions/sizes for all arenas.
	if eval_instances.is_empty():
		return

	# Ensure container is correctly sized first
	_update_container_size()

	var size = get_window_size()
	var cols = 5
	var rows = 2
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


func create_eval_instance(individual_index: int, grid_x: int, grid_y: int) -> Dictionary:
	## Create a SubViewport with a game instance for evaluation.
	var container = SubViewportContainer.new()
	container.stretch = true
	training_container.add_child(container)

	# Set initial position and size immediately (don't wait for deferred update)
	var size = get_window_size()
	var cols = 5
	var rows = 2
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

	# Instantiate game scene
	var scene: Node2D = MainScenePacked.instantiate()
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
	## Start evaluating the first batch of individuals (rolling replacement after).
	cleanup_training_instances()

	# Reset rolling counters
	next_individual = parallel_count  # First 10 are started, next is #10
	evaluated_count = 0

	print("Gen %d: Starting evaluation (rolling batches of %d)..." % [generation, parallel_count])

	for i in range(parallel_count):
		var grid_x: int = i % 5
		var grid_y: int = i / 5
		var instance = create_eval_instance(i, grid_x, grid_y)
		eval_instances.append(instance)


func replace_eval_instance(slot_index: int, individual_index: int) -> void:
	## Replace a completed evaluation slot with a new individual.
	var old_eval = eval_instances[slot_index]
	var grid_x: int = slot_index % 5
	var grid_y: int = int(slot_index / 5)

	# Clean up old instance
	if is_instance_valid(old_eval.container):
		old_eval.container.queue_free()

	# Create new instance in same slot
	var new_instance = create_eval_instance(individual_index, grid_x, grid_y)
	eval_instances[slot_index] = new_instance


func cleanup_training_instances() -> void:
	## Clean up completed evaluation instances.
	for eval in eval_instances:
		if is_instance_valid(eval.container):
			eval.container.queue_free()
	eval_instances.clear()


func _physics_process(delta: float) -> void:
	if current_mode == Mode.HUMAN:
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

		# Check if game over (no time limit)
		if eval.scene.game_over:
			var fitness: float = eval.scene.score
			evolution.set_fitness(eval.index, fitness)
			eval.done = true
			evaluated_count += 1
			active_count -= 1

			# Replace with next individual if available
			if next_individual < population_size:
				replace_eval_instance(i, next_individual)
				next_individual += 1

	# Check if generation complete
	if evaluated_count >= population_size:
		evolution.evolve()
		evaluated_count = 0
		next_individual = 0

		if evolution.get_generation() >= max_generations:
			stop_training()
			return

		# Start fresh batch for new generation
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

		stats_label.text = "Gen %d | Progress: %d/%d | Best: %.0f | All-time: %.0f | Stagnant: %d/%d | Speed: %.2fx | [-/+] [T]=Stop [H]=Human" % [
			generation,
			evaluated_count,
			population_size,
			best_current,
			all_time_best,
			generations_without_improvement,
			stagnation_limit,
			time_scale
		]


func _on_generation_complete(gen: int, best: float, avg: float) -> void:
	generation = gen
	best_fitness = best
	all_time_best = evolution.get_all_time_best_fitness()

	# Track stagnation for early stopping
	if all_time_best > previous_all_time_best:
		generations_without_improvement = 0
		previous_all_time_best = all_time_best
	else:
		generations_without_improvement += 1

	print("Gen %3d | Best: %6.1f | Avg: %6.1f | All-time: %6.1f | Stagnant: %d/%d" % [
		gen, best, avg, all_time_best, generations_without_improvement, stagnation_limit
	])

	# Auto-save every generation
	evolution.save_best(BEST_NETWORK_PATH)
	evolution.save_population(POPULATION_PATH)

	# Early stopping if no improvement for stagnation_limit generations
	if generations_without_improvement >= stagnation_limit:
		print("Early stopping: No improvement for %d generations" % stagnation_limit)
		stop_training()


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


const SPEED_STEPS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]

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
