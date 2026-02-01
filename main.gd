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

# Bonus points (chess piece values used for kills)
const POWERUP_COLLECT_BONUS: int = 10
const SCREEN_CLEAR_BONUS: int = 25

# Chess piece types for spawning
enum ChessPiece { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

const POWERUP_DURATION: float = 5.0
const SLOW_MULTIPLIER: float = 0.5
const RESPAWN_INVINCIBILITY: float = 2.0

const MAX_HIGH_SCORES: int = 5
const SAVE_PATH: String = "user://highscores.save"

# Obstacle generation
const OBSTACLE_SPAWN_RADIUS: float = 600.0
const OBSTACLE_MIN_DISTANCE: float = 100.0
const OBSTACLE_CLEANUP_RADIUS: float = 900.0
const OBSTACLE_DENSITY: int = 25  # Target number of obstacles around player
const OBSTACLE_MIN_SPAWN_DIST: float = 150.0  # Min distance from player when spawning

# Difficulty scaling
const BASE_ENEMY_SPEED: float = 150.0
const MAX_ENEMY_SPEED: float = 300.0
const BASE_SPAWN_INTERVAL: float = 50.0
const MIN_SPAWN_INTERVAL: float = 20.0
const DIFFICULTY_SCALE_SCORE: float = 500.0  # Score at which difficulty is maxed

# Slow enemies tracking
var slow_active: bool = false

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
	spawn_initial_obstacles()
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

	if score >= next_spawn_score:
		spawn_enemy()
		var spawn_interval = get_scaled_spawn_interval()
		next_spawn_score += spawn_interval

	if score >= next_powerup_score:
		spawn_powerup()
		next_powerup_score += 80.0  # Rarer power-ups (was 40)

	manage_obstacles()

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

	# Apply slow if active
	if slow_active:
		enemy.speed *= SLOW_MULTIPLIER

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

	# Spawn at random position around player (outside view)
	var angle = randf() * TAU
	var distance = randf_range(500, 700)
	var pos = player.position + Vector2(cos(angle), sin(angle)) * distance

	enemy.position = pos
	add_child(enemy)

func spawn_powerup() -> void:
	var powerup = powerup_scene.instantiate()

	# Find a valid position not overlapping obstacles
	var pos = find_valid_powerup_position()
	if pos == Vector2.ZERO:
		powerup.queue_free()
		return  # Couldn't find valid position

	powerup.position = pos

	# Random power-up type
	var type_index = randi() % 4
	powerup.set_type(type_index)
	powerup.collected.connect(_on_powerup_collected)
	add_child(powerup)

func find_valid_powerup_position() -> Vector2:
	const POWERUP_OBSTACLE_MIN_DIST: float = 80.0  # Obstacle size + buffer

	for attempt in range(15):
		var angle = randf() * TAU
		var distance = randf_range(200, 400)
		var pos = player.position + Vector2(cos(angle), sin(angle)) * distance

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
	score += points
	spawn_floating_text("+%d" % points, Color(1, 1, 0, 1), pos)

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
		var enemies = get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			enemy.speed *= SLOW_MULTIPLIER
	slow_active = true
	player.activate_slow_effect(POWERUP_DURATION)

func end_slow_enemies() -> void:
	if slow_active:
		slow_active = false
		var enemies = get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			enemy.speed /= SLOW_MULTIPLIER

func clear_all_enemies() -> void:
	player.trigger_screen_clear_effect()
	var enemies = get_tree().get_nodes_in_group("enemy")
	var total_points = 0
	for enemy in enemies:
		if enemy.has_method("get_point_value"):
			total_points += enemy.get_point_value()
		else:
			total_points += 1
		enemy.queue_free()
	# Bonus points for screen clear (piece values + flat bonus)
	if total_points > 0:
		total_points += SCREEN_CLEAR_BONUS
		score += total_points
		spawn_floating_text("+%d CLEAR!" % total_points, Color(1, 0.3, 0.3, 1), player.position + Vector2(0, -50))

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
		# Respawn player at current position with brief invincibility
		player.respawn(player.position, RESPAWN_INVINCIBILITY)

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

# Obstacle generation functions
func spawn_initial_obstacles() -> void:
	for i in range(OBSTACLE_DENSITY):
		try_spawn_obstacle()

func manage_obstacles() -> void:
	# Clean up far obstacles
	var obstacles = get_tree().get_nodes_in_group("obstacle")
	for obstacle in obstacles:
		if obstacle.position.distance_to(player.position) > OBSTACLE_CLEANUP_RADIUS:
			spawned_obstacle_positions.erase(obstacle.position)
			obstacle.queue_free()

	# Spawn new obstacles if needed
	var current_count = get_tree().get_nodes_in_group("obstacle").size()
	if current_count < OBSTACLE_DENSITY:
		try_spawn_obstacle()

func try_spawn_obstacle() -> void:
	for attempt in range(10):
		var angle = randf() * TAU
		var distance = randf_range(300, OBSTACLE_SPAWN_RADIUS)
		var pos = player.position + Vector2(cos(angle), sin(angle)) * distance

		# Check minimum distance from player
		if pos.distance_to(player.position) < OBSTACLE_MIN_DISTANCE:
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
			return


# AI Training functions
func setup_training_manager() -> void:
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
			training_manager.start_training(50, 100)

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


var _pressed_keys: Dictionary = {}

func _key_just_pressed(key_name: String) -> bool:
	var is_pressed := true
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
	else:
		ai_status_label.text = "[T]=Train | [P]=Playback"
		ai_status_label.add_theme_color_override("font_color", Color.WHITE)
