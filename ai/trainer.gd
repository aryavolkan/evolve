extends Node

## @deprecated Use training_manager.gd for all training. Retained for test compatibility.
## Training harness for evolving neural network agents.
## Manages population evaluation and evolution cycles.

signal training_started
signal individual_evaluated(index: int, fitness: float)
signal generation_finished(gen: int, best: float, avg: float)
signal training_finished(best_fitness: float)

# Training state
var evolution: Evolution
var current_individual: int = 0
var is_training: bool = false
var evaluation_time: float = 0.0
var max_evaluation_time: float = 60.0  # Seconds per individual

# References
var main_scene: Node2D
var player: CharacterBody2D
var ai_controller: AIController

# Configuration
@export var population_size: int = 50
@export var generations: int = 100
@export var time_scale: float = 3.0  # Speed up training
@export var auto_save_interval: int = 10  # Save every N generations

# Paths
const BEST_NETWORK_PATH := "user://best_network.nn"
const POPULATION_PATH := "user://population.evo"
const TRAINING_LOG_PATH := "user://training_log.txt"

var log_file: FileAccess


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_training(scene: Node2D) -> void:
	## Begin training with the given main scene.
	main_scene = scene
	player = main_scene.get_node("Player")

	# Initialize evolution
	evolution = Evolution.new(
		population_size,
		AISensor.TOTAL_INPUTS,
		32,  # Hidden size
		6,   # Output size (move_x, move_y, 4 shoot directions)
		5,   # Elite count
		0.15,  # Mutation rate
		0.3,   # Mutation strength
		0.7    # Crossover rate
	)

	evolution.generation_complete.connect(_on_generation_complete)

	# Setup AI controller
	ai_controller = AIController.new()
	ai_controller.set_player(player)

	# Open log file
	log_file = FileAccess.open(TRAINING_LOG_PATH, FileAccess.WRITE)
	log_file.store_line("Generation,Best,Average,AllTimeBest")

	# Start
	is_training = true
	current_individual = 0
	Engine.time_scale = time_scale

	# Load the first network
	load_individual(0)

	training_started.emit()
	print("Training started with population of %d" % population_size)


func stop_training() -> void:
	## Stop training and save progress.
	is_training = false
	Engine.time_scale = 1.0

	if evolution:
		evolution.save_best(BEST_NETWORK_PATH)
		evolution.save_population(POPULATION_PATH)

	if log_file:
		log_file.close()

	var best := evolution.get_all_time_best_fitness() if evolution else 0.0
	training_finished.emit(best)
	print("Training stopped. Best fitness: %.1f" % best)


func resume_training(scene: Node2D) -> void:
	## Resume training from saved state.
	main_scene = scene
	player = main_scene.get_node("Player")

	# Initialize with same parameters
	evolution = Evolution.new(population_size, AISensor.TOTAL_INPUTS, 32, 6)

	if evolution.load_population(POPULATION_PATH):
		print("Resumed from generation %d" % evolution.get_generation())
	else:
		print("No saved population found, starting fresh")
		evolution.initialize_population()

	evolution.generation_complete.connect(_on_generation_complete)

	ai_controller = AIController.new()
	ai_controller.set_player(player)

	log_file = FileAccess.open(TRAINING_LOG_PATH, FileAccess.READ_WRITE)
	log_file.seek_end()

	is_training = true
	current_individual = 0
	Engine.time_scale = time_scale

	load_individual(0)
	training_started.emit()


func load_individual(index: int) -> void:
	## Load a specific individual's network for evaluation.
	var network := evolution.get_individual(index)
	ai_controller.set_network(network)

	# Reset game state
	reset_game()
	evaluation_time = 0.0


func reset_game() -> void:
	## Reset the game for a new evaluation.
	# Reset score
	main_scene.score = 0.0
	main_scene.lives = 3
	main_scene.game_over = false
	main_scene.next_spawn_score = 50.0
	main_scene.next_powerup_score = 30.0

	# Reset player
	player.position = Vector2.ZERO
	player.is_hit = false
	player.is_invincible = false
	player.is_speed_boosted = false
	player.is_slow_active = false
	player.speed_boost_time = 0.0
	player.invincibility_time = 0.0
	player.slow_time = 0.0
	player.velocity = Vector2.ZERO

	# Clear enemies - use free() instead of queue_free() for immediate removal
	for enemy in main_scene.get_tree().get_nodes_in_group("enemy"):
		enemy.free()

	# Clear powerups
	for powerup in main_scene.get_tree().get_nodes_in_group("powerup"):
		powerup.free()

	# Spawn initial enemies at arena edges (now safe since old ones are gone)
	main_scene.spawn_initial_enemies()


func _physics_process(delta: float) -> void:
	if not is_training:
		return

	evaluation_time += delta

	# Check if evaluation is complete (game over or time limit)
	var game_over: bool = main_scene.game_over
	var time_exceeded: bool = evaluation_time >= max_evaluation_time

	if game_over or time_exceeded:
		# Record fitness (use game score directly)
		var fitness: float = main_scene.score
		evolution.set_fitness(current_individual, fitness)
		individual_evaluated.emit(current_individual, fitness)

		# Move to next individual
		current_individual += 1

		if current_individual >= population_size:
			# Generation complete, evolve
			evolution.evolve()
			current_individual = 0

			# Check if training is complete
			if evolution.get_generation() >= generations:
				stop_training()
				return

		# Load next individual
		load_individual(current_individual)


func get_ai_action() -> Dictionary:
	## Called by the player to get the AI's action.
	if ai_controller:
		return ai_controller.get_action()
	return {"move_direction": Vector2.ZERO, "shoot_direction": Vector2.ZERO}


func is_ai_controlled() -> bool:
	return is_training


func _on_generation_complete(gen: int, best: float, avg: float) -> void:
	var all_time := evolution.get_all_time_best_fitness()

	print("Gen %d: Best=%.1f, Avg=%.1f, All-time=%.1f" % [gen, best, avg, all_time])
	generation_finished.emit(gen, best, avg)

	# Log to file
	if log_file:
		log_file.store_line("%d,%.2f,%.2f,%.2f" % [gen, best, avg, all_time])
		log_file.flush()

	# Auto-save
	if gen % auto_save_interval == 0:
		evolution.save_best(BEST_NETWORK_PATH)
		evolution.save_population(POPULATION_PATH)
		print("Auto-saved at generation %d" % gen)


func get_training_stats() -> Dictionary:
	## Get current training statistics.
	if not evolution:
		return {}

	return {
		"is_training": is_training,
		"generation": evolution.get_generation(),
		"individual": current_individual,
		"population_size": population_size,
		"eval_time": evaluation_time,
		"max_eval_time": max_evaluation_time,
		"best_fitness": evolution.get_best_fitness(),
		"all_time_best": evolution.get_all_time_best_fitness()
	}


func load_best_for_playback() -> NeuralNetwork:
	## Load the best saved network for watching it play.
	return NeuralNetwork.load_from_file(BEST_NETWORK_PATH)
