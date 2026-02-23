extends RefCounted
## Manages all playback-type modes: playback, generation playback, archive playback,
## sandbox, and side-by-side comparison.
## Extracted from training_manager.gd to reduce its responsibility.

signal status_changed(status: String)

# Dependencies injected via setup()
var main_scene: Node2D
var player: CharacterBody2D
var ai_controller  # AIController instance
var arena_pool: RefCounted
var NeuralNetworkScript  # preloaded script
var AIControllerScript   # preloaded script
var MainScenePacked      # preloaded PackedScene
var BEST_NETWORK_PATH: String
var map_elites_archive: MapElites  # set externally before archive playback
var hide_main_game_fn: Callable
var show_main_game_fn: Callable

# Generation playback state
var playback_generation: int = 1
var max_playback_generation: int = 1
var generation_networks: Array = []

# Archive playback state
var archive_playback_cell: Vector2i = Vector2i(-1, -1)
var archive_playback_fitness: float = 0.0

# Sandbox state
var sandbox_config: Dictionary = {}

# Comparison state
var comparison_strategies: Array = []
var comparison_instances: Array = []


func setup(deps: Dictionary) -> void:
    ## Inject dependencies from training_manager.
    ## deps keys: main_scene, player, ai_controller, arena_pool,
    ##            NeuralNetworkScript, AIControllerScript, MainScenePacked,
    ##            BEST_NETWORK_PATH, hide_main_game, show_main_game
    main_scene = deps.main_scene
    player = deps.player
    ai_controller = deps.ai_controller
    arena_pool = deps.arena_pool
    NeuralNetworkScript = deps.NeuralNetworkScript
    AIControllerScript = deps.AIControllerScript
    MainScenePacked = deps.MainScenePacked
    BEST_NETWORK_PATH = deps.BEST_NETWORK_PATH
    hide_main_game_fn = deps.hide_main_game
    show_main_game_fn = deps.show_main_game


# ============================================================
# Playback (best network)
# ============================================================

func start_playback() -> void:
    ## Watch the best trained network play.
    if not main_scene:
        push_error("Training manager not initialized")
        return

    var network = NeuralNetworkScript.load_from_file(BEST_NETWORK_PATH)
    if not network:
        push_error("No saved network found at " + BEST_NETWORK_PATH)
        status_changed.emit("No trained network found")
        return

    Engine.time_scale = 1.0
    ai_controller.set_network(network)
    player.enable_ai_control(true)
    player.set_training_mode(true)

    # Update milestone rewards based on the network's achieved fitness
    # For playback, we'll use a high fitness to show the visual effects
    if player.has_method("update_fitness_milestone"):
        # Assume the best network achieved at least 175000 fitness if saved
        player.update_fitness_milestone(175000)

    reset_game()
    status_changed.emit("Playback started")
    print("Playing back best network")


func stop_playback() -> void:
    ## Return to human control.
    player.enable_ai_control(false)
    main_scene.get_tree().paused = false
    status_changed.emit("Playback stopped")


func process_playback() -> void:
    var action: Dictionary = ai_controller.get_action()
    player.set_ai_action(action.move_direction, action.shoot_direction)

    if main_scene.game_over:
        main_scene.game_over_label.text = "GAME OVER\nFinal Score: %d\n\nPress [P] to replay\nPress [H] for human mode" % int(main_scene.score)
        main_scene.game_over_label.visible = true
        player.enable_ai_control(false)


# ============================================================
# Generation playback
# ============================================================

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
        status_changed.emit("No generation networks found")
        return

    max_playback_generation = generation_networks.size()
    playback_generation = 1

    Engine.time_scale = 1.0
    ai_controller.set_network(generation_networks[0])
    player.enable_ai_control(true)

    reset_game()
    status_changed.emit("Generation playback started")
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


func process_generation_playback() -> void:
    var action: Dictionary = ai_controller.get_action()
    player.set_ai_action(action.move_direction, action.shoot_direction)

    if main_scene.game_over:
        main_scene.game_over_label.text = "GENERATION %d\nScore: %d\n\nPress [SPACE] for next gen\nPress [H] for human mode" % [playback_generation, int(main_scene.score)]
        main_scene.game_over_label.visible = true
        player.enable_ai_control(false)


