extends RefCounted
class_name RtNeatManager

## Orchestrates rtNEAT mode: spawns agents into a single shared arena,
## drives AI each frame, and replaces worst agents with new offspring.

const InteractionToolsScript = preload("res://ai/agent_interaction_tools.gd")
const Tool = InteractionToolsScript.Tool
const BLESS_FITNESS: float = InteractionToolsScript.BLESS_FITNESS
const CURSE_FITNESS: float = InteractionToolsScript.CURSE_FITNESS
const MAX_LOG_ENTRIES: int = InteractionToolsScript.MAX_LOG_ENTRIES
const SPEED_STEPS: Array[float] = InteractionToolsScript.SPEED_STEPS
const WAVE_SIZE: int = InteractionToolsScript.WAVE_SIZE
const WAVE_SPREAD: float = InteractionToolsScript.WAVE_SPREAD
const OBSTACLE_REMOVE_RADIUS: float = InteractionToolsScript.OBSTACLE_REMOVE_RADIUS

var AISensorScript = preload("res://ai/sensor.gd")
var AIControllerScript = preload("res://ai/ai_controller.gd")
var AgentScenePacked: PackedScene = null  # Loaded lazily in start()

# Core references
var RtNeatPopulationScript = preload("res://ai/rtneat_population.gd")

var main_scene: Node2D = null
var population = null  # RtNeatPopulation
var overlay = null  # RtNeatOverlay (set externally)

# Per-agent parallel arrays
var agents: Array = []  # Array[CharacterBody2D] (agent.gd instances)
var sensors: Array = []  # Array[Sensor]
var controllers: Array = []  # Array[AIController]

# Configuration
var agent_count: int = 30

# Interaction tools (delegated)
var interaction_tools = InteractionToolsScript.new()

# Replacement log and player obstacles (shared with interaction_tools)
var replacement_log: Array = []
var player_obstacles: Array = []

# Backward-compatible accessors delegating to interaction_tools
var current_tool: int:
    get: return interaction_tools.current_tool
    set(v): interaction_tools.current_tool = v

var time_scale: float:
    get: return interaction_tools.time_scale
    set(v): interaction_tools.time_scale = v

# Inspected agent
var inspected_agent_index: int = -1

# Novelty search
var novelty_search: NoveltySearch = null
var _agent_behavior_data: Array = []  # Per-agent behavior tracking
var _agent_start_positions: Array = []  # Per-agent spawn positions
var _agent_move_directions: Array = []  # Per-agent movement direction history

# State
var _running: bool = false
var _total_time: float = 0.0


func _init() -> void:
    interaction_tools.replacement_log = replacement_log
    interaction_tools.player_obstacles = player_obstacles


func setup(scene: Node2D, config: Dictionary = {}) -> void:
    ## Store main scene reference and configure parameters.
    main_scene = scene
    agent_count = config.get("agent_count", 30)
    var replacement_interval: float = config.get("replacement_interval", 15.0)
    var min_lifetime: float = config.get("min_lifetime", 10.0)

    # Create population
    population = RtNeatPopulationScript.new()

    var neat_config := NeatConfig.new()
    neat_config.input_count = 86  # From sensor.gd TOTAL_INPUTS
    neat_config.output_count = 6
    neat_config.population_size = agent_count

    population.replacement_interval = replacement_interval
    population.min_lifetime = min_lifetime
    population.initialize(agent_count, neat_config)

    # Initialize novelty search
    novelty_search = NoveltySearch.new()
    novelty_search.novelty_weight = config.get("novelty_weight", 0.3)
    novelty_search.k_nearest = config.get("novelty_k", 15)

    _configure_interaction_tools()


func _configure_interaction_tools() -> void:
    interaction_tools.setup(main_scene, {
        "bless_fn": Callable(self, "_bless_agent"),
        "curse_fn": Callable(self, "_curse_agent"),
        "on_tool_changed": Callable(self, "_handle_tool_changed"),
        "player_obstacles": player_obstacles,
        "replacement_log": replacement_log,
    })
    interaction_tools.reset_time()


func _handle_tool_changed(tool: int) -> void:
    if tool != Tool.INSPECT:
        clear_inspection()


