extends Node2D

var score: float = 0.0
var lives: int = 3
var game_over: bool = false
var kills: int = 0
var powerups_collected: int = 0
var score_from_kills: float = 0.0
var score_from_powerups: float = 0.0
var entering_name: bool = false
var next_spawn_score: float = 50.0
var next_powerup_score: float = 30.0
var enemy_scene: PackedScene = preload("res://enemy.tscn")
var powerup_scene: PackedScene = preload("res://powerup.tscn")
var obstacle_scene: PackedScene = preload("res://obstacle.tscn")
var floating_text_scene: PackedScene = preload("res://floating_text.tscn")
var high_scores: Array = []
var spawned_obstacle_positions: Array = []

# AI Training
var training_manager: Node
var ai_status_label: Label

# Bonus points - kills/powerups dominate, survival is minor
const POWERUP_COLLECT_BONUS: int = 5000    # Massive incentive to collect powerups
const SCREEN_CLEAR_BONUS: int = 8000       # Huge reward for screen clear
const KILL_MULTIPLIER: int = 1000          # Chess values (1-9 -> 1000-9000)
const SURVIVAL_MILESTONE_BONUS: int = 100  # Small milestone bonus
const SHOOT_TOWARD_ENEMY_BONUS: int = 50   # Reward for shooting toward enemies
const SHOOT_HIT_BONUS: int = 200           # Bonus when projectile is near enemy

# Chess piece types for spawning
enum ChessPiece { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

const POWERUP_DURATION: float = 5.0
const SLOW_MULTIPLIER: float = 0.5
const RESPAWN_INVINCIBILITY: float = 2.0

const MAX_HIGH_SCORES: int = 5
const SAVE_PATH: String = "user://highscores.save"

# Arena configuration - large square arena
const ARENA_WIDTH: float = 3840.0   # 3x viewport width
const ARENA_HEIGHT: float = 3840.0  # Square arena
const ARENA_WALL_THICKNESS: float = 40.0
const ARENA_PADDING: float = 100.0  # Safe zone from walls for spawning

# Permanent obstacle configuration
const OBSTACLE_COUNT: int = 40      # More obstacles for larger arena
const OBSTACLE_MIN_DISTANCE: float = 150.0  # Min distance between obstacles
const OBSTACLE_PLAYER_SAFE_ZONE: float = 300.0  # Keep obstacles away from player spawn

# Power-up limit
const MAX_POWERUPS: int = 15  # Maximum power-ups on the map at once

# Difficulty scaling
const BASE_ENEMY_SPEED: float = 150.0
const MAX_ENEMY_SPEED: float = 300.0
const BASE_SPAWN_INTERVAL: float = 50.0
const MIN_SPAWN_INTERVAL: float = 20.0
const DIFFICULTY_SCALE_SCORE: float = 500.0  # Score at which difficulty is maxed

# Slow/Freeze enemies tracking
var slow_active: bool = false
var freeze_active: bool = false

# Double points tracking
var double_points_active: bool = false

# Screen clear spawn cooldown
var screen_clear_cooldown: float = 0.0
const SCREEN_CLEAR_SPAWN_DELAY: float = 2.0  # No enemy spawns for 2 seconds after clear

# Survival milestone tracking
var survival_time: float = 0.0
var last_milestone: int = 0
const MILESTONE_INTERVAL: float = 15.0  # Bonus every 15 seconds

# Arena camera
var arena_camera: Camera2D

@onready var score_label: Label = $CanvasLayer/UI/ScoreLabel
@onready var lives_label: Label = $CanvasLayer/UI/LivesLabel
@onready var game_over_label: Label = $CanvasLayer/UI/GameOverLabel
@onready var powerup_label: Label = $CanvasLayer/UI/PowerUpLabel
@onready var scoreboard_label: Label = $CanvasLayer/UI/ScoreboardLabel
@onready var name_entry: LineEdit = $CanvasLayer/UI/NameEntry
@onready var name_prompt: Label = $CanvasLayer/UI/NamePrompt
@onready var player: CharacterBody2D = $Player

var game_seed: int = 0  # Seed for deterministic training
var training_mode: bool = false  # Simplified game for AI training
var rng: RandomNumberGenerator  # Per-arena RNG for deterministic replay

# Curriculum config applied to this instance
var curriculum_config: Dictionary = {}  # From training_manager curriculum stages
var effective_arena_width: float = ARENA_WIDTH
var effective_arena_height: float = ARENA_HEIGHT

# Pre-generated events for deterministic training
var preset_obstacles: Array = []  # [{pos: Vector2}, ...]
var preset_enemy_spawns: Array = []  # [{time: float, pos: Vector2, type: int}, ...]
var use_preset_events: bool = false

func set_game_seed(s: int) -> void:
	## Set random seed for deterministic game (used in training).
	game_seed = s
	rng = RandomNumberGenerator.new()
	rng.seed = s

func set_training_mode(enabled: bool, p_curriculum_config: Dictionary = {}) -> void:
	## Enable simplified game mode for AI training.
	## p_curriculum_config: curriculum stage config with arena_scale, enemy_types, powerup_types
	training_mode = enabled
	curriculum_config = p_curriculum_config
	if not curriculum_config.is_empty():
		var scale: float = curriculum_config.get("arena_scale", 1.0)
		effective_arena_width = ARENA_WIDTH * scale
		effective_arena_height = ARENA_HEIGHT * scale
	else:
		effective_arena_width = ARENA_WIDTH
		effective_arena_height = ARENA_HEIGHT

var preset_powerup_spawns: Array = []  # [{time: float, pos: Vector2, type: int}, ...]

# Co-evolution: if set, all spawned enemies use this neural network for AI control
var enemy_ai_network = null

func set_preset_events(obstacles: Array, enemy_spawns: Array, powerup_spawns: Array = []) -> void:
	## Use pre-generated events for deterministic gameplay.
	preset_obstacles = obstacles
	preset_enemy_spawns = enemy_spawns.duplicate()  # Copy so we can pop from it
	preset_powerup_spawns = powerup_spawns.duplicate()
	use_preset_events = true

static func generate_random_events(seed_value: int, p_curriculum_config: Dictionary = {}) -> Dictionary:
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

