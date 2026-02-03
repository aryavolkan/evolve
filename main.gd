extends Node2D

var score: float = 0.0
var lives: int = 3
var game_over: bool = false
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

# Bonus points - made significant so AI learns to prioritize kills and power-ups
const POWERUP_COLLECT_BONUS: int = 50      # Was 10 - now worth 5 seconds of survival
const SCREEN_CLEAR_BONUS: int = 100        # Was 25 - big reward for clearing screen
const KILL_MULTIPLIER: int = 10            # Multiply chess piece values (1-9 -> 10-90)

# Chess piece types for spawning
enum ChessPiece { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

const POWERUP_DURATION: float = 5.0
const SLOW_MULTIPLIER: float = 0.5
const RESPAWN_INVINCIBILITY: float = 2.0

const MAX_HIGH_SCORES: int = 5
const SAVE_PATH: String = "user://highscores.save"

# Arena configuration - large arena (2x viewport size, zoomed out to fit)
const ARENA_WIDTH: float = 2560.0   # 2x viewport width
const ARENA_HEIGHT: float = 1440.0  # 2x viewport height
const ARENA_WALL_THICKNESS: float = 40.0
const ARENA_PADDING: float = 100.0  # Safe zone from walls for spawning

# Permanent obstacle configuration
const OBSTACLE_COUNT: int = 20      # Fewer obstacles for clearer navigation
const OBSTACLE_MIN_DISTANCE: float = 120.0  # Min distance between obstacles
const OBSTACLE_PLAYER_SAFE_ZONE: float = 250.0  # Keep obstacles away from player spawn

# Power-up limit
const MAX_POWERUPS: int = 5  # Maximum power-ups on the map at once

# Difficulty scaling
const BASE_ENEMY_SPEED: float = 150.0
const MAX_ENEMY_SPEED: float = 300.0
const BASE_SPAWN_INTERVAL: float = 50.0
const MIN_SPAWN_INTERVAL: float = 20.0
const DIFFICULTY_SCALE_SCORE: float = 500.0  # Score at which difficulty is maxed

# Slow enemies tracking
var slow_active: bool = false

# Screen clear spawn cooldown
var screen_clear_cooldown: float = 0.0
const SCREEN_CLEAR_SPAWN_DELAY: float = 2.0  # No enemy spawns for 2 seconds after clear

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

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		print("Evolve app started!")
	get_tree().paused = false
	player.hit.connect(_on_player_hit)
	player.enemy_killed.connect(_on_enemy_killed)
	player.powerup_timer_updated.connect(_on_powerup_timer_updated)
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

	score += delta * 10
	score_label.text = "Score: %d" % int(score)
	update_ai_status_display()

	# Update screen clear cooldown
	if screen_clear_cooldown > 0:
		screen_clear_cooldown -= delta

	if score >= next_spawn_score and screen_clear_cooldown <= 0:
		spawn_enemy()
		var spawn_interval = get_scaled_spawn_interval()
		next_spawn_score += spawn_interval

	# Spawn power-ups based on score, but respect the MAX_POWERUPS limit
	if score >= next_powerup_score:
		# Count only local powerups (in this scene, not globally)
		var powerup_count = count_local_powerups()

		if powerup_count >= MAX_POWERUPS:
			# At max power-ups, set next threshold far ahead
			next_powerup_score = score + 80.0
		elif spawn_powerup():
			next_powerup_score += 80.0
		else:
			# Couldn't spawn (no valid position), try again later
			next_powerup_score = score + 20.0

func get_difficulty_factor() -> float:
	return clampf(score / DIFFICULTY_SCALE_SCORE, 0.0, 1.0)

func get_scaled_enemy_speed() -> float:
	var factor = get_difficulty_factor()
	return lerpf(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, factor)

func get_scaled_spawn_interval() -> float:
	var factor = get_difficulty_factor()
	return lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, factor)

