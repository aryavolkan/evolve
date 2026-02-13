extends RefCounted
class_name TeamManager

## Orchestrates two-team rtNEAT mode: two independent populations evolve
## in a shared arena, fighting each other with projectiles while
## environmental enemies remain as hazards.

var AISensorScript = preload("res://ai/sensor.gd")
var AIControllerScript = preload("res://ai/ai_controller.gd")
var RtNeatPopulationScript = preload("res://ai/rtneat_population.gd")
var AgentScenePacked: PackedScene = null

# Core references
var main_scene: Node2D = null
var overlay = null  # RtNeatOverlay (set externally)

# Two populations — one per team
var pop_a = null  # RtNeatPopulation (team 0)
var pop_b = null  # RtNeatPopulation (team 1)

# Per-team parallel arrays
var agents_a: Array = []
var sensors_a: Array = []
var controllers_a: Array = []
var agents_b: Array = []
var sensors_b: Array = []
var controllers_b: Array = []

# Configuration
var team_size: int = 15
var team_bonus_coeff: float = 0.2

# PvP kill tracking
var team_a_pvp_kills: int = 0
var team_b_pvp_kills: int = 0

# Replacement log
var replacement_log: Array = []
const MAX_LOG_ENTRIES: int = 5

# Speed control
const SPEED_STEPS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0, 8.0, 16.0]
var time_scale: float = 1.0

# Interaction tools (reuse same pattern as RtNeatManager)
enum Tool { INSPECT, PLACE_OBSTACLE, REMOVE_OBSTACLE, SPAWN_WAVE, BLESS, CURSE }
var current_tool: int = Tool.INSPECT
var player_obstacles: Array = []
var inspected_agent_index: int = -1

const BLESS_FITNESS: float = 2000.0
const CURSE_FITNESS: float = 2000.0
const WAVE_SIZE: int = 5
const WAVE_SPREAD: float = 200.0
const OBSTACLE_REMOVE_RADIUS: float = 80.0
const PVP_KILL_BONUS: float = 3000.0

# State
var _running: bool = false
var _total_time: float = 0.0


func setup(scene: Node2D, config: Dictionary = {}) -> void:
	main_scene = scene
	team_size = config.get("team_size", 15)

	var replacement_interval: float = config.get("replacement_interval", 15.0)
	var min_lifetime: float = config.get("min_lifetime", 10.0)

	# Create two populations with team-mode input count (119)
	pop_a = RtNeatPopulationScript.new()
	pop_b = RtNeatPopulationScript.new()

	var neat_config_a := NeatConfig.new()
	neat_config_a.input_count = AISensorScript.TEAM_TOTAL_INPUTS  # 119
	neat_config_a.output_count = 6
	neat_config_a.population_size = team_size

	var neat_config_b := NeatConfig.new()
	neat_config_b.input_count = AISensorScript.TEAM_TOTAL_INPUTS  # 119
	neat_config_b.output_count = 6
	neat_config_b.population_size = team_size

	pop_a.replacement_interval = replacement_interval
	pop_a.min_lifetime = min_lifetime
	pop_a.initialize(team_size, neat_config_a)

	pop_b.replacement_interval = replacement_interval
	pop_b.min_lifetime = min_lifetime
	pop_b.initialize(team_size, neat_config_b)


func start() -> void:
	if not main_scene or not pop_a or not pop_b:
		push_error("TeamManager: not set up")
		return

	_running = true
	_total_time = 0.0
	replacement_log.clear()
	team_a_pvp_kills = 0
	team_b_pvp_kills = 0

	if not AgentScenePacked:
		AgentScenePacked = load("res://agent.tscn")

	main_scene.training_mode = true

	var arena_center := Vector2(main_scene.effective_arena_width / 2.0, main_scene.effective_arena_height / 2.0)
	var half_width: float = main_scene.effective_arena_width * 0.25

	# Spawn team A (left half)
	for i in team_size:
		var agent = _spawn_agent(i, 0, pop_a.get_species_color(i), pop_a.networks[i],
			arena_center + Vector2(-half_width + randf() * half_width * 0.5, randf_range(-300, 300)))
		agents_a.append(agent)
		var sensor_ctrl = _create_sensor_controller(agent, 0, pop_a.networks[i])
		sensors_a.append(sensor_ctrl.sensor)
		controllers_a.append(sensor_ctrl.controller)
		_connect_agent_signals(agent, i, 0)
		agent.activate_invincibility(2.0)

	# Spawn team B (right half)
	for i in team_size:
		var agent = _spawn_agent(i, 1, pop_b.get_species_color(i), pop_b.networks[i],
			arena_center + Vector2(half_width * 0.5 + randf() * half_width * 0.5, randf_range(-300, 300)))
		agents_b.append(agent)
		var sensor_ctrl = _create_sensor_controller(agent, 1, pop_b.networks[i])
		sensors_b.append(sensor_ctrl.sensor)
		controllers_b.append(sensor_ctrl.controller)
		_connect_agent_signals(agent, i, 1)
		agent.activate_invincibility(2.0)