	# Generate enemy spawn events - very slow initially for learning
	var spawn_time: float = 0.0
	var spawn_interval: float = 6.0  # Very slow spawning to give AI time
	while spawn_time < 120.0:
		spawn_time += spawn_interval
		spawn_interval = maxf(spawn_interval * 0.95, 3.0)  # Cap at 3s minimum
		# Random edge position (scaled to arena)
		var edge = gen_rng.randi() % 4
		var pos: Vector2
		match edge:
			0: pos = Vector2(gen_rng.randf_range(padding, scaled_width - padding), padding)
			1: pos = Vector2(gen_rng.randf_range(padding, scaled_width - padding), scaled_height - padding)
			2: pos = Vector2(padding, gen_rng.randf_range(padding, scaled_height - padding))
			3: pos = Vector2(scaled_width - padding, gen_rng.randf_range(padding, scaled_height - padding))
		# Pick random enemy type from allowed types
		var enemy_type: int = allowed_enemy_types[gen_rng.randi() % allowed_enemy_types.size()]
		enemy_spawns.append({"time": spawn_time, "pos": pos, "type": enemy_type})

	# Determine allowed powerup types from curriculum
	var allowed_powerup_types: Array = p_curriculum_config.get("powerup_types", [])
	var use_all_powerups: bool = allowed_powerup_types.is_empty() and p_curriculum_config.is_empty()

	# Generate powerup spawn events - CLOSE to player spawn for easier collection
	var powerup_spawns: Array = []
	var powerup_time: float = 1.0  # First powerup at 1 second
	var max_powerup_dist: float = minf(1000.0, scaled_width * 0.3)
	while powerup_time < 120.0:
		# Spawn powerups within reachable distance of center (player spawn)
		var angle = gen_rng.randf() * TAU
		var dist = gen_rng.randf_range(300.0 * arena_scale, max_powerup_dist)
		var pos = arena_center + Vector2(cos(angle), sin(angle)) * dist
		# Clamp to arena bounds
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

func _ready() -> void:
	if not rng:
		# Human mode: create unseeded RNG (random each run)
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if DisplayServer.get_name() != "headless":
		print("Evolve app started!")
	get_tree().paused = false
	player.hit.connect(_on_player_hit)
	player.enemy_killed.connect(_on_enemy_killed)
	player.powerup_timer_updated.connect(_on_powerup_timer_updated)
	player.shot_fired.connect(_on_shot_fired)
	game_over_label.visible = false
	powerup_label.visible = false
	name_entry.visible = false
	name_prompt.visible = false
	load_high_scores()
	update_lives_display()
	update_scoreboard_display()
	setup_arena()
	spawn_arena_obstacles()
	spawn_initial_enemies()
	setup_training_manager()

	# Check for auto-train flag (for headless W&B sweeps)
	for arg in OS.get_cmdline_user_args():
		if arg == "--auto-train":
			call_deferred("_start_auto_training")
			return


func _start_auto_training() -> void:
	## Start training automatically (for headless sweep runs)
	if training_manager:
		print("Auto-training started via command line")
		training_manager.start_training()


func _process(delta: float) -> void:
	# Handle AI training controls (always check these)
	handle_training_input()

	if game_over:
		if entering_name:
			if Input.is_action_just_pressed("ui_accept") and name_entry.text.strip_edges() != "":
				submit_high_score(name_entry.text.strip_edges())
		else:
			if Input.is_action_just_pressed("ui_accept"):
				get_tree().reload_current_scene()
		return

	var score_multiplier = 2.0 if double_points_active else 1.0
	score += delta * 5 * score_multiplier  # Reduced base survival (5 pts/sec)
	score_label.text = "Score: %d" % int(score)
	update_ai_status_display()

	# Track survival time and award milestone bonuses
	survival_time += delta
	var current_milestone = int(survival_time / MILESTONE_INTERVAL)
	if current_milestone > last_milestone:
		var bonus = SURVIVAL_MILESTONE_BONUS * current_milestone
		score += bonus
		last_milestone = current_milestone

