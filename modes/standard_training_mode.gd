extends TrainingModeBase
class_name StandardTrainingMode

## TRAINING mode: parallel arena evaluation with generational evolution.

var pop_size: int = 100
var max_generations: int = 100


func enter(context) -> void:
	super.enter(context)
	_start_training()


func exit() -> void:
	# Clean up pause state first
	if ctx.training_ui.is_paused:
		ctx.training_ui.destroy_pause_overlay()
		ctx.training_ui.is_paused = false

	Engine.time_scale = 1.0

	# Cleanup training instances and visual layer
	ctx.eval_instances.clear()
	ctx.arena_pool.destroy()

	# Show main game again
	ctx.show_main_game()

	if ctx.evolution:
		ctx.evolution.save_best(ctx.BEST_NETWORK_PATH)
		ctx.evolution.save_population(ctx.POPULATION_PATH)
		print("Saved best network (fitness: %.1f)" % ctx.evolution.get_all_time_best_fitness())

	ctx.training_status_changed.emit("Training stopped")


func process(delta: float) -> void:
	_process_parallel_training(delta)


func handle_input(event: InputEvent) -> void:
	# ESC exits fullscreen
	if event.is_action_pressed("ui_cancel") and ctx.arena_pool.fullscreen_index >= 0:
		ctx.arena_pool.exit_fullscreen()
		ctx.get_viewport().set_input_as_handled()
		return

	# Mouse click toggles fullscreen
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked_index = ctx.arena_pool.get_slot_at_position(event.position)
		if ctx.arena_pool.fullscreen_index >= 0:
			if clicked_index != ctx.arena_pool.fullscreen_index:
				ctx.arena_pool.exit_fullscreen()
				ctx.get_viewport().set_input_as_handled()
		else:
			if clicked_index >= 0:
				ctx.arena_pool.enter_fullscreen(clicked_index)
				ctx.get_viewport().set_input_as_handled()


# ============================================================
# Training startup
# ============================================================

func _start_training() -> void:
	ctx._load_sweep_config(pop_size, max_generations)

	# Apply config values to local state
	ctx.population_size = ctx.config.population_size
	ctx.max_generations = ctx.config.max_generations
	ctx.evals_per_individual = ctx.config.evals_per_individual
	ctx.time_scale = ctx.config.time_scale
	ctx.parallel_count = ctx.config.parallel_count

	# Get input size from sensor
	var sensor_instance = ctx.AISensorScript.new()
	var input_size: int = sensor_instance.TOTAL_INPUTS

	# Initialize evolution system
	ctx.use_neat = ctx.config.use_neat
	ctx.use_memory = ctx.config.use_memory
	if ctx.use_neat:
		var neat_config := NeatConfig.new()
		neat_config.input_count = input_size
		neat_config.output_count = 6
		neat_config.population_size = ctx.population_size
		neat_config.crossover_rate = ctx.config.crossover_rate
		neat_config.weight_mutate_rate = ctx.config.mutation_rate
		neat_config.weight_perturb_strength = ctx.config.mutation_strength
		ctx.evolution = ctx.NeatEvolutionScript.new(neat_config)
	else:
		ctx.evolution = ctx.EvolutionScript.new(
			ctx.population_size,
			input_size,
			ctx.config.hidden_size,
			6,
			ctx.config.elite_count,
			ctx.config.mutation_rate,
			ctx.config.mutation_strength,
			ctx.config.crossover_rate
		)
		ctx.evolution.use_nsga2 = ctx.use_nsga2
		if ctx.use_memory:
			ctx.evolution.enable_population_memory()

	ctx.evolution.generation_complete.connect(_on_generation_complete)

	# Initialize lineage tracker
	ctx.lineage_tracker = ctx.LineageTrackerScript.new()
	ctx.evolution.lineage = ctx.lineage_tracker

	# Clean up any leftover pause state
	if ctx.training_ui.pause_overlay:
		ctx.training_ui.destroy_pause_overlay()
	ctx.training_ui.is_paused = false
	ctx.training_ui.training_complete = false

	ctx.current_batch_start = 0
	ctx.generation = 0
	ctx.generations_without_improvement = 0
	ctx.best_avg_fitness = 0.0
	ctx.previous_avg_fitness = 0.0
	ctx.rerun_count = 0
	ctx.current_eval_seed = 0
	ctx.curriculum.reset()
	ctx.curriculum.enabled = ctx.config.curriculum_enabled
	ctx.use_nsga2 = ctx.config.use_nsga2
	ctx.stats_tracker.reset()
	ctx.use_map_elites = ctx.config.use_map_elites
	if ctx.use_map_elites:
		ctx.map_elites_archive = MapElites.new(ctx.config.map_elites_grid_size)
	Engine.time_scale = ctx.time_scale

	# Hide the main game and show training arenas
	ctx.hide_main_game()
	ctx.create_training_container()

	# Generate events for all seeds upfront
	ctx.generate_all_seed_events()
	_start_next_batch()

	ctx.training_status_changed.emit("Training started")
	var mem_label = "+memory" if ctx.use_memory else ""
	var evo_type = ("NEAT" if ctx.use_neat else ("NSGA-II" if ctx.use_nsga2 else "Standard")) + mem_label
	print("Training started: pop=%d, max_gen=%d, parallel=%d, seeds=%d, early_stop=%d, evo=%s" % [
		ctx.population_size, ctx.max_generations, ctx.parallel_count, ctx.evals_per_individual, ctx.stagnation_limit, evo_type
	])


