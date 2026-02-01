extends Node

## Training Manager - Orchestrates AI training and playback.
## Add this as an autoload or attach to a persistent node.

signal training_status_changed(status: String)
signal stats_updated(stats: Dictionary)

enum Mode { HUMAN, TRAINING, PLAYBACK }

var current_mode: Mode = Mode.HUMAN

# Training components (untyped to avoid preload issues)
var evolution = null
var ai_controller = null
var current_individual: int = 0
var evaluation_time: float = 0.0

# References (set when game starts)
var main_scene: Node2D
var player: CharacterBody2D

# Configuration
var population_size: int = 50
var max_generations: int = 100
var max_eval_time: float = 60.0
var time_scale: float = 2.0

# Paths
const BEST_NETWORK_PATH := "user://best_network.nn"
const POPULATION_PATH := "user://population.evo"

# Stats
var generation: int = 0
var best_fitness: float = 0.0
var all_time_best: float = 0.0


# Preloaded scripts
var NeuralNetworkScript = preload("res://ai/neural_network.gd")
var AISensorScript = preload("res://ai/sensor.gd")
var AIControllerScript = preload("res://ai/ai_controller.gd")
var EvolutionScript = preload("res://ai/evolution.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func initialize(scene: Node2D) -> void:
	## Call this when the main scene is ready.
	main_scene = scene
	player = scene.get_node("Player")

	# Setup AI controller
	ai_controller = AIControllerScript.new()
	ai_controller.set_player(player)


func start_training(pop_size: int = 50, generations: int = 100) -> void:
	## Begin evolutionary training.
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
	current_individual = 0
	generation = 0
	Engine.time_scale = time_scale

	player.enable_ai_control(true)
	load_individual(0)

	training_status_changed.emit("Training started")
	print("Training started: pop=%d, max_gen=%d" % [population_size, max_generations])


func stop_training() -> void:
	## Stop training and save progress.
	if current_mode != Mode.TRAINING:
		return

	current_mode = Mode.HUMAN
	Engine.time_scale = 1.0
	player.enable_ai_control(false)

	if evolution:
		evolution.save_best(BEST_NETWORK_PATH)
		evolution.save_population(POPULATION_PATH)
		print("Saved best network (fitness: %.1f)" % evolution.get_all_time_best_fitness())

	training_status_changed.emit("Training stopped")


func resume_training() -> void:
	## Resume from saved state.
	if not main_scene:
		push_error("Training manager not initialized")
		return

	var sensor_instance = AISensorScript.new()
	var input_size: int = sensor_instance.TOTAL_INPUTS

	evolution = EvolutionScript.new(population_size, input_size, 32, 6)

	if evolution.load_population(POPULATION_PATH):
		generation = evolution.get_generation()
		best_fitness = evolution.get_best_fitness()
		all_time_best = evolution.get_all_time_best_fitness()
		print("Resumed from generation %d (best: %.1f)" % [generation, all_time_best])
	else:
		print("No saved state, starting fresh")
		evolution.initialize_population()

	evolution.generation_complete.connect(_on_generation_complete)

	current_mode = Mode.TRAINING
	current_individual = 0
	Engine.time_scale = time_scale

	player.enable_ai_control(true)
	load_individual(0)

	training_status_changed.emit("Training resumed")


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
	# Unpause if game was paused at game over
	main_scene.get_tree().paused = false
	training_status_changed.emit("Playback stopped")


func load_individual(index: int) -> void:
	## Load a network for evaluation.
	var network = evolution.get_individual(index)
	ai_controller.set_network(network)
	reset_game()
	evaluation_time = 0.0


func reset_game() -> void:
	## Reset game state for new evaluation.
	# Unpause the game (it gets paused on game over)
	main_scene.get_tree().paused = false

	main_scene.score = 0.0
	main_scene.lives = 3
	main_scene.game_over = false
	main_scene.entering_name = false
	main_scene.next_spawn_score = 50.0
	main_scene.next_powerup_score = 30.0

	# Hide game over UI elements
	main_scene.game_over_label.visible = false
	main_scene.name_entry.visible = false
	main_scene.name_prompt.visible = false

	player.position = Vector2.ZERO
	player.is_hit = false
	player.is_speed_boosted = false
	player.is_slow_active = false
	player.speed_boost_time = 0.0
	player.slow_time = 0.0
	player.velocity = Vector2.ZERO

	# Clear entities
	for enemy in main_scene.get_tree().get_nodes_in_group("enemy"):
		enemy.queue_free()
	for powerup in main_scene.get_tree().get_nodes_in_group("powerup"):
		powerup.queue_free()

	# Give brief invincibility after reset to prevent instant death
	# (queue_free doesn't happen until end of frame)
	player.activate_invincibility(1.0)


func _physics_process(delta: float) -> void:
	if current_mode == Mode.HUMAN:
		return

	# Get AI action and apply to player
	var action: Dictionary = ai_controller.get_action()
	player.set_ai_action(action.move_direction, action.shoot_direction)

	if current_mode == Mode.TRAINING:
		_process_training(delta)
	elif current_mode == Mode.PLAYBACK:
		_process_playback()


func _process_training(delta: float) -> void:
	evaluation_time += delta

	var game_over: bool = main_scene.game_over
	var time_exceeded: bool = evaluation_time >= max_eval_time

	if game_over or time_exceeded:
		# Record fitness (game score is the fitness)
		var fitness: float = main_scene.score
		evolution.set_fitness(current_individual, fitness)

		current_individual += 1

		if current_individual >= population_size:
			# Evolve to next generation
			evolution.evolve()
			current_individual = 0

			if evolution.get_generation() >= max_generations:
				stop_training()
				return

		load_individual(current_individual)

	# Update stats
	stats_updated.emit(get_stats())


func _process_playback() -> void:
	## Handle playback mode - single run, stop when game over.
	if main_scene.game_over:
		# Show final score and stop playback
		main_scene.game_over_label.text = "GAME OVER\nFinal Score: %d\n\nPress [P] to replay\nPress [H] for human mode" % int(main_scene.score)
		main_scene.game_over_label.visible = true
		# Stop AI control but stay in playback mode so user can see the result
		player.enable_ai_control(false)


func _on_generation_complete(gen: int, best: float, avg: float) -> void:
	generation = gen
	best_fitness = best
	all_time_best = evolution.get_all_time_best_fitness()

	print("Gen %3d | Best: %6.1f | Avg: %6.1f | All-time: %6.1f" % [gen, best, avg, all_time_best])

	# Auto-save every 10 generations
	if gen % 10 == 0:
		evolution.save_best(BEST_NETWORK_PATH)
		evolution.save_population(POPULATION_PATH)


func get_stats() -> Dictionary:
	return {
		"mode": Mode.keys()[current_mode],
		"generation": generation,
		"individual": current_individual,
		"population_size": population_size,
		"eval_time": evaluation_time,
		"max_eval_time": max_eval_time,
		"best_fitness": best_fitness,
		"all_time_best": all_time_best,
		"current_score": main_scene.score if main_scene else 0.0
	}


func get_mode() -> Mode:
	return current_mode


func is_ai_active() -> bool:
	return current_mode != Mode.HUMAN
