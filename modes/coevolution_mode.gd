extends TrainingModeBase
class_name CoevolutionMode

## COEVOLUTION mode: dual-population co-evolutionary training.

var pop_size: int = 100
var max_generations: int = 100


func enter(context) -> void:
    super.enter(context)
    _start_coevolution()


func exit() -> void:
    if ctx.training_ui.is_paused:
        ctx.training_ui.destroy_pause_overlay()
        ctx.training_ui.is_paused = false

    Engine.time_scale = 1.0

    ctx.eval_instances.clear()
    ctx.arena_pool.destroy()

    ctx.show_main_game()

    if ctx.coevolution:
        ctx.coevolution.save_populations(ctx.POPULATION_PATH, ctx.ENEMY_POPULATION_PATH)
        ctx.coevolution.save_hall_of_fame(ctx.ENEMY_HOF_PATH)
        ctx.coevolution.player_evolution.save_best(ctx.BEST_NETWORK_PATH)
        var stats = ctx.coevolution.get_stats()
        print("Saved co-evolution (player best: %.1f, enemy best: %.1f)" % [
            stats.player.best_fitness, stats.enemy.best_fitness
        ])

    ctx.training_status_changed.emit("Co-evolution stopped")


func process(delta: float) -> void:
    _process_coevolution_training(delta)


func handle_input(event: InputEvent) -> void:
    # SPACE toggles pause
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
        ctx.toggle_pause()
        ctx.get_viewport().set_input_as_handled()
        return

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
# Coevolution startup
# ============================================================

func _start_coevolution() -> void:
    ctx._load_sweep_config(pop_size, max_generations)

    ctx.population_size = ctx.config.population_size
    ctx.max_generations = ctx.config.max_generations
    ctx.evals_per_individual = ctx.config.evals_per_individual
    ctx.time_scale = ctx.config.time_scale
    ctx.parallel_count = ctx.config.parallel_count

    var sensor_instance = ctx.AISensorScript.new()
    var input_size: int = sensor_instance.TOTAL_INPUTS

    ctx.coevolution = ctx.CoevolutionScript.new(
        ctx.population_size, input_size, ctx.config.hidden_size, 6,
        ctx.population_size,
        ctx.config.elite_count, ctx.config.mutation_rate, ctx.config.mutation_strength, ctx.config.crossover_rate
    )

    ctx.lineage_tracker = ctx.LineageTrackerScript.new()
    ctx.coevolution.player_evolution.lineage = ctx.lineage_tracker

    if ctx.training_ui.pause_overlay:
        ctx.training_ui.destroy_pause_overlay()
    ctx.training_ui.is_paused = false
    ctx.training_ui.training_complete = false

    ctx.current_batch_start = 0
    ctx.generation = 0
    ctx.generations_without_improvement = 0
    ctx.best_avg_fitness = 0.0
    ctx.previous_avg_fitness = 0.0
    ctx.current_eval_seed = 0
    ctx.curriculum.reset()
    ctx.curriculum.enabled = ctx.config.curriculum_enabled
    ctx.stats_tracker.reset()
    ctx.coevo_enemy_fitness.clear()
    ctx.coevo_enemy_stats.clear()
    ctx.coevo_is_hof_generation = false
    Engine.time_scale = ctx.time_scale

    ctx.coevolution.load_hall_of_fame(ctx.ENEMY_HOF_PATH)

    ctx.hide_main_game()
    ctx.create_training_container()

    ctx.generate_all_seed_events()
    _start_next_batch()

    ctx.training_status_changed.emit("Co-evolution training started")
    print("Co-evolution started: pop=%d, max_gen=%d, parallel=%d" % [
        ctx.population_size, ctx.max_generations, ctx.parallel_count
    ])


# ============================================================
# Batch management
# ============================================================

func _start_next_batch() -> void:
    _cleanup_training_instances()

    ctx.next_individual = mini(ctx.parallel_count, ctx.population_size)
    ctx.evaluated_count = 0
    ctx.coevo_enemy_fitness.clear()
    ctx.coevo_enemy_stats.clear()

    var seed_label = "seed %d/%d" % [ctx.current_eval_seed + 1, ctx.evals_per_individual]
    print("Gen %d (%s): Co-evolving %d player-enemy pairs..." % [ctx.generation, seed_label, ctx.population_size])

    for i in range(mini(ctx.parallel_count, ctx.population_size)):
        var enemy_idx: int = _pick_enemy_index(i)
        var instance = _create_eval_instance(i, enemy_idx)
        ctx.eval_instances.append(instance)


func _cleanup_training_instances() -> void:
    ctx.arena_pool.cleanup_all()
    ctx.eval_instances.clear()