# ============================================================
# Archive playback (MAP-Elites)
# ============================================================

func start_archive_playback(cell: Vector2i) -> void:
    ## Play back the MAP-Elites elite at the given grid cell.
    if not map_elites_archive:
        push_error("No MAP-Elites archive available")
        return

    var elite = map_elites_archive.get_elite(cell)
    if elite == null:
        push_error("No elite at cell (%d, %d)" % [cell.x, cell.y])
        return

    if not main_scene:
        push_error("Training manager not initialized")
        return

    archive_playback_cell = cell
    archive_playback_fitness = elite.fitness

    Engine.time_scale = 1.0
    ai_controller.set_network(elite.solution)
    player.enable_ai_control(true)

    reset_game()
    status_changed.emit("Archive playback: cell (%d, %d), fitness %.0f" % [cell.x, cell.y, elite.fitness])
    print("Archive playback: cell (%d, %d), fitness %.0f" % [cell.x, cell.y, elite.fitness])


func stop_archive_playback() -> void:
    ## Return to human control from archive playback.
    player.enable_ai_control(false)
    main_scene.get_tree().paused = false
    status_changed.emit("Archive playback stopped")


func process_archive_playback() -> void:
    var action: Dictionary = ai_controller.get_action()
    player.set_ai_action(action.move_direction, action.shoot_direction)

    if main_scene.game_over:
        main_scene.game_over_label.text = "ARCHIVE CELL (%d, %d)\nArchive Fitness: %.0f\nGame Score: %d\n\nPress [P] to replay\nPress [H] for human mode" % [
            archive_playback_cell.x, archive_playback_cell.y,
            archive_playback_fitness, int(main_scene.score)
        ]
        main_scene.game_over_label.visible = true
        player.enable_ai_control(false)


# ============================================================
# Sandbox
# ============================================================

func start_sandbox(config: Dictionary) -> void:
    ## Start sandbox mode with custom configuration.
    if not main_scene:
        push_error("Training manager not initialized")
        return

    sandbox_config = config

    Engine.time_scale = 1.0

    var enemy_types: Array = config.get("enemy_types", [0])
    var spawn_mult: float = config.get("spawn_rate_multiplier", 1.0)
    var powerup_freq: float = config.get("powerup_frequency", 1.0)
    var difficulty: float = config.get("starting_difficulty", 0.0)
    var net_source: String = config.get("network_source", "best")

    if net_source == "best":
        var network = NeuralNetworkScript.load_from_file(BEST_NETWORK_PATH)
        if network:
            ai_controller.set_network(network)
            player.enable_ai_control(true)
        else:
            push_warning("No saved network found, using human control")
    else:
        player.enable_ai_control(false)

    reset_game()
    main_scene.apply_sandbox_overrides(config)
    status_changed.emit("Sandbox mode started")
    print("Sandbox started: enemies=%s, spawn=%.1fx, powerups=%.1fx, difficulty=%.1f, network=%s" % [
        enemy_types, spawn_mult, powerup_freq, difficulty, net_source
    ])


func stop_sandbox() -> void:
    ## Stop sandbox mode and return to human control.
    player.enable_ai_control(false)
    main_scene.clear_sandbox_overrides()
    main_scene.get_tree().paused = false
    status_changed.emit("Sandbox stopped")


func process_sandbox() -> void:
    ## Process sandbox mode - drive AI if network loaded.
    if player.ai_controlled:
        var action: Dictionary = ai_controller.get_action()
        player.set_ai_action(action.move_direction, action.shoot_direction)

    if main_scene.game_over:
        player.enable_ai_control(false)


# ============================================================
# Comparison (side-by-side)
# ============================================================

