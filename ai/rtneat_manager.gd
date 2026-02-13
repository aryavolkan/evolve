extends RefCounted
class_name RtNeatManager

## Orchestrates rtNEAT mode: spawns agents into a single shared arena,
## drives AI each frame, and replaces worst agents with new offspring.

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
var time_scale: float = 1.0

# Replacement log (last N events)
var replacement_log: Array = []  # [{text: String, time: float}]
const MAX_LOG_ENTRIES: int = 5

# Speed control
const SPEED_STEPS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0]

# Inspected agent
var inspected_agent_index: int = -1

# Interaction tools
enum Tool { INSPECT, PLACE_OBSTACLE, REMOVE_OBSTACLE, SPAWN_WAVE, BLESS, CURSE }
var current_tool: int = Tool.INSPECT
var player_obstacles: Array = []  # Track player-placed obstacles for cleanup

const BLESS_FITNESS: float = 2000.0
const CURSE_FITNESS: float = 2000.0
const WAVE_SIZE: int = 5
const WAVE_SPREAD: float = 200.0
const OBSTACLE_REMOVE_RADIUS: float = 80.0

# State
var _running: bool = false
var _total_time: float = 0.0


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


func start() -> void:
	## Spawn all agents into the scene.
	if not main_scene or not population:
		push_error("RtNeatManager: not set up")
		return

	_running = true
	_total_time = 0.0
	replacement_log.clear()

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
	current_tool = Tool.INSPECT

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

	# Get replacement data from population
	var result: Dictionary = population.do_replacement(index)

	# Log the replacement
	var log_entry := "Replaced #%d (fit: %.0f) → offspring of #%d × #%d" % [
		index, old_fitness, result.parent_a, result.parent_b
	]
	replacement_log.push_front({"text": log_entry, "time": _total_time})
	if replacement_log.size() > MAX_LOG_ENTRIES:
		replacement_log.pop_back()

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

	# Clear inspected if it was this agent
	if inspected_agent_index == index:
		inspected_agent_index = -1


# Signal handlers for fitness accumulation
func _on_agent_enemy_killed(pos: Vector2, points: int, agent_index: int) -> void:
	var bonus: float = points * 1000.0  # Chess value × 1000
	population.update_fitness(agent_index, bonus)


func _on_agent_died(_agent: CharacterBody2D, agent_index: int) -> void:
	population.mark_dead(agent_index)


func _on_agent_powerup(_agent: CharacterBody2D, _type: String, agent_index: int) -> void:
	population.update_fitness(agent_index, 5000.0)


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


# Speed controls
func adjust_speed(direction: float) -> void:
	var current_idx: int = SPEED_STEPS.find(time_scale)
	if current_idx == -1:
		current_idx = 2  # Default to 1.0x

	if direction > 0 and current_idx < SPEED_STEPS.size() - 1:
		current_idx += 1
	elif direction < 0 and current_idx > 0:
		current_idx -= 1

	time_scale = SPEED_STEPS[current_idx]
	Engine.time_scale = time_scale


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
# Interaction Tools
# ============================================================

func set_tool(tool: int) -> void:
	current_tool = tool
	if tool != Tool.INSPECT:
		clear_inspection()


func get_tool_name() -> String:
	match current_tool:
		Tool.INSPECT: return "INSPECT"
		Tool.PLACE_OBSTACLE: return "PLACE"
		Tool.REMOVE_OBSTACLE: return "REMOVE"
		Tool.SPAWN_WAVE: return "SPAWN"
		Tool.BLESS: return "BLESS"
		Tool.CURSE: return "CURSE"
	return "INSPECT"


func handle_click(world_pos: Vector2) -> bool:
	## Dispatch click to the active tool. Returns true if handled (non-inspect).
	match current_tool:
		Tool.INSPECT:
			return false  # Fall through to existing inspect logic
		Tool.PLACE_OBSTACLE:
			_place_obstacle(world_pos)
		Tool.REMOVE_OBSTACLE:
			_remove_obstacle(world_pos)
		Tool.SPAWN_WAVE:
			_spawn_wave(world_pos)
		Tool.BLESS:
			_bless_agent(world_pos)
		Tool.CURSE:
			_curse_agent(world_pos)
	return true


func _place_obstacle(pos: Vector2) -> void:
	var obstacle_scene: PackedScene = load("res://obstacle.tscn")
	var obstacle = obstacle_scene.instantiate()
	obstacle.position = pos
	main_scene.add_child(obstacle)
	player_obstacles.append(obstacle)
	main_scene.spawned_obstacle_positions.append(pos)
	_log_event("Placed obstacle at (%.0f, %.0f)" % [pos.x, pos.y])


func _remove_obstacle(pos: Vector2) -> void:
	var nearest_obs = null
	var nearest_dist: float = OBSTACLE_REMOVE_RADIUS
	for obs in player_obstacles:
		if not is_instance_valid(obs):
			continue
		var dist: float = obs.position.distance_to(pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_obs = obs
	if nearest_obs:
		# Remove from tracking arrays
		var obs_pos: Vector2 = nearest_obs.position
		player_obstacles.erase(nearest_obs)
		var pos_idx: int = main_scene.spawned_obstacle_positions.find(obs_pos)
		if pos_idx >= 0:
			main_scene.spawned_obstacle_positions.remove_at(pos_idx)
		nearest_obs.queue_free()
		_log_event("Removed obstacle at (%.0f, %.0f)" % [obs_pos.x, obs_pos.y])


func _spawn_wave(pos: Vector2) -> void:
	# Weighted types: 50% pawn, 25% knight, 12.5% bishop, 8.3% rook, 4.2% queen
	var weights: Array[int] = [0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3]
	for i in WAVE_SIZE:
		var angle: float = TAU * i / WAVE_SIZE
		var spawn_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * WAVE_SPREAD
		var enemy_type: int = weights[randi() % weights.size()]
		main_scene.spawn_enemy_at(spawn_pos, enemy_type)
	_log_event("Spawned wave of %d enemies at (%.0f, %.0f)" % [WAVE_SIZE, pos.x, pos.y])


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


func _log_event(text: String) -> void:
	replacement_log.push_front({"text": text, "time": _total_time})
	if replacement_log.size() > MAX_LOG_ENTRIES:
		replacement_log.pop_back()