func start() -> void:
    ## Spawn all agents into the scene.
    if not main_scene or not population:
        push_error("RtNeatManager: not set up")
        return

    _running = true
    _total_time = 0.0
    interaction_tools.reset_time()
    replacement_log.clear()
    _agent_behavior_data.clear()
    _agent_start_positions.clear()
    _agent_move_directions.clear()

    # Lazy-load agent scene
    if not AgentScenePacked:
        AgentScenePacked = load("res://agent.tscn")

    # Enable training mode adjustments on the main scene
    main_scene.training_mode = true

    # Spawn agents in a ring around arena center
    var arena_center := Vector2(main_scene.effective_arena_width / 2.0, main_scene.effective_arena_height / 2.0)
    var ring_radius: float = 400.0

    for i in agent_count:
        var agent = AgentScenePacked.instantiate()
        agent.agent_id = i
        agent.species_color = population.get_species_color(i)

        # Position in a ring
        var angle: float = TAU * i / agent_count
        agent.position = arena_center + Vector2(cos(angle), sin(angle)) * ring_radius

        main_scene.add_child(agent)

        # Create sensor + controller wired to this agent's network
        var sensor = AISensorScript.new()
        sensor.set_player(agent)

        var controller = AIControllerScript.new()
        controller.sensor = sensor
        controller.set_network(population.networks[i])

        agents.append(agent)
        sensors.append(sensor)
        controllers.append(controller)
        _agent_behavior_data.append(_new_behavior_data())
        _agent_start_positions.append(agent.position)
        _agent_move_directions.append([])

        # Connect signals for fitness tracking
        agent.enemy_killed.connect(_on_agent_enemy_killed.bind(i))
        agent.died.connect(_on_agent_died.bind(i))
        agent.powerup_collected_by_agent.connect(_on_agent_powerup.bind(i))
        agent.shot_fired.connect(_on_agent_shot_fired.bind(i))

        # Start with brief invincibility
        agent.activate_invincibility(2.0)


func stop() -> void:
    ## Remove all agents and cleanup.
    _running = false
    Engine.time_scale = 1.0

    for agent in agents:
        if is_instance_valid(agent):
            agent.queue_free()

    # Clean up player-placed obstacles
    for obs in player_obstacles:
        if is_instance_valid(obs):
            obs.queue_free()
    player_obstacles.clear()
    interaction_tools.current_tool = Tool.INSPECT

    agents.clear()
    sensors.clear()
    controllers.clear()
    inspected_agent_index = -1

    if overlay and is_instance_valid(overlay):
        overlay.queue_free()
        overlay = null


func process(delta: float) -> void:
    ## Called every physics frame by training_manager.
    if not _running:
        return

    _total_time += delta
    interaction_tools.update_time(delta)

    # 1. Drive each alive agent
    for i in agent_count:
        if not population.alive[i]:
            continue
        if not is_instance_valid(agents[i]) or agents[i].is_dead:
            continue

        # AI decision
        var action: Dictionary = controllers[i].get_action()
        agents[i].set_ai_action(action.move_direction, action.shoot_direction)

        # Accumulate survival fitness
        population.update_fitness(i, delta * 5.0)

        # Track behavior for novelty search
        if i < _agent_behavior_data.size():
            var bd: Dictionary = _agent_behavior_data[i]
            bd["distance_traveled"] += agents[i].position.distance_to(bd.get("_last_pos", agents[i].position))
            bd["_last_pos"] = agents[i].position
            bd["time_alive"] += delta
            var center := Vector2(main_scene.effective_arena_width / 2.0, main_scene.effective_arena_height / 2.0)
            bd["_center_dist_sum"] += agents[i].position.distance_to(center)
            bd["_center_dist_count"] += 1
            # Track movement direction for entropy
            if action.move_direction.length_squared() > 0.01 and i < _agent_move_directions.size():
                _agent_move_directions[i].append(action.move_direction.angle())

    # 2. Check for replacement
    var idx: int = population.tick(delta)
    if idx >= 0:
        _do_agent_replacement(idx)

    # 3. Update overlay
    if overlay and is_instance_valid(overlay):
        overlay.update_display(population.get_stats(), replacement_log, time_scale, inspected_agent_index, current_tool)