func _spawn_agent(agent_id: int, team_idx: int, color: Color, _network, pos: Vector2) -> CharacterBody2D:
	var agent = AgentScenePacked.instantiate()
	agent.agent_id = agent_id
	agent.team_id = team_idx
	agent.species_color = color
	agent.position = pos
	main_scene.add_child(agent)
	return agent


func _create_sensor_controller(agent: CharacterBody2D, team_idx: int, network) -> Dictionary:
	var sensor = AISensorScript.new()
	sensor.set_player(agent)
	sensor.team_mode = true
	sensor.owner_team_id = team_idx

	var controller = AIControllerScript.new()
	controller.sensor = sensor
	controller.set_network(network)

	return {"sensor": sensor, "controller": controller}


func _connect_agent_signals(agent: CharacterBody2D, idx: int, team_idx: int) -> void:
	agent.enemy_killed.connect(_on_agent_enemy_killed.bind(team_idx, idx))
	agent.died.connect(_on_agent_died.bind(team_idx, idx))
	agent.powerup_collected_by_agent.connect(_on_agent_powerup.bind(team_idx, idx))
	agent.shot_fired.connect(_on_agent_shot_fired.bind(team_idx, idx))
	agent.pvp_hit_by.connect(_on_pvp_hit.bind(team_idx, idx))


func stop() -> void:
	_running = false
	Engine.time_scale = 1.0

	for agent in agents_a + agents_b:
		if is_instance_valid(agent):
			agent.queue_free()

	for obs in player_obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	player_obstacles.clear()
	current_tool = Tool.INSPECT

	agents_a.clear()
	sensors_a.clear()
	controllers_a.clear()
	agents_b.clear()
	sensors_b.clear()
	controllers_b.clear()
	inspected_agent_index = -1

	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null


func process(delta: float) -> void:
	if not _running:
		return

	_total_time += delta

	# Drive team A agents
	for i in team_size:
		if not pop_a.alive[i]:
			continue
		if not is_instance_valid(agents_a[i]) or agents_a[i].is_dead:
			continue
		var action: Dictionary = controllers_a[i].get_action()
		agents_a[i].set_ai_action(action.move_direction, action.shoot_direction)
		pop_a.update_fitness(i, delta * 5.0)

	# Drive team B agents
	for i in team_size:
		if not pop_b.alive[i]:
			continue
		if not is_instance_valid(agents_b[i]) or agents_b[i].is_dead:
			continue
		var action: Dictionary = controllers_b[i].get_action()
		agents_b[i].set_ai_action(action.move_direction, action.shoot_direction)
		pop_b.update_fitness(i, delta * 5.0)

	# Check replacements for both teams
	var idx_a: int = pop_a.tick(delta)
	if idx_a >= 0:
		_do_replacement(pop_a, agents_a, sensors_a, controllers_a, idx_a, 0)

	var idx_b: int = pop_b.tick(delta)
	if idx_b >= 0:
		_do_replacement(pop_b, agents_b, sensors_b, controllers_b, idx_b, 1)

	# Update overlay
	if overlay and is_instance_valid(overlay):
		overlay.update_teams_display(get_stats(), replacement_log, time_scale, inspected_agent_index, current_tool)


func _do_replacement(pop, team_agents: Array, team_sensors: Array, team_controllers: Array, index: int, team_idx: int) -> void:
	var old_fitness: float = pop.fitnesses[index]

	# Apply team bonus: offspring gets team_avg * bonus_coeff head start
	var team_avg: float = 0.0
	var alive_count: int = 0
	for i in pop.pop_size:
		if pop.alive[i]:
			team_avg += pop.fitnesses[i]
			alive_count += 1
	if alive_count > 0:
		team_avg /= alive_count

	var result: Dictionary = pop.do_replacement(index)

	# Apply team bonus to new offspring
	pop.update_fitness(index, team_avg * team_bonus_coeff)

	var team_label: String = "A" if team_idx == 0 else "B"
	var log_entry := "Team %s: Replaced #%d (fit: %.0f) → offspring" % [team_label, index, old_fitness]
	replacement_log.push_front({"text": log_entry, "time": _total_time})
	if replacement_log.size() > MAX_LOG_ENTRIES:
		replacement_log.pop_back()

	# Remove old agent
	if is_instance_valid(team_agents[index]):
		team_agents[index].queue_free()

	# Spawn new agent
	var arena_center := Vector2(main_scene.effective_arena_width / 2.0, main_scene.effective_arena_height / 2.0)
	var agent = _spawn_agent(index, team_idx, result.species_color, result.network, arena_center)

	var sensor_ctrl = _create_sensor_controller(agent, team_idx, result.network)

	team_agents[index] = agent
	team_sensors[index] = sensor_ctrl.sensor
	team_controllers[index] = sensor_ctrl.controller

	_connect_agent_signals(agent, index, team_idx)
	agent.activate_invincibility(2.0)

	if inspected_agent_index == _global_index(team_idx, index):
		inspected_agent_index = -1