	# Proximity rewards - guide AI toward powerups (continuous shaping)
	var proximity_bonus = calculate_proximity_bonus(delta)
	if proximity_bonus > 0:
		score += proximity_bonus
		score_from_powerups += proximity_bonus  # Count as powerup-related

	# Update screen clear cooldown
	if screen_clear_cooldown > 0:
		screen_clear_cooldown -= delta

	# Enemy spawning
	if use_preset_events:
		# Spawn from preset list based on elapsed time (use survival_time for accuracy)
		while preset_enemy_spawns.size() > 0 and preset_enemy_spawns[0].time <= survival_time:
			var spawn_data = preset_enemy_spawns.pop_front()
			spawn_enemy_at(spawn_data.pos, spawn_data.type)
	elif score >= next_spawn_score and screen_clear_cooldown <= 0:
		spawn_enemy()
		var spawn_interval = get_scaled_spawn_interval()
		next_spawn_score += spawn_interval

	# Powerup spawning
	if use_preset_events:
		# Spawn from preset list based on elapsed time
		while preset_powerup_spawns.size() > 0 and preset_powerup_spawns[0].time <= survival_time:
			var spawn_data = preset_powerup_spawns.pop_front()
			spawn_powerup_at(spawn_data.pos, spawn_data.type)
	elif score >= next_powerup_score:
		var powerup_count = count_local_powerups()

		if powerup_count >= MAX_POWERUPS:
			next_powerup_score = score + 80.0
		elif spawn_powerup():
			next_powerup_score += 80.0
		else:
			next_powerup_score = score + 20.0

func get_difficulty_factor() -> float:
	return clampf(score / DIFFICULTY_SCALE_SCORE, 0.0, 1.0)


func calculate_proximity_bonus(delta: float) -> float:
	## Reward AI for being close to powerups (continuous shaping signal).
	## Returns bonus points to add this frame.
	var bonus := 0.0
	var powerups = get_tree().get_nodes_in_group("powerup")
	var nearest_dist := 99999.0

	for powerup in powerups:
		if not is_instance_valid(powerup) or powerup.get_parent() != self:
			continue
		var dist = player.position.distance_to(powerup.position)
		nearest_dist = minf(nearest_dist, dist)

	# Reward based on distance to NEAREST powerup (range 1500 for large arena)
	if nearest_dist < 1500:
		# Closer = more bonus (100 pts/sec at distance 0, scaling down)
		var proximity_factor = 1.0 - (nearest_dist / 1500.0)
		bonus = 100.0 * proximity_factor * delta

	return bonus

func get_scaled_enemy_speed() -> float:
	var factor = get_difficulty_factor()
	return lerpf(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, factor)

func get_scaled_spawn_interval() -> float:
	var factor = get_difficulty_factor()
	return lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, factor)

func spawn_enemy() -> void:
	var enemy = enemy_scene.instantiate()
	enemy.speed = get_scaled_enemy_speed()

	if training_mode and not curriculum_config.is_empty():
		# Use curriculum-allowed enemy types
		var allowed: Array = curriculum_config.get("enemy_types", [0])
		enemy.type = allowed[rng.randi() % allowed.size()]
	elif training_mode:
		# Simplified: only pawns in training mode (no curriculum)
		enemy.type = ChessPiece.PAWN
	else:
		# Chess piece type (weighted: pawns common, higher pieces rarer)
		var type_roll = rng.randf()
		var difficulty = get_difficulty_factor()

		if type_roll < 0.5 - difficulty * 0.3:
			enemy.type = ChessPiece.PAWN
		elif type_roll < 0.7 - difficulty * 0.1:
			enemy.type = ChessPiece.KNIGHT
		elif type_roll < 0.85:
			enemy.type = ChessPiece.BISHOP
		elif type_roll < 0.95:
			enemy.type = ChessPiece.ROOK
		else:
			enemy.type = ChessPiece.QUEEN

	# Spawn at random position along arena edges
	var pos = get_random_edge_spawn_position()
	enemy.position = pos
	enemy.rng = rng
	add_child(enemy)

	# Wire AI if co-evolution is active
	if enemy_ai_network:
		enemy.setup_ai(enemy_ai_network)

	# Apply slow/freeze after adding to tree (so apply_type_config has run)
	if freeze_active:
		enemy.apply_freeze()
	elif slow_active:
		enemy.apply_slow(SLOW_MULTIPLIER)


func spawn_enemy_at(pos: Vector2, enemy_type: int) -> void:
	## Spawn enemy at specific position with specific type (for preset events).
	var enemy = enemy_scene.instantiate()
	# Much slower enemies in training mode for easier learning
	enemy.speed = get_scaled_enemy_speed() * (0.5 if training_mode else 1.0)
	enemy.type = enemy_type  # 0=pawn, 1=knight, etc.
	enemy.position = pos
	enemy.rng = rng
	add_child(enemy)

	# Wire AI if co-evolution is active
	if enemy_ai_network:
		enemy.setup_ai(enemy_ai_network)

	if freeze_active:
		enemy.apply_freeze()
	elif slow_active:
		enemy.apply_slow(SLOW_MULTIPLIER)