func _do_agent_replacement(index: int) -> void:
    ## Replace the agent at index with a new offspring.
    var old_fitness: float = population.fitnesses[index]

    # Compute novelty for the departing agent and blend into fitness
    if novelty_search and index < _agent_behavior_data.size():
        var bd: Dictionary = _agent_behavior_data[index]
        if is_instance_valid(agents[index]):
            bd["final_x"] = agents[index].position.x
            bd["final_y"] = agents[index].position.y
        bd["avg_center_distance"] = bd["_center_dist_sum"] / maxf(bd["_center_dist_count"], 1.0)
        bd["movement_entropy"] = _compute_movement_entropy(index)

        var bc: PackedFloat32Array = NoveltySearch.characterize(bd, main_scene.effective_arena_width, main_scene.effective_arena_height)

        # Gather current population BCs
        var pop_bcs: Array[PackedFloat32Array] = []
        for j in agent_count:
            if j != index and j < _agent_behavior_data.size():
                var jbd: Dictionary = _agent_behavior_data[j]
                if is_instance_valid(agents[j]):
                    jbd["final_x"] = agents[j].position.x
                    jbd["final_y"] = agents[j].position.y
                jbd["avg_center_distance"] = jbd["_center_dist_sum"] / maxf(jbd["_center_dist_count"], 1.0)
                pop_bcs.append(NoveltySearch.characterize(jbd, main_scene.effective_arena_width, main_scene.effective_arena_height))

        var novelty_score: float = novelty_search.compute_novelty(bc, pop_bcs)
        novelty_search.maybe_add_to_archive(bc, novelty_score)

        # Blend novelty into the fitness used for parent selection
        # Scale novelty to be on similar magnitude as fitness
        var scaled_novelty: float = novelty_score * 1000.0
        population.fitnesses[index] = novelty_search.blend_fitness(old_fitness, scaled_novelty)

    # Get replacement data from population
    var result: Dictionary = population.do_replacement(index)

    # Log the replacement
    var log_entry := "Replaced #%d (fit: %.0f) → offspring of #%d × #%d" % [
        index, old_fitness, result.parent_a, result.parent_b
    ]
    _log_event(log_entry)

    # Remove old agent
    if is_instance_valid(agents[index]):
        agents[index].queue_free()

    # Spawn new agent
    var agent = AgentScenePacked.instantiate()
    agent.agent_id = index
    agent.species_color = result.species_color

    # Position at arena center with invincibility
    var arena_center := Vector2(main_scene.effective_arena_width / 2.0, main_scene.effective_arena_height / 2.0)
    agent.position = arena_center
    main_scene.add_child(agent)

    # Wire new sensor + controller
    var sensor = AISensorScript.new()
    sensor.set_player(agent)

    var controller = AIControllerScript.new()
    controller.sensor = sensor
    controller.set_network(result.network)

    agents[index] = agent
    sensors[index] = sensor
    controllers[index] = controller

    # Reconnect signals
    agent.enemy_killed.connect(_on_agent_enemy_killed.bind(index))
    agent.died.connect(_on_agent_died.bind(index))
    agent.powerup_collected_by_agent.connect(_on_agent_powerup.bind(index))
    agent.shot_fired.connect(_on_agent_shot_fired.bind(index))

    # Start with brief invincibility
    agent.activate_invincibility(2.0)

    # Reset behavior tracking for new agent
    if index < _agent_behavior_data.size():
        _agent_behavior_data[index] = _new_behavior_data()
        _agent_start_positions[index] = agent.position
        _agent_move_directions[index] = []

    # Clear inspected if it was this agent
    if inspected_agent_index == index:
        inspected_agent_index = -1


# Signal handlers for fitness accumulation
func _on_agent_enemy_killed(pos: Vector2, points: int, agent_index: int) -> void:
    var bonus: float = points * 1000.0  # Chess value × 1000
    population.update_fitness(agent_index, bonus)
    if agent_index < _agent_behavior_data.size():
        _agent_behavior_data[agent_index]["enemies_killed"] += 1


func _on_agent_died(_agent: CharacterBody2D, agent_index: int) -> void:
    population.mark_dead(agent_index)


func _on_agent_powerup(_agent: CharacterBody2D, _type: String, agent_index: int) -> void:
    population.update_fitness(agent_index, 5000.0)
    if agent_index < _agent_behavior_data.size():
        _agent_behavior_data[agent_index]["powerups_collected"] += 1


func _on_agent_shot_fired(direction: Vector2, agent_index: int) -> void:
    ## Reward shooting toward enemies (training shaping).
    if agent_index < 0 or agent_index >= agents.size():
        return
    var agent = agents[agent_index]
    if not is_instance_valid(agent):
        return
    for child in main_scene.get_children():
        if child.is_in_group("enemy") and is_instance_valid(child):
            var to_enemy = (child.position - agent.position).normalized()
            var dot = direction.dot(to_enemy)
            var dist = agent.position.distance_to(child.position)
            if dot > 0.7 and dist < 800:
                population.update_fitness(agent_index, 50.0)
                return


# ============================================================
# Interaction tools — delegated to AgentInteractionTools
# ============================================================

