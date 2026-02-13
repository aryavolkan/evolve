extends RefCounted
class_name EventGenerator

## Generates deterministic random events (obstacles, enemy spawns, powerup spawns)
## for a game session based on a seed value and optional curriculum config.


static func generate(seed_value: int, p_curriculum_config: Dictionary = {}) -> Dictionary:
	## Generate random events for a deterministic game session.
	## Call once per generation, share results with all individuals.
	## p_curriculum_config: optional curriculum config to filter enemy/powerup types and scale arena.
	var gen_rng = RandomNumberGenerator.new()
	gen_rng.seed = seed_value

	var obstacles: Array = []
	var enemy_spawns: Array = []

	# Apply arena scaling from curriculum
	var arena_scale: float = p_curriculum_config.get("arena_scale", 1.0)
	var scaled_width: float = 3840.0 * arena_scale
	var scaled_height: float = 3840.0 * arena_scale
	var padding: float = 100.0
	var safe_zone: float = 300.0 * arena_scale
	var min_obstacle_dist: float = 150.0

	# Scale obstacle count with arena area
	var obstacle_count: int = int(40 * arena_scale * arena_scale)
	obstacle_count = maxi(obstacle_count, 3)

	# Generate obstacle positions
	var arena_center = Vector2(scaled_width / 2, scaled_height / 2)
	var spawned_positions: Array = []
	for i in range(obstacle_count):
		for attempt in range(50):
			var pos = Vector2(
				gen_rng.randf_range(padding, scaled_width - padding),
				gen_rng.randf_range(padding, scaled_height - padding)
			)
			if pos.distance_to(arena_center) < safe_zone:
				continue
			var too_close = false
			for existing_pos in spawned_positions:
				if pos.distance_to(existing_pos) < min_obstacle_dist:
					too_close = true
					break
			if not too_close:
				obstacles.append({"pos": pos})
				spawned_positions.append(pos)
				break

	# Determine allowed enemy types from curriculum
	var allowed_enemy_types: Array = p_curriculum_config.get("enemy_types", [0])
	if allowed_enemy_types.is_empty():
		allowed_enemy_types = [0]  # Fallback to pawns

	# Generate enemy spawn events
	var spawn_time: float = 0.0
	var spawn_interval: float = 6.0
	while spawn_time < 120.0:
		spawn_time += spawn_interval
		spawn_interval = maxf(spawn_interval * 0.95, 3.0)
		var edge = gen_rng.randi() % 4
		var pos: Vector2
		match edge:
			0: pos = Vector2(gen_rng.randf_range(padding, scaled_width - padding), padding)
			1: pos = Vector2(gen_rng.randf_range(padding, scaled_width - padding), scaled_height - padding)
			2: pos = Vector2(padding, gen_rng.randf_range(padding, scaled_height - padding))
			3: pos = Vector2(scaled_width - padding, gen_rng.randf_range(padding, scaled_height - padding))
		var enemy_type: int = allowed_enemy_types[gen_rng.randi() % allowed_enemy_types.size()]
		enemy_spawns.append({"time": spawn_time, "pos": pos, "type": enemy_type})

	# Determine allowed powerup types from curriculum
	var allowed_powerup_types: Array = p_curriculum_config.get("powerup_types", [])
	var use_all_powerups: bool = allowed_powerup_types.is_empty() and p_curriculum_config.is_empty()

	# Generate powerup spawn events
	var powerup_spawns: Array = []
	var powerup_time: float = 1.0
	var max_powerup_dist: float = minf(1000.0, scaled_width * 0.3)
	while powerup_time < 120.0:
		var angle = gen_rng.randf() * TAU
		var dist = gen_rng.randf_range(300.0 * arena_scale, max_powerup_dist)
		var pos = arena_center + Vector2(cos(angle), sin(angle)) * dist
		pos.x = clampf(pos.x, padding, scaled_width - padding)
		pos.y = clampf(pos.y, padding, scaled_height - padding)

		var powerup_type: int
		if use_all_powerups:
			powerup_type = gen_rng.randi() % 10
		elif allowed_powerup_types.is_empty():
			powerup_type = 0
		else:
			powerup_type = allowed_powerup_types[gen_rng.randi() % allowed_powerup_types.size()]
		powerup_spawns.append({"time": powerup_time, "pos": pos, "type": powerup_type})
		powerup_time += 3.0

	return {"obstacles": obstacles, "enemy_spawns": enemy_spawns, "powerup_spawns": powerup_spawns}