func spawn_powerup_at(pos: Vector2, powerup_type: int) -> void:
	## Spawn powerup at specific position with specific type (for preset events).
	if count_local_powerups() >= MAX_POWERUPS:
		return  # Don't exceed max powerups
	var powerup = powerup_scene.instantiate()
	powerup.position = pos
	powerup.set_type(powerup_type)
	powerup.collected.connect(_on_powerup_collected)
	add_child(powerup)


func spawn_initial_enemies() -> void:
	## Spawn initial enemies at the arena edges
	var enemy_count = 3 if training_mode else 10  # Fewer enemies in training
	for i in range(enemy_count):
		var enemy = enemy_scene.instantiate()
		enemy.speed = BASE_ENEMY_SPEED * (0.5 if training_mode else 1.0)  # Slower in training
		enemy.type = ChessPiece.PAWN  # Start with pawns
		enemy.position = get_random_edge_spawn_position()
		enemy.rng = rng
		add_child(enemy)
		# Wire AI if co-evolution is active
		if enemy_ai_network:
			enemy.setup_ai(enemy_ai_network)


func count_local_powerups() -> int:
	## Count powerups that are children of this scene (not global).
	## This is needed for parallel training where multiple scenes share the tree.
	var count = 0
	for p in get_tree().get_nodes_in_group("powerup"):
		if is_instance_valid(p) and not p.is_queued_for_deletion() and p.get_parent() == self:
			count += 1
	return count


func spawn_powerup() -> bool:
	## Returns true if a power-up was successfully spawned
	# Check if we've reached the maximum number of power-ups (local only)
	if count_local_powerups() >= MAX_POWERUPS:
		return false  # Don't spawn more power-ups

	var powerup = powerup_scene.instantiate()

	# Find a valid position not overlapping obstacles
	var pos = find_valid_powerup_position()
	if pos == Vector2.ZERO:
		powerup.queue_free()
		return false  # Couldn't find valid position

	powerup.position = pos

	# Random powerup type (10 types: 0-9)
	var type_index = rng.randi() % 10
	powerup.set_type(type_index)
	powerup.collected.connect(_on_powerup_collected)
	add_child(powerup)
	return true

func find_valid_powerup_position() -> Vector2:
	const POWERUP_OBSTACLE_MIN_DIST: float = 80.0  # Obstacle size + buffer
	const POWERUP_PLAYER_MIN_DIST: float = 150.0   # Not too close to player

	for attempt in range(20):
		# Random position within arena bounds
		var pos = Vector2(
			rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING),
			rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING)
		)

		# Check distance from player (not too close, not too far)
		var player_dist = pos.distance_to(player.position)
		if player_dist < POWERUP_PLAYER_MIN_DIST:
			continue

		# Check distance from all obstacles
		var valid = true
		for obstacle_pos in spawned_obstacle_positions:
			if pos.distance_to(obstacle_pos) < POWERUP_OBSTACLE_MIN_DIST:
				valid = false
				break

		if valid:
			return pos

	return Vector2.ZERO  # Failed to find valid position

func _on_powerup_collected(type: String) -> void:
	powerups_collected += 1
	show_powerup_message(type)

	# Bonus for collecting powerup
	var multiplier = 2 if double_points_active else 1
	var bonus = POWERUP_COLLECT_BONUS * multiplier
	score += bonus
	score_from_powerups += bonus
	var bonus_text = "+%d" % bonus
	spawn_floating_text(bonus_text, Color(0, 1, 0.5, 1), player.position)

	match type:
		"SPEED BOOST":
			player.activate_speed_boost(POWERUP_DURATION)
		"INVINCIBILITY":
			player.activate_invincibility(POWERUP_DURATION)
		"SLOW ENEMIES":
			activate_slow_enemies()
		"SCREEN CLEAR":
			clear_all_enemies()
		"RAPID FIRE":
			player.activate_rapid_fire(POWERUP_DURATION)
		"PIERCING":
			player.activate_piercing(POWERUP_DURATION)
		"SHIELD":
			player.activate_shield()
		"FREEZE":
			activate_freeze_enemies()
		"DOUBLE POINTS":
			activate_double_points()
		"BOMB":
			explode_nearby_enemies()

func _on_enemy_killed(pos: Vector2, points: int = 1) -> void:
	kills += 1
	var multiplier = 2 if double_points_active else 1
	var bonus = points * KILL_MULTIPLIER * multiplier
	score += bonus
	score_from_kills += bonus
	var bonus_text = "+%d" % bonus
	spawn_floating_text(bonus_text, Color(1, 1, 0, 1), pos)

func spawn_floating_text(text: String, color: Color, pos: Vector2) -> void:
	var floating = floating_text_scene.instantiate()
	add_child(floating)
	floating.setup(text, color, pos)

func show_powerup_message(type: String) -> void:
	powerup_label.text = type + "!"
	powerup_label.visible = true
	await get_tree().create_timer(2.0).timeout
	powerup_label.visible = false