# ============================================================
# Batch management
# ============================================================

func _start_next_batch() -> void:
	_cleanup_training_instances()

	ctx.next_individual = mini(ctx.parallel_count, ctx.population_size)
	ctx.evaluated_count = 0

	var seed_label = "seed %d/%d" % [ctx.current_eval_seed + 1, ctx.evals_per_individual]
	print("Gen %d (%s): Evaluating %d individuals..." % [ctx.generation, seed_label, ctx.population_size])

	for i in range(mini(ctx.parallel_count, ctx.population_size)):
		var instance = _create_eval_instance(i)
		ctx.eval_instances.append(instance)


func _cleanup_training_instances() -> void:
	ctx.arena_pool.cleanup_all()
	ctx.eval_instances.clear()


func _create_eval_instance(individual_index: int) -> Dictionary:
	var slot = ctx.arena_pool.create_slot()
	var viewport = slot.viewport
	var slot_index = slot.index

	var scene: Node2D = ctx.MainScenePacked.instantiate()
	scene.set_training_mode(true, ctx.get_current_curriculum_config())
	if ctx.generation_events_by_seed.size() > ctx.current_eval_seed:
		var events = ctx.generation_events_by_seed[ctx.current_eval_seed]
		var enemy_copy = events.enemy_spawns.duplicate(true)
		var powerup_copy = events.powerup_spawns.duplicate(true)
		scene.set_preset_events(events.obstacles, enemy_copy, powerup_copy)
	viewport.add_child(scene)

	var scene_player: CharacterBody2D = scene.get_node("Player")
	scene_player.enable_ai_control(true)

	var controller = ctx.AIControllerScript.new()
	controller.set_player(scene_player)
	if ctx.use_neat:
		controller.set_network(ctx.evolution.get_network(individual_index))
	else:
		controller.set_network(ctx.evolution.get_individual(individual_index))
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


func _replace_eval_instance(slot_index: int, individual_index: int) -> void:
	var slot = ctx.arena_pool.replace_slot(slot_index)
	var viewport = slot.viewport

	var scene: Node2D = ctx.MainScenePacked.instantiate()
	scene.set_training_mode(true, ctx.get_current_curriculum_config())
	if ctx.generation_events_by_seed.size() > ctx.current_eval_seed:
		var events = ctx.generation_events_by_seed[ctx.current_eval_seed]
		var enemy_copy = events.enemy_spawns.duplicate(true)
		var powerup_copy = events.powerup_spawns.duplicate(true)
		scene.set_preset_events(events.obstacles, enemy_copy, powerup_copy)
	viewport.add_child(scene)

	var scene_player: CharacterBody2D = scene.get_node("Player")
	scene_player.enable_ai_control(true)

	var controller = ctx.AIControllerScript.new()
	controller.set_player(scene_player)
	if ctx.use_neat:
		controller.set_network(ctx.evolution.get_network(individual_index))
	else:
		controller.set_network(ctx.evolution.get_individual(individual_index))
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

	ctx.eval_instances[slot_index] = {
		"slot_index": slot_index,
		"viewport": viewport,
		"scene": scene,
		"player": scene_player,
		"controller": controller,
		"index": individual_index,
		"time": 0.0,
		"done": false
	}