func spawn_enemy() -> void:
	var enemy = enemy_scene.instantiate()
	enemy.speed = get_scaled_enemy_speed()

	# Chess piece type (weighted: pawns common, higher pieces rarer)
	# As difficulty increases, better pieces spawn more often
	var type_roll = randf()
	var difficulty = get_difficulty_factor()

	# Weighted spawning based on difficulty
	# Early game: mostly pawns, Late game: more variety
	if type_roll < 0.5 - difficulty * 0.3:
		enemy.type = ChessPiece.PAWN      # 1 point
	elif type_roll < 0.7 - difficulty * 0.1:
		enemy.type = ChessPiece.KNIGHT    # 3 points
	elif type_roll < 0.85:
		enemy.type = ChessPiece.BISHOP    # 3 points
	elif type_roll < 0.95:
		enemy.type = ChessPiece.ROOK      # 5 points
	else:
		enemy.type = ChessPiece.QUEEN     # 9 points

	# Spawn at random position along arena edges
	var pos = get_random_edge_spawn_position()
	enemy.position = pos
	add_child(enemy)

	# Apply slow after adding to tree (so apply_type_config has run)
	if slow_active:
		enemy.apply_slow(SLOW_MULTIPLIER)


func spawn_initial_enemies() -> void:
	## Spawn initial enemies at the arena edges
	const INITIAL_ENEMY_COUNT: int = 10
	for i in range(INITIAL_ENEMY_COUNT):
		var enemy = enemy_scene.instantiate()
		enemy.speed = BASE_ENEMY_SPEED
		enemy.type = ChessPiece.PAWN  # Start with pawns
		enemy.position = get_random_edge_spawn_position()
		add_child(enemy)


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

	# Random powerup type
	var type_index = randi() % 4
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
			randf_range(ARENA_PADDING, ARENA_WIDTH - ARENA_PADDING),
			randf_range(ARENA_PADDING, ARENA_HEIGHT - ARENA_PADDING)
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
	show_powerup_message(type)

	# Bonus for collecting powerup
	score += POWERUP_COLLECT_BONUS
	spawn_floating_text("+%d" % POWERUP_COLLECT_BONUS, Color(0, 1, 0.5, 1), player.position)

	match type:
		"SPEED BOOST":
			player.activate_speed_boost(POWERUP_DURATION)
		"INVINCIBILITY":
			player.activate_invincibility(POWERUP_DURATION)
		"SLOW ENEMIES":
			activate_slow_enemies()
		"SCREEN CLEAR":
			clear_all_enemies()

func _on_enemy_killed(pos: Vector2, points: int = 1) -> void:
	var bonus = points * KILL_MULTIPLIER  # Scale up kill rewards (pawn=10, queen=90)
	score += bonus
	spawn_floating_text("+%d" % bonus, Color(1, 1, 0, 1), pos)

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
		var arena_center = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)
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
	var arena_center = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)

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
	var zoom_x = viewport_size.x / ARENA_WIDTH
	var zoom_y = viewport_size.y / ARENA_HEIGHT
	var zoom_level = min(zoom_x, zoom_y)  # Use smaller to fit both dimensions
	arena_camera.zoom = Vector2(zoom_level, zoom_level)