func _on_powerup_timer_updated(powerup_type: String, time_left: float) -> void:
	# Handle slow enemies ending
	if powerup_type == "SLOW" and time_left <= 0:
		end_slow_enemies()
	# Handle freeze enemies ending
	if powerup_type == "FREEZE" and time_left <= 0:
		end_freeze_enemies()
	# Handle double points ending
	if powerup_type == "DOUBLE" and time_left <= 0:
		end_double_points()


func _on_shot_fired(direction: Vector2) -> void:
	## Reward shooting toward enemies (training shaping)
	if not training_mode:
		return

	var dominated_enemies = get_local_enemies()
	for enemy in dominated_enemies:
		if not is_instance_valid(enemy):
			continue
		var to_enemy = (enemy.position - player.position).normalized()
		var dot = direction.dot(to_enemy)
		var dist = player.position.distance_to(enemy.position)

		# Reward if shooting toward a nearby enemy (within 45 degrees and 800 units)
		if dot > 0.7 and dist < 800:
			var bonus = SHOOT_TOWARD_ENEMY_BONUS
			score += bonus
			score_from_kills += bonus  # Count as kill-related
			return  # Only reward once per shot


func activate_slow_enemies() -> void:
	# Apply slow to all current enemies if not already active
	if not slow_active:
		for enemy in get_local_enemies():
			enemy.apply_slow(SLOW_MULTIPLIER)
	slow_active = true
	player.activate_slow_effect(POWERUP_DURATION)

func get_local_enemies() -> Array:
	## Get enemies that belong to this scene (not other parallel training scenes).
	var local_enemies = []
	for child in get_children():
		if child.is_in_group("enemy"):
			local_enemies.append(child)
	return local_enemies


func end_slow_enemies() -> void:
	if slow_active:
		slow_active = false
		for enemy in get_local_enemies():
			enemy.remove_slow(SLOW_MULTIPLIER)


func activate_freeze_enemies() -> void:
	# Freeze completely stops enemies (unlike slow which is 50%)
	if not freeze_active:
		for enemy in get_local_enemies():
			enemy.apply_freeze()
	freeze_active = true
	player.activate_freeze_effect(POWERUP_DURATION)


func end_freeze_enemies() -> void:
	if freeze_active:
		freeze_active = false
		for enemy in get_local_enemies():
			enemy.remove_freeze()


func activate_double_points() -> void:
	double_points_active = true
	player.activate_double_points(POWERUP_DURATION)


func end_double_points() -> void:
	double_points_active = false


func clear_all_enemies() -> void:
	player.trigger_screen_clear_effect()
	var local_enemies = get_local_enemies()
	var total_points = 0
	for enemy in local_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			if enemy.has_method("get_point_value"):
				total_points += enemy.get_point_value() * KILL_MULTIPLIER
			else:
				total_points += KILL_MULTIPLIER
			enemy.queue_free()

	# Bonus points for screen clear (scaled piece values + flat bonus)
	if total_points > 0:
		total_points += SCREEN_CLEAR_BONUS
		score += total_points
		spawn_floating_text("+%d CLEAR!" % total_points, Color(1, 0.3, 0.3, 1), player.position + Vector2(0, -50))

	# Prevent immediate respawning - set cooldown and advance spawn threshold
	screen_clear_cooldown = SCREEN_CLEAR_SPAWN_DELAY
	next_spawn_score = score + get_scaled_spawn_interval()


const BOMB_RADIUS: float = 600.0  # Radius of bomb explosion

func explode_nearby_enemies() -> void:
	## Kill all enemies within BOMB_RADIUS of the player
	var local_enemies = get_local_enemies()
	var total_points = 0
	var killed_count = 0

	for enemy in local_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			var distance = player.position.distance_to(enemy.position)
			if distance <= BOMB_RADIUS:
				if enemy.has_method("get_point_value"):
					total_points += enemy.get_point_value() * KILL_MULTIPLIER
				else:
					total_points += KILL_MULTIPLIER
				killed_count += 1
				enemy.queue_free()

	# Award points and show feedback
	if total_points > 0:
		var multiplier = 2 if double_points_active else 1
		total_points *= multiplier
		score += total_points
		score_from_kills += total_points
		spawn_floating_text("+%d BOMB!" % total_points, Color(1, 0.5, 0, 1), player.position + Vector2(0, -50))


func update_lives_display() -> void:
	lives_label.text = "Lives: %d" % lives

func _on_player_hit() -> void:
	lives -= 1
	update_lives_display()

	# Show life lost indicator
	spawn_floating_text("-1 LIFE", Color(1, 0.2, 0.2, 1), player.position + Vector2(0, -30))

	if lives <= 0:
		game_over = true
		get_tree().paused = true

		if is_high_score(int(score)):
			entering_name = true
			game_over_label.text = "NEW HIGH SCORE!\nScore: %d" % int(score)
			game_over_label.visible = true
			name_prompt.visible = true
			name_entry.visible = true
			name_entry.text = ""
			name_entry.grab_focus()
		else:
			game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
			game_over_label.visible = true
	else:
		# Respawn player at arena center with brief invincibility
		var arena_center = Vector2(effective_arena_width / 2, effective_arena_height / 2)
		player.respawn(arena_center, RESPAWN_INVINCIBILITY)

