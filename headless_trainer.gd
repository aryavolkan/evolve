extends SceneTree

## Headless training script - run with: godot --headless --script res://headless_trainer.gd
## Evaluates networks in parallel using multiple scene instances.

var NeuralNetworkScript = preload("res://ai/neural_network.gd")
var SensorScript = preload("res://ai/sensor.gd")
var AIControllerScript = preload("res://ai/ai_controller.gd")
var EvolutionScript = preload("res://ai/evolution.gd")

var main_scene_packed: PackedScene = preload("res://main.tscn")

# Configuration
var population_size: int = 50
var max_generations: int = 100
var max_eval_time: float = 60.0
var parallel_evals: int = 10  # Number of parallel evaluations

# State
var evolution = null
var current_generation: int = 0
var current_batch_start: int = 0

# Parallel evaluation instances
var eval_instances: Array = []  # Array of {scene, controller, index, time, done}

const BEST_NETWORK_PATH := "user://best_network.nn"
const POPULATION_PATH := "user://population.evo"


func _init() -> void:
	# Parse command line arguments
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		match args[i]:
			"--population", "-p":
				if i + 1 < args.size():
					population_size = int(args[i + 1])
			"--generations", "-g":
				if i + 1 < args.size():
					max_generations = int(args[i + 1])
			"--parallel", "-j":
				if i + 1 < args.size():
					parallel_evals = int(args[i + 1])
			"--eval-time", "-t":
				if i + 1 < args.size():
					max_eval_time = float(args[i + 1])

	print("=== Headless Neuroevolution Trainer ===")
	print("Population: %d | Generations: %d | Parallel: %d | Eval time: %.0fs" % [
		population_size, max_generations, parallel_evals, max_eval_time
	])
	print("")

	# Get input size from sensor
	var sensor_instance = SensorScript.new()
	var input_size: int = sensor_instance.TOTAL_INPUTS

	# Initialize evolution
	evolution = EvolutionScript.new(
		population_size,
		input_size,
		32,  # Hidden size
		6,   # Output size
		5,   # Elite count
		0.15,  # Mutation rate
		0.3,   # Mutation strength
		0.7    # Crossover rate
	)

	evolution.generation_complete.connect(_on_generation_complete)

	# Try to resume from saved state
	if evolution.load_population(POPULATION_PATH):
		current_generation = evolution.get_generation()
		print("Resumed from generation %d" % current_generation)
	else:
		print("Starting fresh training")

	# Start first batch
	start_next_batch()


func _physics_process(delta: float) -> bool:
	var all_done := true

	for eval in eval_instances:
		if eval.done:
			continue

		all_done = false
		eval.time += delta

		# Drive AI controller
		var action: Dictionary = eval.controller.get_action()
		eval.player.set_ai_action(action.move_direction, action.shoot_direction)

		var scene: Node2D = eval.scene
		var game_over: bool = scene.game_over
		var time_exceeded: bool = eval.time >= max_eval_time

		# Handle game pause on death
		if scene.get_tree():
			scene.get_tree().paused = false

		if game_over or time_exceeded:
			# Record fitness
			var fitness: float = scene.score
			evolution.set_fitness(eval.index, fitness)
			eval.done = true

			# Brief progress indicator
			var done_count: int = 0
			for e in eval_instances:
				if e.done:
					done_count += 1
			var progress: int = current_batch_start + done_count
			print("  [%d/%d] Individual %d: %.1f pts" % [progress, population_size, eval.index, fitness])

	if all_done and eval_instances.size() > 0:
		# Batch complete, start next or evolve
		cleanup_instances()

		current_batch_start += parallel_evals
		if current_batch_start >= population_size:
			# Generation complete
			evolution.evolve()
			current_batch_start = 0

			if evolution.get_generation() >= max_generations:
				finish_training()
				return true  # Signal to quit

		start_next_batch()

	return false  # Keep running


func start_next_batch() -> void:
	## Start evaluating the next batch of individuals in parallel.
	var batch_end: int = mini(current_batch_start + parallel_evals, population_size)

	print("Gen %d: Evaluating individuals %d-%d..." % [
		evolution.get_generation(), current_batch_start, batch_end - 1
	])

	for i in range(current_batch_start, batch_end):
		var instance: Dictionary = create_eval_instance(i)
		eval_instances.append(instance)


func create_eval_instance(individual_index: int) -> Dictionary:
	## Create a new game instance for evaluating one individual.
	var scene: Node2D = main_scene_packed.instantiate()
	root.add_child(scene)

	# Get player and set up AI control
	var player: CharacterBody2D = scene.get_node("Player")
	player.enable_ai_control(true)

	# Create AI controller with this individual's network
	var controller = AIControllerScript.new()
	controller.set_player(player)
	controller.set_network(evolution.get_individual(individual_index))

	# Hide game over UI if it exists (may not be ready yet, that's ok)
	if scene.game_over_label:
		scene.game_over_label.visible = false
	if scene.name_entry:
		scene.name_entry.visible = false
	if scene.name_prompt:
		scene.name_prompt.visible = false

	return {
		"scene": scene,
		"player": player,
		"controller": controller,
		"index": individual_index,
		"time": 0.0,
		"done": false
	}


func cleanup_instances() -> void:
	## Clean up completed evaluation instances.
	for eval in eval_instances:
		if is_instance_valid(eval.scene):
			eval.scene.queue_free()
	eval_instances.clear()


func _on_generation_complete(gen: int, best: float, avg: float) -> void:
	var all_time: float = evolution.get_all_time_best_fitness()

	print("")
	print("=== Generation %d Complete ===" % gen)
	print("  Best: %.1f | Avg: %.1f | All-time: %.1f" % [best, avg, all_time])
	print("")

	# Auto-save
	evolution.save_best(BEST_NETWORK_PATH)
	evolution.save_generation_best(BEST_NETWORK_PATH)  # Save per-generation best
	evolution.save_population(POPULATION_PATH)


func finish_training() -> void:
	## Training complete.
	print("")
	print("========================================")
	print("Training Complete!")
	print("Final best fitness: %.1f" % evolution.get_all_time_best_fitness())
	print("Saved to: %s" % BEST_NETWORK_PATH)
	print("========================================")

	# Save final state
	evolution.save_best(BEST_NETWORK_PATH)
	evolution.save_population(POPULATION_PATH)

	# Exit
	quit(0)