# ============================================================
# Parallel training processing
# ============================================================

func _process_parallel_training(delta: float) -> void:
	var active_count := 0

	for i in ctx.eval_instances.size():
		var eval = ctx.eval_instances[i]
		if eval.done:
			continue

		active_count += 1
		eval.time += delta

		# Drive AI controller
		var action: Dictionary = eval.controller.get_action()
		eval.player.set_ai_action(action.move_direction, action.shoot_direction)

		# Check if game over OR timeout (60 second max)
		var timed_out = eval.time >= 60.0
		if eval.scene.game_over or timed_out:
			var fitness: float = eval.scene.score
			var kill_score: float = eval.scene.score_from_kills
			var powerup_score: float = eval.scene.score_from_powerups
			var survival_score: float = eval.scene.score - kill_score - powerup_score
			ctx.stats_tracker.record_eval_result(eval.index, fitness, kill_score, powerup_score, survival_score)

			if ctx.use_map_elites:
				ctx.stats_tracker.record_behavior(eval.index, eval.scene.kills, eval.scene.powerups_collected, eval.scene.survival_time)

			eval.done = true
			ctx.evaluated_count += 1
			active_count -= 1

			if ctx.next_individual < ctx.population_size:
				_replace_eval_instance(i, ctx.next_individual)
				ctx.next_individual += 1

	# Check if all individuals complete for current seed
	if ctx.evaluated_count >= ctx.population_size:
		ctx.current_eval_seed += 1

		if ctx.current_eval_seed >= ctx.evals_per_individual:
			for idx in ctx.population_size:
				if ctx.use_nsga2:
					ctx.evolution.set_objectives(idx, ctx.stats_tracker.get_avg_objectives(idx))
				else:
					ctx.evolution.set_fitness(idx, ctx.stats_tracker.get_avg_fitness(idx))

			if ctx.use_map_elites and ctx.map_elites_archive:
				ctx.metrics_writer.update_map_elites_archive(ctx.map_elites_archive, ctx.evolution, ctx.stats_tracker, ctx.population_size, ctx.use_neat)

			var stats = ctx.evolution.get_stats()
			print("Gen %d complete: min=%.0f avg=%.0f max=%.0f best_ever=%.0f" % [
				ctx.generation, stats.current_min, stats.current_avg, stats.current_max, stats.all_time_best
			])

			ctx.evolution.evolve()
			ctx.generation = ctx.evolution.get_generation()

			ctx.current_eval_seed = 0
			ctx.stats_tracker.clear_accumulators()
			ctx.evaluated_count = 0
			ctx.next_individual = 0

			if ctx.evolution.get_generation() >= ctx.max_generations:
				ctx._show_training_complete("Reached max generations (%d)" % ctx.max_generations)
				ctx._write_metrics_for_wandb()
				return

			ctx.generate_all_seed_events()
			_start_next_batch()
		else:
			ctx.evaluated_count = 0
			ctx.next_individual = 0
			_start_next_batch()

	# Update stats display
	_update_training_stats_display()
	ctx.stats_updated.emit(ctx.get_stats())


# ============================================================
# Stats display
# ============================================================