# High score functions
func load_high_scores() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data = file.get_var()
		if data is Array:
			high_scores = data
		file.close()

func save_high_scores() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_var(high_scores)
	file.close()

func is_high_score(new_score: int) -> bool:
	if high_scores.size() < MAX_HIGH_SCORES:
		return true
	return new_score > high_scores[-1]["score"]

func submit_high_score(player_name: String) -> void:
	var entry = { "name": player_name.substr(0, 10), "score": int(score) }
	high_scores.append(entry)
	high_scores.sort_custom(func(a, b): return a["score"] > b["score"])
	if high_scores.size() > MAX_HIGH_SCORES:
		high_scores.resize(MAX_HIGH_SCORES)
	save_high_scores()

	entering_name = false
	name_entry.visible = false
	name_prompt.visible = false
	game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
	update_scoreboard_display()

func update_scoreboard_display() -> void:
	var text = "HIGH SCORES\n"
	for i in range(high_scores.size()):
		text += "%d. %s - %d\n" % [i + 1, high_scores[i]["name"], high_scores[i]["score"]]
	for i in range(high_scores.size(), MAX_HIGH_SCORES):
		text += "%d. ---\n" % [i + 1]
	scoreboard_label.text = text

# Arena setup functions
func setup_arena() -> void:
	## Create the arena with walls and a static camera
	var arena_center = Vector2(effective_arena_width / 2, effective_arena_height / 2)

	# Disable player's camera (we use arena camera instead)
	var player_camera = player.get_node_or_null("Camera2D")
	if player_camera:
		player_camera.enabled = false

	# Position player at arena center
	player.position = arena_center

	# Create arena walls (visual boundary)
	create_arena_walls()

	# Draw arena floor (visual background with grid)
	create_arena_floor()

	# Create static camera centered on arena
	arena_camera = Camera2D.new()
	arena_camera.position = arena_center
	add_child(arena_camera)
	arena_camera.make_current()

	# Update camera zoom to fit current viewport
	update_camera_zoom()

	# Connect to viewport size changes
	get_tree().root.size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	## Called when the window is resized
	update_camera_zoom()


func update_camera_zoom() -> void:
	## Update camera zoom to fit arena in current viewport
	if not arena_camera:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var zoom_x = viewport_size.x / effective_arena_width
	var zoom_y = viewport_size.y / effective_arena_height
	var zoom_level = min(zoom_x, zoom_y)  # Use smaller to fit both dimensions
	arena_camera.zoom = Vector2(zoom_level, zoom_level)


func create_arena_walls() -> void:
	## Create visible border walls inside the arena boundary
	var wall_thickness = ARENA_WALL_THICKNESS
	var wall_positions = [
		# Top wall - inside the arena, at y = wall_thickness/2
		{"pos": Vector2(effective_arena_width / 2, wall_thickness / 2),
		 "size": Vector2(effective_arena_width, wall_thickness)},
		# Bottom wall - inside the arena
		{"pos": Vector2(effective_arena_width / 2, effective_arena_height - wall_thickness / 2),
		 "size": Vector2(effective_arena_width, wall_thickness)},
		# Left wall - inside the arena
		{"pos": Vector2(wall_thickness / 2, effective_arena_height / 2),
		 "size": Vector2(wall_thickness, effective_arena_height - wall_thickness * 2)},
		# Right wall - inside the arena
		{"pos": Vector2(effective_arena_width - wall_thickness / 2, effective_arena_height / 2),
		 "size": Vector2(wall_thickness, effective_arena_height - wall_thickness * 2)}
	]

	for wall_data in wall_positions:
		var wall = StaticBody2D.new()
		wall.position = wall_data.pos
		wall.collision_layer = 4  # Same as obstacles
		wall.collision_mask = 0

		# Collision shape - centered at wall position
		var collision = CollisionShape2D.new()
		collision.position = Vector2.ZERO  # Explicitly centered
		var shape = RectangleShape2D.new()
		shape.size = wall_data.size
		collision.shape = shape
		wall.add_child(collision)

		# Visual representation - must match collision exactly
		# ColorRect uses top-left positioning, so offset by half size to center
		var rect = ColorRect.new()
		rect.size = wall_data.size
		rect.position = -wall_data.size / 2  # Center the rect on the wall position
		rect.color = Color(0.25, 0.3, 0.45, 1)  # Blue-gray
		rect.z_index = 5  # Above floor
		wall.add_child(rect)

		# Inner highlight for visibility
		var inner_size = wall_data.size - Vector2(6, 6)
		if inner_size.x > 0 and inner_size.y > 0:
			var highlight = ColorRect.new()
			highlight.size = inner_size
			highlight.position = -inner_size / 2  # Also centered
			highlight.color = Color(0.35, 0.4, 0.55, 1)  # Brighter inner
			highlight.z_index = 6
			wall.add_child(highlight)

		wall.add_to_group("wall")
		add_child(wall)