func create_arena_walls() -> void:
	## Create visible border walls inside the arena boundary
	var wall_thickness = ARENA_WALL_THICKNESS
	var wall_positions = [
		# Top wall - inside the arena, at y = wall_thickness/2
		{"pos": Vector2(ARENA_WIDTH / 2, wall_thickness / 2),
		 "size": Vector2(ARENA_WIDTH, wall_thickness)},
		# Bottom wall - inside the arena
		{"pos": Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT - wall_thickness / 2),
		 "size": Vector2(ARENA_WIDTH, wall_thickness)},
		# Left wall - inside the arena
		{"pos": Vector2(wall_thickness / 2, ARENA_HEIGHT / 2),
		 "size": Vector2(wall_thickness, ARENA_HEIGHT - wall_thickness * 2)},
		# Right wall - inside the arena
		{"pos": Vector2(ARENA_WIDTH - wall_thickness / 2, ARENA_HEIGHT / 2),
		 "size": Vector2(wall_thickness, ARENA_HEIGHT - wall_thickness * 2)}
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
	floor_rect.size = Vector2(ARENA_WIDTH, ARENA_HEIGHT)
	floor_rect.color = Color(0.08, 0.08, 0.12, 1)  # Very dark blue
	floor_rect.z_index = -10
	add_child(floor_rect)

	# Add grid lines for visual reference
	var grid_size = 160.0  # Larger grid for bigger arena
	for x in range(int(ARENA_WIDTH / grid_size) + 1):
		var line = ColorRect.new()
		line.position = Vector2(x * grid_size - 1, 0)
		line.size = Vector2(2, ARENA_HEIGHT)
		line.color = Color(0.12, 0.12, 0.18, 0.5)
		line.z_index = -9
		add_child(line)

	for y in range(int(ARENA_HEIGHT / grid_size) + 1):
		var line = ColorRect.new()
		line.position = Vector2(0, y * grid_size - 1)
		line.size = Vector2(ARENA_WIDTH, 2)
		line.color = Color(0.12, 0.12, 0.18, 0.5)
		line.z_index = -9
		add_child(line)


func spawn_arena_obstacles() -> void:
	## Spawn permanent obstacles throughout the arena
	spawned_obstacle_positions.clear()
	var arena_center = Vector2(ARENA_WIDTH / 2, ARENA_HEIGHT / 2)

	for i in range(OBSTACLE_COUNT):
		var placed = false
		for attempt in range(50):
			# Random position within arena
			var pos = Vector2(
				randf_range(ARENA_PADDING, ARENA_WIDTH - ARENA_PADDING),
				randf_range(ARENA_PADDING, ARENA_HEIGHT - ARENA_PADDING)
			)

			# Keep away from player spawn (center)
			if pos.distance_to(arena_center) < OBSTACLE_PLAYER_SAFE_ZONE:
				continue

			# Check minimum distance from other obstacles
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
	var edge = randi() % 4
	var pos: Vector2

	match edge:
		0:  # Top edge
			pos = Vector2(randf_range(ARENA_PADDING, ARENA_WIDTH - ARENA_PADDING), ARENA_PADDING)
		1:  # Bottom edge
			pos = Vector2(randf_range(ARENA_PADDING, ARENA_WIDTH - ARENA_PADDING), ARENA_HEIGHT - ARENA_PADDING)
		2:  # Left edge
			pos = Vector2(ARENA_PADDING, randf_range(ARENA_PADDING, ARENA_HEIGHT - ARENA_PADDING))
		3:  # Right edge
			pos = Vector2(ARENA_WIDTH - ARENA_PADDING, randf_range(ARENA_PADDING, ARENA_HEIGHT - ARENA_PADDING))

	return pos


func get_arena_bounds() -> Rect2:
	## Return the playable arena bounds (inside the walls)
	## Player collision should stop at the wall inner edge
	var wall_inner = ARENA_WALL_THICKNESS  # Where walls end
	return Rect2(wall_inner, wall_inner,
				 ARENA_WIDTH - wall_inner * 2,
				 ARENA_HEIGHT - wall_inner * 2)


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
	ai_status_label.text = "T=Train | P=Playback | H=Human"


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
			training_manager.start_training(48, 100)

	elif Input.is_physical_key_pressed(KEY_P):
		if not _key_just_pressed("playback"):
			return
		if training_manager.get_mode() == training_manager.Mode.PLAYBACK:
			training_manager.stop_playback()
		else:
			training_manager.start_playback()

	elif Input.is_physical_key_pressed(KEY_H):
		if not _key_just_pressed("human"):
			return
		if training_manager.get_mode() == training_manager.Mode.TRAINING:
			training_manager.stop_training()
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

	# Training mode controls
	if training_manager.get_mode() == training_manager.Mode.TRAINING:
		# SPACE to toggle pause (with graph view)
		if Input.is_action_just_pressed("ui_accept"):
			training_manager.toggle_pause()

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
		ai_status_label.text = "[T]=Train | [P]=Playback | [G]=Gen Playback"
		ai_status_label.add_theme_color_override("font_color", Color.WHITE)