func _update_training_stats_display() -> void:
	var best_current = 0.0
	for eval in ctx.eval_instances:
		if not eval.done and eval.scene.score > best_current:
			best_current = eval.scene.score

	ctx.training_ui.update_training_stats({
		"generation": ctx.generation,
		"current_eval_seed": ctx.current_eval_seed,
		"evals_per_individual": ctx.evals_per_individual,
		"evaluated_count": ctx.evaluated_count,
		"population_size": ctx.population_size,
		"best_current": best_current,
		"all_time_best": ctx.all_time_best,
		"generations_without_improvement": ctx.generations_without_improvement,
		"stagnation_limit": ctx.stagnation_limit,
		"curriculum_enabled": ctx.curriculum_enabled,
		"curriculum_label": ctx.get_curriculum_label(),
		"use_nsga2": ctx.use_nsga2,
		"pareto_front_size": ctx.evolution.pareto_front.size() if ctx.evolution and ctx.use_nsga2 else 0,
		"use_neat": ctx.use_neat,
		"neat_species_count": ctx.evolution.get_stats().species_count if ctx.evolution and ctx.use_neat else 0,
		"neat_compat_threshold": ctx.evolution.get_stats().compatibility_threshold if ctx.evolution and ctx.use_neat else 0.0,
		"use_map_elites": ctx.use_map_elites,
		"me_occupied": ctx.map_elites_archive.get_occupied_count() if ctx.map_elites_archive else 0,
		"me_total": ctx.map_elites_archive.grid_size * ctx.map_elites_archive.grid_size if ctx.map_elites_archive else 0,
		"time_scale": ctx.time_scale,
		"fullscreen": ctx.arena_pool.fullscreen_index >= 0,
	})


# ============================================================
# Generation complete callback
# ============================================================

func _on_generation_complete(gen: int, best: float, avg: float, min_fit: float) -> void:
	ctx.generation = gen
	ctx.best_fitness = best
	ctx.all_time_best = ctx.evolution.get_all_time_best_fitness()

	# Check if this generation is worse than previous (and we haven't exceeded rerun limit)
	if ctx.previous_avg_fitness > 0 and avg < ctx.previous_avg_fitness and ctx.rerun_count < ctx.MAX_RERUNS:
		ctx.rerun_count += 1
		print("Gen %3d | Avg: %6.1f < Previous: %6.1f | RE-RUNNING (attempt %d/%d)" % [
			gen, avg, ctx.previous_avg_fitness, ctx.rerun_count, ctx.MAX_RERUNS
		])
		ctx.evolution.restore_backup()
		ctx.generation = ctx.evolution.get_generation()
		return

	ctx.rerun_count = 0
	ctx.previous_avg_fitness = avg

	var score_breakdown = ctx.stats_tracker.record_generation(best, avg, min_fit, ctx.population_size, ctx.evals_per_individual)
	var avg_kill_score: float = score_breakdown.avg_kill_score
	var avg_powerup_score: float = score_breakdown.avg_powerup_score

	if avg > ctx.best_avg_fitness:
		ctx.generations_without_improvement = 0
		ctx.best_avg_fitness = avg
	else:
		ctx.generations_without_improvement += 1

	var curriculum_info = ""
	if ctx.curriculum_enabled:
		curriculum_info = " | %s" % ctx.get_curriculum_label()
	var neat_info = ""
	if ctx.use_neat and ctx.evolution:
		neat_info = " | Sp: %d" % ctx.evolution.get_species_count()
	var me_info = ""
	if ctx.use_map_elites and ctx.map_elites_archive:
		me_info = " | ME: %d (%.0f%%)" % [ctx.map_elites_archive.get_occupied_count(), ctx.map_elites_archive.get_coverage() * 100]
	print("Gen %3d | Best: %6.1f | Avg: %6.1f | Kill$: %.0f | Pwr$: %.0f | Stagnant: %d/%d%s%s%s" % [
		gen, best, avg, avg_kill_score, avg_powerup_score, ctx.generations_without_improvement, ctx.stagnation_limit, curriculum_info, neat_info, me_info
	])

	ctx.check_curriculum_advancement()

	if ctx.lineage_tracker:
		ctx.lineage_tracker.prune_old(gen)

	ctx.evolution.save_best(ctx.BEST_NETWORK_PATH)
	ctx.evolution.save_population(ctx.POPULATION_PATH)

	if ctx.use_neat:
		ctx.migration_mgr.export_best(ctx.evolution, ctx.config.worker_id, ctx.generation, ctx.MIGRATION_POOL_DIR)
		ctx.migration_mgr.try_import(ctx.evolution, ctx.config.worker_id, ctx.generation, ctx.generations_without_improvement, ctx.MIGRATION_POOL_DIR)

	ctx._write_metrics_for_wandb()

	if ctx.generations_without_improvement >= ctx.stagnation_limit:
		print("Early stopping: No improvement for %d generations" % ctx.stagnation_limit)
		ctx._show_training_complete("Early stopping: No improvement for %d generations" % ctx.stagnation_limit)
		ctx._write_metrics_for_wandb()