func create_arena_floor() -> void:
	## Draw the arena floor as a visual background
	var floor_rect = ColorRect.new()
	floor_rect.position = Vector2(0, 0)
	floor_rect.size = Vector2(effective_arena_width, effective_arena_height)
	floor_rect.color = Color(0.08, 0.08, 0.12, 1)  # Very dark blue
	floor_rect.z_index = -10
	add_child(floor_rect)

	# Add grid lines for visual reference
	var grid_size = 160.0  # Larger grid for bigger arena
	for x in range(int(effective_arena_width / grid_size) + 1):
		var line = ColorRect.new()
		line.position = Vector2(x * grid_size - 1, 0)
		line.size = Vector2(2, effective_arena_height)
		line.color = Color(0.12, 0.12, 0.18, 0.5)
		line.z_index = -9
		add_child(line)

	for y in range(int(effective_arena_height / grid_size) + 1):
		var line = ColorRect.new()
		line.position = Vector2(0, y * grid_size - 1)
		line.size = Vector2(effective_arena_width, 2)
		line.color = Color(0.12, 0.12, 0.18, 0.5)
		line.z_index = -9
		add_child(line)


func spawn_arena_obstacles() -> void:
	## Spawn permanent obstacles throughout the arena
	spawned_obstacle_positions.clear()

	# Use preset positions if available (for deterministic training)
	if use_preset_events and preset_obstacles.size() > 0:
		for obstacle_data in preset_obstacles:
			var obstacle = obstacle_scene.instantiate()
			obstacle.position = obstacle_data.pos
			add_child(obstacle)
			spawned_obstacle_positions.append(obstacle_data.pos)
		return

	# Generate random positions
	var arena_center = Vector2(effective_arena_width / 2, effective_arena_height / 2)
	for i in range(OBSTACLE_COUNT):
		var placed = false
		for attempt in range(50):
			var pos = Vector2(
				rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING),
				rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING)
			)

			if pos.distance_to(arena_center) < OBSTACLE_PLAYER_SAFE_ZONE:
				continue

			var too_close = false
			for existing_pos in spawned_obstacle_positions:
				if pos.distance_to(existing_pos) < OBSTACLE_MIN_DISTANCE:
					too_close = true
					break

			if not too_close:
				var obstacle = obstacle_scene.instantiate()
				obstacle.position = pos
				add_child(obstacle)
				spawned_obstacle_positions.append(pos)
				placed = true
				break

		if not placed:
			print("Warning: Could not place obstacle %d" % i)


func get_random_edge_spawn_position() -> Vector2:
	## Get a random position along the arena edges for enemy spawning
	var edge = rng.randi() % 4
	var pos: Vector2

	match edge:
		0:  # Top edge
			pos = Vector2(rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING), ARENA_PADDING)
		1:  # Bottom edge
			pos = Vector2(rng.randf_range(ARENA_PADDING, effective_arena_width - ARENA_PADDING), effective_arena_height - ARENA_PADDING)
		2:  # Left edge
			pos = Vector2(ARENA_PADDING, rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING))
		3:  # Right edge
			pos = Vector2(effective_arena_width - ARENA_PADDING, rng.randf_range(ARENA_PADDING, effective_arena_height - ARENA_PADDING))

	return pos


func get_arena_bounds() -> Rect2:
	## Return the playable arena bounds (inside the walls)
	## Player collision should stop at the wall inner edge
	var wall_inner = ARENA_WALL_THICKNESS  # Where walls end
	return Rect2(wall_inner, wall_inner,
				 effective_arena_width - wall_inner * 2,
				 effective_arena_height - wall_inner * 2)


# AI Training functions
func setup_training_manager() -> void:
	# Don't setup training manager if we're inside a SubViewport (training instance)
	if get_viewport() != get_tree().root:
		return

	var TrainingManager = load("res://training_manager.gd")
	training_manager = TrainingManager.new()
	add_child(training_manager)
	training_manager.initialize(self)

	# Create AI status label
	ai_status_label = Label.new()
	ai_status_label.position = Vector2(10, 10)
	ai_status_label.add_theme_color_override("font_color", Color.WHITE)
	ai_status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	ai_status_label.add_theme_constant_override("shadow_offset_x", 1)
	ai_status_label.add_theme_constant_override("shadow_offset_y", 1)
	$CanvasLayer/UI.add_child(ai_status_label)
	ai_status_label.text = "T=Train | C=CoEvo | P=Playback | H=Human"