func adjust_speed(direction: float) -> void:
    interaction_tools.adjust_speed(direction)


func set_tool(tool: int) -> void:
    interaction_tools.set_tool(tool)
    if tool != Tool.INSPECT:
        clear_inspection()


func get_tool_name() -> String:
    return interaction_tools.get_tool_name()


func handle_click(world_pos: Vector2) -> bool:
    return interaction_tools.handle_click(world_pos)


func _log_event(text: String) -> void:
    interaction_tools.log_event(text)


# Click-to-inspect
func get_agent_at_position(world_pos: Vector2) -> int:
    ## Find nearest agent to world position. Returns index or -1.
    var nearest_idx: int = -1
    var nearest_dist: float = 60.0  # Click radius threshold
    for i in agent_count:
        if not is_instance_valid(agents[i]) or agents[i].is_dead:
            continue
        var dist: float = agents[i].global_position.distance_to(world_pos)
        if dist < nearest_dist:
            nearest_dist = dist
            nearest_idx = i
    return nearest_idx


func inspect_agent(index: int) -> Dictionary:
    ## Get detailed info about an agent for the inspect panel.
    if index < 0 or index >= agent_count:
        return {}
    inspected_agent_index = index
    return {
        "agent_id": index,
        "species_id": population.species_ids[index],
        "species_color": population.get_species_color(index),
        "fitness": population.fitnesses[index],
        "age": population.ages[index],
        "lives": agents[index].lives if is_instance_valid(agents[index]) else 0,
        "alive": population.alive[index],
        "nodes": population.networks[index].get_node_count(),
        "connections": population.networks[index].get_connection_count(),
        "genome": population.genomes[index],
        "network": population.networks[index],
    }


func clear_inspection() -> void:
    inspected_agent_index = -1


# ============================================================
# Bless / Curse — manager-specific (use population directly)
# ============================================================

func _bless_agent(pos: Vector2) -> void:
    var idx: int = get_agent_at_position(pos)
    if idx < 0:
        return
    population.update_fitness(idx, BLESS_FITNESS)
    # Gold flash via brief invincibility
    if is_instance_valid(agents[idx]):
        agents[idx].activate_invincibility(0.5)
    _log_event("Blessed #%d (+%.0f fitness)" % [idx, BLESS_FITNESS])


func _curse_agent(pos: Vector2) -> void:
    var idx: int = get_agent_at_position(pos)
    if idx < 0:
        return
    population.update_fitness(idx, -CURSE_FITNESS)
    # Red flash via sprite modulate + timer reset
    if is_instance_valid(agents[idx]) and agents[idx].has_node("Sprite2D"):
        var sprite = agents[idx].get_node("Sprite2D")
        var original_color: Color = sprite.modulate
        sprite.modulate = Color(1.0, 0.2, 0.2, 1.0)
        agents[idx].get_tree().create_timer(0.5).timeout.connect(
            func():
                if is_instance_valid(agents[idx]):
                    agents[idx].update_sprite_color()
        )
    _log_event("Cursed #%d (-%.0f fitness)" % [idx, CURSE_FITNESS])


func _new_behavior_data() -> Dictionary:
    ## Create fresh behavior tracking data for an agent.
    return {
        "final_x": 0.0,
        "final_y": 0.0,
        "distance_traveled": 0.0,
        "enemies_killed": 0,
        "powerups_collected": 0,
        "movement_entropy": 0.0,
        "avg_center_distance": 0.0,
        "time_alive": 0.0,
        "_last_pos": Vector2.ZERO,
        "_center_dist_sum": 0.0,
        "_center_dist_count": 0,
    }


func _compute_movement_entropy(index: int) -> float:
    ## Compute directional entropy from movement angle history.
    ## Higher entropy = more varied movement directions.
    if index >= _agent_move_directions.size():
        return 0.0
    var angles: Array = _agent_move_directions[index]
    if angles.size() < 10:
        return 0.0

    # Bin angles into 8 directional buckets
    var bins: PackedFloat32Array = PackedFloat32Array()
    bins.resize(8)
    for angle in angles:
        var bucket: int = int(fposmod(angle, TAU) / (TAU / 8.0)) % 8
        bins[bucket] += 1.0

    # Normalize to probabilities
    var total: float = float(angles.size())
    var entropy: float = 0.0
    for count in bins:
        if count > 0:
            var p: float = count / total
            entropy -= p * log(p) / log(2.0)

    # Normalize: max entropy for 8 bins = 3.0 bits
    return clampf(entropy / 3.0, 0.0, 1.0)