# ============================================================
# Signal handlers
# ============================================================

func _on_agent_enemy_killed(pos: Vector2, points: int, team_idx: int, agent_idx: int) -> void:
	var pop = pop_a if team_idx == 0 else pop_b
	pop.update_fitness(agent_idx, points * 1000.0)


func _on_agent_died(_agent: CharacterBody2D, team_idx: int, agent_idx: int) -> void:
	var pop = pop_a if team_idx == 0 else pop_b
	pop.mark_dead(agent_idx)


func _on_agent_powerup(_agent: CharacterBody2D, _type: String, team_idx: int, agent_idx: int) -> void:
	var pop = pop_a if team_idx == 0 else pop_b
	pop.update_fitness(agent_idx, 5000.0)


func _on_agent_shot_fired(direction: Vector2, team_idx: int, agent_idx: int) -> void:
	var team_agents: Array = agents_a if team_idx == 0 else agents_b
	var pop = pop_a if team_idx == 0 else pop_b
	if agent_idx < 0 or agent_idx >= team_agents.size():
		return
	var agent = team_agents[agent_idx]
	if not is_instance_valid(agent):
		return

	# Check aim toward enemies
	for child in main_scene.get_children():
		if child.is_in_group("enemy") and is_instance_valid(child):
			var to_enemy = (child.position - agent.position).normalized()
			var dot = direction.dot(to_enemy)
			var dist = agent.position.distance_to(child.position)
			if dot > 0.7 and dist < 800:
				pop.update_fitness(agent_idx, 50.0)
				return

	# Check aim toward opposing team agents
	var opponents: Array = agents_b if team_idx == 0 else agents_a
	for opp in opponents:
		if not is_instance_valid(opp) or opp.is_dead:
			continue
		var to_opp = (opp.position - agent.position).normalized()
		var dot = direction.dot(to_opp)
		var dist = agent.position.distance_to(opp.position)
		if dot > 0.7 and dist < 800:
			pop.update_fitness(agent_idx, 50.0)
			return


func _on_pvp_hit(attacker: Node, team_idx: int, _agent_idx: int) -> void:
	## Victim was hit by attacker from opposing team. Reward attacker.
	if not is_instance_valid(attacker):
		return

	# Determine attacker's team and slot
	var attacker_team: int = attacker.get("team_id") if attacker.get("team_id") != null else -1
	if attacker_team < 0:
		return

	var attacker_agents: Array = agents_a if attacker_team == 0 else agents_b
	var attacker_pop = pop_a if attacker_team == 0 else pop_b
	var attacker_idx: int = attacker_agents.find(attacker)
	if attacker_idx >= 0:
		attacker_pop.update_fitness(attacker_idx, PVP_KILL_BONUS)

	# Track PvP kills
	if attacker_team == 0:
		team_a_pvp_kills += 1
	else:
		team_b_pvp_kills += 1

	_log_event("PvP: Team %s #%d hit Team %s agent" % [
		"A" if attacker_team == 0 else "B", attacker_idx,
		"B" if team_idx == 0 else "A"
	])


# ============================================================
# Stats and inspection
# ============================================================

func get_stats() -> Dictionary:
	var stats_a: Dictionary = pop_a.get_stats() if pop_a else {}
	var stats_b: Dictionary = pop_b.get_stats() if pop_b else {}
	return {
		"team_a": stats_a,
		"team_b": stats_b,
		"team_a_pvp_kills": team_a_pvp_kills,
		"team_b_pvp_kills": team_b_pvp_kills,
		"total_agents": team_size * 2,
		"agent_count": team_size * 2,
		"alive_count": stats_a.get("alive_count", 0) + stats_b.get("alive_count", 0),
	}


func _global_index(team_idx: int, agent_idx: int) -> int:
	return agent_idx if team_idx == 0 else team_size + agent_idx