func handle_training_input() -> void:
	if not training_manager:
		return

	# T = Start/Stop Training
	if Input.is_action_just_pressed("ui_text_submit"):  # We'll use a different key
		pass

	if Input.is_key_pressed(KEY_T) and Input.is_action_just_pressed("ui_focus_next"):
		# Avoid accidental triggers
		pass

	# Check for key presses (using _unhandled_key_input would be cleaner but this works)
	if Input.is_physical_key_pressed(KEY_T) and not Input.is_physical_key_pressed(KEY_SHIFT):
		if not _key_just_pressed("train"):
			return
		if training_manager.get_mode() == training_manager.Mode.TRAINING:
			training_manager.stop_training()
		else:
			training_manager.start_training(100, 100)

	elif Input.is_physical_key_pressed(KEY_P):
		if not _key_just_pressed("playback"):
			return
		if training_manager.get_mode() == training_manager.Mode.PLAYBACK:
			training_manager.stop_playback()
		else:
			training_manager.start_playback()

	elif Input.is_physical_key_pressed(KEY_C) and not Input.is_physical_key_pressed(KEY_SHIFT):
		if not _key_just_pressed("coevo"):
			return
		if training_manager.get_mode() == training_manager.Mode.COEVOLUTION:
			training_manager.stop_coevolution_training()
		else:
			training_manager.start_coevolution_training(100, 100)

	elif Input.is_physical_key_pressed(KEY_H):
		if not _key_just_pressed("human"):
			return
		if training_manager.get_mode() == training_manager.Mode.TRAINING:
			training_manager.stop_training()
		elif training_manager.get_mode() == training_manager.Mode.COEVOLUTION:
			training_manager.stop_coevolution_training()
		elif training_manager.get_mode() == training_manager.Mode.PLAYBACK:
			training_manager.stop_playback()
		elif training_manager.get_mode() == training_manager.Mode.GENERATION_PLAYBACK:
			training_manager.stop_playback()

	elif Input.is_physical_key_pressed(KEY_G):
		if not _key_just_pressed("gen_playback"):
			return
		if training_manager.get_mode() == training_manager.Mode.GENERATION_PLAYBACK:
			training_manager.stop_playback()
		else:
			training_manager.start_generation_playback()

	# SPACE to advance generation playback (only when game over)
	if training_manager.get_mode() == training_manager.Mode.GENERATION_PLAYBACK:
		if Input.is_action_just_pressed("ui_accept") and game_over:
			training_manager.advance_generation_playback()

	# Training mode controls (SPACE for pause is handled in training_manager._input)
	if training_manager.get_mode() == training_manager.Mode.TRAINING or training_manager.get_mode() == training_manager.Mode.COEVOLUTION:
		# Speed controls ([ and ] or - and =) - only when not paused
		if not training_manager.is_paused:
			var speed_down = Input.is_physical_key_pressed(KEY_BRACKETLEFT) or Input.is_physical_key_pressed(KEY_MINUS)
			var speed_up = Input.is_physical_key_pressed(KEY_BRACKETRIGHT) or Input.is_physical_key_pressed(KEY_EQUAL)

			if speed_down and not _speed_down_held:
				training_manager.adjust_speed(-1.0)
			if speed_up and not _speed_up_held:
				training_manager.adjust_speed(1.0)

			_speed_down_held = speed_down
			_speed_up_held = speed_up


var _pressed_keys: Dictionary = {}
var _speed_down_held: bool = false
var _speed_up_held: bool = false

func _key_just_pressed(key_name: String) -> bool:
	if _pressed_keys.get(key_name, false):
		return false  # Already pressed
	_pressed_keys[key_name] = true
	# Reset after a short delay
	get_tree().create_timer(0.3).timeout.connect(func(): _pressed_keys[key_name] = false)
	return true


func update_ai_status_display() -> void:
	if not training_manager or not ai_status_label:
		return

	var stats: Dictionary = training_manager.get_stats()
	var mode_str: String = stats.get("mode", "HUMAN")

	if mode_str == "TRAINING":
		ai_status_label.text = "TRAINING | Gen: %d | Individual: %d/%d\nBest: %.0f | All-time: %.0f\n[T]=Stop [H]=Human" % [
			stats.get("generation", 0),
			stats.get("individual", 0) + 1,
			stats.get("population_size", 0),
			stats.get("best_fitness", 0),
			stats.get("all_time_best", 0)
		]
		ai_status_label.add_theme_color_override("font_color", Color.YELLOW)
	elif mode_str == "COEVOLUTION":
		ai_status_label.text = "CO-EVOLUTION | Gen: %d | P.Best: %.0f | E.Best: %.0f\n[C]=Stop [H]=Human" % [
			stats.get("generation", 0),
			stats.get("best_fitness", 0),
			stats.get("enemy_best_fitness", 0),
		]
		ai_status_label.add_theme_color_override("font_color", Color.ORANGE)
	elif mode_str == "PLAYBACK":
		ai_status_label.text = "PLAYBACK | Watching best AI\n[P]=Stop [H]=Human"
		ai_status_label.add_theme_color_override("font_color", Color.CYAN)
	elif mode_str == "GENERATION_PLAYBACK":
		ai_status_label.text = "GENERATION %d/%d\n[SPACE]=Next [G]=Restart [H]=Human" % [
			stats.get("playback_generation", 1),
			stats.get("max_playback_generation", 1)
		]
		ai_status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		ai_status_label.text = "[T]=Train | [C]=CoEvo | [P]=Playback | [G]=Gen Playback"
		ai_status_label.add_theme_color_override("font_color", Color.WHITE)