func start_comparison(strategies: Array) -> void:
    ## Start side-by-side comparison with 2-4 strategies in parallel arenas.
    if not main_scene:
        push_error("Training manager not initialized")
        return

    comparison_strategies = strategies

    Engine.time_scale = 1.0

    hide_main_game_fn.call()
    arena_pool.setup(main_scene.get_tree(), strategies.size(), "ComparisonCanvasLayer", Color.CYAN)
    arena_pool.set_stats_text("SIDE-BY-SIDE COMPARISON | [H]=Stop")

    var shared_seed: int = randi()
    var events = load("res://main.gd").generate_random_events(shared_seed)

    comparison_instances.clear()
    var arena_count: int = strategies.size()

    for i in arena_count:
        var slot = arena_pool.create_slot()
        var viewport = slot.viewport

        var scene: Node2D = MainScenePacked.instantiate()
        scene.set_game_seed(shared_seed)
        var enemy_copy = events.enemy_spawns.duplicate(true)
        var powerup_copy = events.powerup_spawns.duplicate(true)
        scene.set_preset_events(events.obstacles, enemy_copy, powerup_copy)
        viewport.add_child(scene)

        var scene_player: CharacterBody2D = scene.get_node("Player")
        var controller = null

        var strategy = strategies[i]
        if strategy.source == "best":
            var network = NeuralNetworkScript.load_from_file(BEST_NETWORK_PATH)
            if network:
                scene_player.enable_ai_control(true)
                controller = AIControllerScript.new()
                controller.set_player(scene_player)
                controller.set_network(network)
        if not controller and i == 0:
            scene_player.enable_ai_control(false)

        var ui = scene.get_node("CanvasLayer/UI")
        for child in ui.get_children():
            if child.name not in ["ScoreLabel", "LivesLabel"]:
                child.visible = false

        var strat_label = Label.new()
        strat_label.name = "StrategyLabel"
        strat_label.text = "Arena %d: %s" % [i + 1, strategy.get("label", "Unknown")]
        strat_label.position = Vector2(5, 80)
        strat_label.add_theme_font_size_override("font_size", 14)
        strat_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.9))
        ui.add_child(strat_label)

        comparison_instances.append({
            "slot_index": slot.index,
            "scene": scene,
            "player": scene_player,
            "controller": controller,
            "strategy": strategy,
            "done": false,
        })

    status_changed.emit("Comparison started with %d strategies" % arena_count)
    print("Comparison started: %d arenas, seed=%d" % [arena_count, shared_seed])


func stop_comparison() -> void:
    ## Stop comparison mode.
    Engine.time_scale = 1.0

    comparison_instances.clear()
    arena_pool.destroy()

    show_main_game_fn.call()
    status_changed.emit("Comparison stopped")


func process_comparison(delta: float) -> void:
    ## Drive AI controllers and update stats for comparison arenas.
    var all_done := true

    for inst in comparison_instances:
        if inst.done:
            continue

        if inst.controller:
            var action: Dictionary = inst.controller.get_action()
            inst.player.set_ai_action(action.move_direction, action.shoot_direction)

        if inst.scene.game_over:
            inst.done = true
        else:
            all_done = false

    var parts: Array = ["COMPARISON"]
    for i in comparison_instances.size():
        var inst = comparison_instances[i]
        var status_str: String
        if inst.done:
            status_str = "Arena %d: Score %d (DONE)" % [i + 1, int(inst.scene.score)]
        else:
            status_str = "Arena %d: Score %d | Kills %d | Lives %d" % [
                i + 1, int(inst.scene.score), inst.scene.kills, inst.scene.lives
            ]
        parts.append(status_str)
    parts.append("[H]=Stop")
    arena_pool.set_stats_text(" | ".join(parts))


# ============================================================
# Game reset
# ============================================================

func reset_game() -> void:
    ## Reset game state for new evaluation.
    main_scene.get_tree().paused = false

    main_scene.score = 0.0
    main_scene.lives = 3
    main_scene.game_over = false
    main_scene.entering_name = false
    main_scene.next_spawn_score = 50.0
    main_scene.next_powerup_score = 30.0
    main_scene.survival_time = 0.0
    main_scene.last_milestone = 0

    main_scene.game_over_label.visible = false
    main_scene.name_entry.visible = false
    main_scene.name_prompt.visible = false

    var arena_center = Vector2(main_scene.effective_arena_width / 2, main_scene.effective_arena_height / 2)
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