func get_agent_at_position(world_pos: Vector2) -> int:
	## Returns global index (0..team_size-1 = team A, team_size..2*team_size-1 = team B), or -1.
	var nearest_idx: int = -1
	var nearest_dist: float = 60.0
	for i in team_size:
		if is_instance_valid(agents_a[i]) and not agents_a[i].is_dead:
			var dist: float = agents_a[i].global_position.distance_to(world_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_idx = i
	for i in team_size:
		if is_instance_valid(agents_b[i]) and not agents_b[i].is_dead:
			var dist: float = agents_b[i].global_position.distance_to(world_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_idx = team_size + i
	return nearest_idx


func inspect_agent(index: int) -> Dictionary:
	if index < 0 or index >= team_size * 2:
		return {}
	inspected_agent_index = index
	var team_idx: int = 0 if index < team_size else 1
	var local_idx: int = index if team_idx == 0 else index - team_size
	var pop = pop_a if team_idx == 0 else pop_b
	var agent = agents_a[local_idx] if team_idx == 0 else agents_b[local_idx]
	var team_label: String = "A" if team_idx == 0 else "B"
	return {
		"agent_id": local_idx,
		"team": team_label,
		"species_id": pop.species_ids[local_idx],
		"species_color": pop.get_species_color(local_idx),
		"fitness": pop.fitnesses[local_idx],
		"age": pop.ages[local_idx],
		"lives": agent.lives if is_instance_valid(agent) else 0,
		"alive": pop.alive[local_idx],
		"nodes": pop.networks[local_idx].get_node_count(),
		"connections": pop.networks[local_idx].get_connection_count(),
		"genome": pop.genomes[local_idx],
		"network": pop.networks[local_idx],
	}


func clear_inspection() -> void:
	inspected_agent_index = -1


# ============================================================
# Speed control
# ============================================================

func adjust_speed(direction: float) -> void:
	var current_idx: int = SPEED_STEPS.find(time_scale)
	if current_idx == -1:
		current_idx = 2
	if direction > 0 and current_idx < SPEED_STEPS.size() - 1:
		current_idx += 1
	elif direction < 0 and current_idx > 0:
		current_idx -= 1
	time_scale = SPEED_STEPS[current_idx]
	Engine.time_scale = time_scale


# ============================================================
# Interaction tools
# ============================================================

func set_tool(tool: int) -> void:
	current_tool = tool
	if tool != Tool.INSPECT:
		clear_inspection()


func handle_click(world_pos: Vector2) -> bool:
	match current_tool:
		Tool.INSPECT:
			return false
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
		var obs_pos: Vector2 = nearest_obs.position
		player_obstacles.erase(nearest_obs)
		var pos_idx: int = main_scene.spawned_obstacle_positions.find(obs_pos)
		if pos_idx >= 0:
			main_scene.spawned_obstacle_positions.remove_at(pos_idx)
		nearest_obs.queue_free()
		_log_event("Removed obstacle at (%.0f, %.0f)" % [obs_pos.x, obs_pos.y])


func _spawn_wave(pos: Vector2) -> void:
	var weights: Array[int] = [0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3]
	for i in WAVE_SIZE:
		var angle: float = TAU * i / WAVE_SIZE
		var spawn_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * WAVE_SPREAD
		var enemy_type: int = weights[randi() % weights.size()]
		main_scene.spawn_enemy_at(spawn_pos, enemy_type)
	_log_event("Spawned wave of %d enemies" % WAVE_SIZE)


func _bless_agent(pos: Vector2) -> void:
	var idx: int = get_agent_at_position(pos)
	if idx < 0:
		return
	var team_idx: int = 0 if idx < team_size else 1
	var local_idx: int = idx if team_idx == 0 else idx - team_size
	var pop = pop_a if team_idx == 0 else pop_b
	pop.update_fitness(local_idx, BLESS_FITNESS)
	var agent = agents_a[local_idx] if team_idx == 0 else agents_b[local_idx]
	if is_instance_valid(agent):
		agent.activate_invincibility(0.5)
	_log_event("Blessed Team %s #%d" % ["A" if team_idx == 0 else "B", local_idx])


func _curse_agent(pos: Vector2) -> void:
	var idx: int = get_agent_at_position(pos)
	if idx < 0:
		return
	var team_idx: int = 0 if idx < team_size else 1
	var local_idx: int = idx if team_idx == 0 else idx - team_size
	var pop = pop_a if team_idx == 0 else pop_b
	pop.update_fitness(local_idx, -CURSE_FITNESS)
	var agent = agents_a[local_idx] if team_idx == 0 else agents_b[local_idx]
	if is_instance_valid(agent) and agent.has_node("Sprite2D"):
		var sprite = agent.get_node("Sprite2D")
		sprite.modulate = Color(1.0, 0.2, 0.2, 1.0)
		agent.get_tree().create_timer(0.5).timeout.connect(
			func():
				if is_instance_valid(agent):
					agent.update_sprite_color()
		)
	_log_event("Cursed Team %s #%d" % ["A" if team_idx == 0 else "B", local_idx])


func _log_event(text: String) -> void:
	replacement_log.push_front({"text": text, "time": _total_time})
	if replacement_log.size() > MAX_LOG_ENTRIES:
		replacement_log.pop_back()