func _pick_enemy_index(_player_index: int) -> int:
    return randi() % ctx.population_size


func _create_eval_instance(player_index: int, enemy_index: int) -> Dictionary:
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
    controller.set_network(ctx.coevolution.get_player_network(player_index))
    controller.network.reset_memory()

    var enemy_network
    if ctx.coevo_is_hof_generation:
        var hof_nets = ctx.coevolution.get_hof_networks()
        enemy_network = hof_nets[enemy_index % hof_nets.size()] if not hof_nets.is_empty() else ctx.coevolution.get_enemy_network(enemy_index)
    else:
        enemy_network = ctx.coevolution.get_enemy_network(enemy_index)

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


func _replace_eval_instance(slot_index: int, player_index: int) -> void:
    var slot = ctx.arena_pool.replace_slot(slot_index)
    var viewport = slot.viewport

    var enemy_idx: int = _pick_enemy_index(player_index)

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
    controller.set_network(ctx.coevolution.get_player_network(player_index))
    controller.network.reset_memory()

    var enemy_network
    if ctx.coevo_is_hof_generation:
        var hof_nets = ctx.coevolution.get_hof_networks()
        enemy_network = hof_nets[enemy_idx % hof_nets.size()] if not hof_nets.is_empty() else ctx.coevolution.get_enemy_network(enemy_idx)
    else:
        enemy_network = ctx.coevolution.get_enemy_network(enemy_idx)
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

    ctx.eval_instances[slot_index] = {
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


# ============================================================
# Co-evolution processing
# ============================================================

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
    var current = node.get_parent()
    while current:
        if current == ancestor:
            return true
        current = current.get_parent()
    return false


func _process_coevolution_training(delta: float) -> void:
    var active_count := 0

    for i in ctx.eval_instances.size():
        var eval = ctx.eval_instances[i]
        if eval.done:
            continue

        active_count += 1
        eval.time += delta

        var action: Dictionary = eval.controller.get_action()
        eval.player.set_ai_action(action.move_direction, action.shoot_direction)

        # Track proximity pressure
        var nearest_dist := INF
        for enemy in eval.scene.get_tree().get_nodes_in_group("enemy"):
            if is_instance_valid(enemy) and _is_descendant_of(enemy, eval.scene):
                var d = enemy.global_position.distance_to(eval.player.global_position)
                nearest_dist = minf(nearest_dist, d)
        if nearest_dist < INF:
            var closeness := 1.0 - clampf(nearest_dist / 3840.0, 0.0, 1.0)
            eval.proximity_sum += closeness
            eval.proximity_samples += 1

        # Track direction changes
        var current_dir = eval.player.velocity.normalized()
        if current_dir.length() > 0.1 and eval.last_player_dir.length() > 0.1:
            var dot = current_dir.dot(eval.last_player_dir)
            if dot < 0.5:
                eval.direction_changes += 1
        eval.last_player_dir = current_dir

        # Check game over or timeout
        var timed_out = eval.time >= 60.0
        if eval.scene.game_over or timed_out:
            var player_fitness: float = eval.scene.score
            var kill_score: float = eval.scene.score_from_kills
            var powerup_score: float = eval.scene.score_from_powerups
            var survival_score: float = eval.scene.survival_time * SURVIVAL_UNIT_SCORE
            ctx.stats_tracker.record_eval_result(eval.index, player_fitness, kill_score, powerup_score, survival_score)

            var damage_dealt: float = 3.0 - eval.scene.lives
            var avg_proximity: float = eval.proximity_sum / maxf(eval.proximity_samples, 1)
            var survival_time: float = eval.scene.survival_time
            var dir_changes: float = eval.direction_changes

            var enemy_fitness: float = ctx.CoevolutionScript.compute_enemy_fitness(
                damage_dealt, avg_proximity, survival_time, dir_changes
            )

            if not ctx.coevo_is_hof_generation:
                var eidx: int = eval.enemy_index
                if not ctx.coevo_enemy_fitness.has(eidx):
                    ctx.coevo_enemy_fitness[eidx] = []
                ctx.coevo_enemy_fitness[eidx].append(enemy_fitness)

            eval.done = true
            ctx.evaluated_count += 1
            active_count -= 1

            if ctx.next_individual < ctx.population_size:
                _replace_eval_instance(i, ctx.next_individual)
                ctx.next_individual += 1

    # Check if all individuals evaluated for current seed
    if ctx.evaluated_count >= ctx.population_size:
        ctx.current_eval_seed += 1

        if ctx.current_eval_seed >= ctx.evals_per_individual:
            for idx in ctx.population_size:
                ctx.coevolution.set_player_fitness(idx, ctx.stats_tracker.get_avg_fitness(idx))

            if not ctx.coevo_is_hof_generation:
                for eidx in ctx.population_size:
                    var scores: Array = ctx.coevo_enemy_fitness.get(eidx, [0.0])
                    var avg_ef: float = 0.0
                    if scores.size() > 0:
                        for s in scores:
                            avg_ef += s
                        avg_ef /= scores.size()
                    else:
                        avg_ef = 0.0  # Default if no scores
                    ctx.coevolution.set_enemy_fitness(eidx, avg_ef)

            var p_stats = ctx.coevolution.player_evolution.get_stats()
            var e_stats = ctx.coevolution.enemy_evolution.get_stats()
            var hof_tag = " [HoF eval]" if ctx.coevo_is_hof_generation else ""
            print("Gen %d complete%s: P(min=%.0f avg=%.0f max=%.0f) E(min=%.0f avg=%.0f max=%.0f)" % [
                ctx.generation, hof_tag,
                p_stats.current_min, p_stats.current_avg, p_stats.current_max,
                e_stats.current_min, e_stats.current_avg, e_stats.current_max
            ])

            ctx.coevolution.evolve_both()
            ctx.generation = ctx.coevolution.get_generation()
            ctx.best_fitness = ctx.coevolution.player_evolution.get_best_fitness()
            ctx.all_time_best = ctx.coevolution.player_evolution.get_all_time_best_fitness()

            var avg = p_stats.current_avg
            if avg > ctx.best_avg_fitness:
                ctx.generations_without_improvement = 0
                ctx.best_avg_fitness = avg
            else:
                ctx.generations_without_improvement += 1

            ctx.stats_tracker.record_generation(p_stats.current_max, avg, p_stats.current_min, ctx.population_size, ctx.evals_per_individual)

            ctx.check_curriculum_advancement()

            ctx.coevolution.player_evolution.save_best(ctx.BEST_NETWORK_PATH)
            ctx.coevolution.save_populations(ctx.POPULATION_PATH, ctx.ENEMY_POPULATION_PATH)
            ctx.coevolution.save_hall_of_fame(ctx.ENEMY_HOF_PATH)
            ctx._write_metrics_for_wandb()

            if ctx.generations_without_improvement >= ctx.stagnation_limit:
                print("Early stopping: No improvement for %d generations" % ctx.stagnation_limit)
                ctx._show_training_complete("Early stopping: No improvement for %d generations" % ctx.stagnation_limit)
                ctx._write_metrics_for_wandb()
                return

            if ctx.generation >= ctx.max_generations:
                ctx._show_training_complete("Reached max generations (%d)" % ctx.max_generations)
                ctx._write_metrics_for_wandb()
                return

            ctx.current_eval_seed = 0
            ctx.stats_tracker.clear_accumulators()
            ctx.coevo_is_hof_generation = ctx.coevolution.should_eval_against_hof()
            ctx.generate_all_seed_events()
            _start_next_batch()
        else:
            ctx.evaluated_count = 0
            ctx.next_individual = 0
            _start_next_batch()

    # Update stats display
    _update_coevo_stats_display()
    ctx.stats_updated.emit(ctx.get_stats())


# ============================================================
# Stats display
# ============================================================

func _update_coevo_stats_display() -> void:
    var best_current = 0.0
    for eval in ctx.eval_instances:
        if not eval.done and eval.scene.score > best_current:
            best_current = eval.scene.score

    var enemy_best_str = "?"
    if ctx.coevolution:
        enemy_best_str = "%.0f" % ctx.coevolution.enemy_evolution.get_best_fitness()

    ctx.training_ui.update_coevo_stats({
        "generation": ctx.generation,
        "current_eval_seed": ctx.current_eval_seed,
        "evals_per_individual": ctx.evals_per_individual,
        "evaluated_count": ctx.evaluated_count,
        "population_size": ctx.population_size,
        "best_current": best_current,
        "all_time_best": ctx.all_time_best,
        "generations_without_improvement": ctx.generations_without_improvement,
        "stagnation_limit": ctx.stagnation_limit,
        "coevo_is_hof_generation": ctx.coevo_is_hof_generation,
        "curriculum_enabled": ctx.curriculum_enabled,
        "curriculum_label": ctx.get_curriculum_label(),
        "enemy_best_str": enemy_best_str,
        "hof_size": ctx.coevolution.get_hof_size() if ctx.coevolution else 0,
        "time_scale": ctx.time_scale,
        "fullscreen": ctx.arena_pool.fullscreen_index >= 0,
    })
