extends Node2D

## Main game scene — orchestrates subsystem managers.
## Game state is managed by GameStateManager, difficulty by DifficultyScaler,
## input by InputCoordinator + TrainingInputHandler, spawning by SpawnManager,
## scoring by ScoreManager, power-ups by PowerupManager, UI by UIManager.

var floating_text_scene: PackedScene = preload("res://floating_text.tscn")
var spawned_obstacle_positions: Array = []

# Preload subsystem manager scripts explicitly so class names resolve in headless mode
# (class_name alone is unreliable in headless mode without a warm script cache)
const _GameStateManagerScript = preload("res://game_state_manager.gd")
const _DifficultyScalerScript = preload("res://difficulty_scaler.gd")
const _InputCoordinatorScript = preload("res://input_coordinator.gd")

# Subsystem managers
var game_state
var difficulty
var input_coord
var spawn_mgr: RefCounted  ## SpawnManager
var score_mgr: RefCounted  ## ScoreManager
var powerup_mgr: RefCounted  ## PowerupManager
var ui_mgr: RefCounted  ## UIManager
var training_input_handler: RefCounted  ## TrainingInputHandler

# AI Training
var training_manager: Node
var ai_status_label: Label

# UI screens
var title_screen: Control = null
var game_over_screen: Control = null
var sensor_visualizer: Node2D = null
var sandbox_panel: Control = null
var comparison_panel: Control = null
var network_visualizer: Control = null
var educational_overlay: Control = null
var phylogenetic_tree: Control = null
var game_started: bool = false  # False until player selects mode from title screen

# Chess piece types for spawning
enum ChessPiece { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

# Arena configuration - large square arena
const ARENA_WIDTH: float = 3840.0   # 3x viewport width
const ARENA_HEIGHT: float = 3840.0  # Square arena

# Power-up limit
const MAX_POWERUPS: int = 15  # Maximum power-ups on the map at once

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

var game_seed: int = 0  # Seed for deterministic training
var training_mode: bool = false  # Simplified game for AI training
var rng: RandomNumberGenerator  # Per-arena RNG for deterministic replay

# Sandbox overrides
var sandbox_spawn_rate_multiplier: float = 1.0
var sandbox_powerup_frequency: float = 1.0
var sandbox_starting_difficulty: float = 0.0
var sandbox_overrides_active: bool = false

# Curriculum config applied to this instance
var curriculum_config: Dictionary = {}  # From training_manager curriculum stages
var effective_arena_width: float = ARENA_WIDTH
var effective_arena_height: float = ARENA_HEIGHT

# Pre-generated events for deterministic training
var preset_obstacles: Array = []  # [{pos: Vector2}, ...]
var preset_enemy_spawns: Array = []  # [{time: float, pos: Vector2, type: int}, ...]
var use_preset_events: bool = false
var preset_powerup_spawns: Array = []  # [{time: float, pos: Vector2, type: int}, ...]

# Spawn tracking
var next_spawn_score: float = 50.0
var next_powerup_score: float = 30.0

# Co-evolution: if set, all spawned enemies use this neural network for AI control
var enemy_ai_network = null

# --- Convenience accessors (keep API compatible) ---
var score: float:
	get: return game_state.score
	set(v): game_state.score = v

var lives: int:
	get: return game_state.lives
	set(v): game_state.lives = v

var game_over: bool:
	get: return game_state.game_over
	set(v): game_state.game_over = v

var kills: int:
	get: return game_state.kills
	set(v): game_state.kills = v

var powerups_collected: int:
	get: return game_state.powerups_collected
	set(v): game_state.powerups_collected = v

var score_from_kills: float:
	get: return game_state.score_from_kills
	set(v): game_state.score_from_kills = v

var score_from_powerups: float:
	get: return game_state.score_from_powerups
	set(v): game_state.score_from_powerups = v

var entering_name: bool:
	get: return game_state.entering_name
	set(v): game_state.entering_name = v

var survival_time: float:
	get: return game_state.survival_time
	set(v): game_state.survival_time = v

var last_milestone: int:
	get: return game_state.last_milestone
	set(v): game_state.last_milestone = v

# -------------------------------------------------

func set_game_seed(s: int) -> void:
	## Set random seed for deterministic game (used in training).
	game_seed = s
	rng = RandomNumberGenerator.new()
	rng.seed = s

func set_training_mode(enabled: bool, p_curriculum_config: Dictionary = {}) -> void:
	## Enable simplified game mode for AI training.
	training_mode = enabled
	if enabled:
		game_started = true
	curriculum_config = p_curriculum_config
	if not curriculum_config.is_empty():
		var scale: float = curriculum_config.get("arena_scale", 1.0)
		effective_arena_width = ARENA_WIDTH * scale
		effective_arena_height = ARENA_HEIGHT * scale
	else:
		effective_arena_width = ARENA_WIDTH
		effective_arena_height = ARENA_HEIGHT
	if spawn_mgr:
		spawn_mgr.effective_arena_width = effective_arena_width
		spawn_mgr.effective_arena_height = effective_arena_height

func apply_sandbox_overrides(config: Dictionary) -> void:
	sandbox_spawn_rate_multiplier = clampf(config.get("spawn_rate_multiplier", 1.0), 0.25, 3.0)
	sandbox_powerup_frequency = clampf(config.get("powerup_frequency", 1.0), 0.25, 3.0)
	sandbox_starting_difficulty = clampf(config.get("starting_difficulty", 0.0), 0.0, 1.0)
	sandbox_overrides_active = true
	var enemy_types: Array = config.get("enemy_types", [])
	if enemy_types.size() > 0:
		curriculum_config = {"enemy_types": enemy_types.duplicate()}
	_apply_sandbox_starting_state()

func clear_sandbox_overrides() -> void:
	sandbox_spawn_rate_multiplier = 1.0
	sandbox_powerup_frequency = 1.0
	sandbox_starting_difficulty = 0.0
	sandbox_overrides_active = false
	curriculum_config = {}

func _apply_sandbox_starting_state() -> void:
	if not sandbox_overrides_active:
		return
	score = sandbox_starting_difficulty * _DifficultyScalerScript.DIFFICULTY_SCALE_SCORE
	next_spawn_score = score + get_scaled_spawn_interval()
	next_powerup_score = score + _get_powerup_interval(80.0)

func _get_powerup_interval(base: float = 80.0) -> float:
	var interval = base
	if sandbox_overrides_active:
		interval = interval / maxf(sandbox_powerup_frequency, 0.1)
	return interval

func set_preset_events(obstacles: Array, enemy_spawns: Array, powerup_spawns: Array = []) -> void:
	## Use pre-generated events for deterministic gameplay.
	preset_obstacles = obstacles
	preset_enemy_spawns = enemy_spawns.duplicate()
	preset_powerup_spawns = powerup_spawns.duplicate()
	use_preset_events = true

static var _EventGenerator = load("res://scripts/event_generator.gd")

static func generate_random_events(seed_value: int, p_curriculum_config: Dictionary = {}, sandbox_overrides: Dictionary = {}) -> Dictionary:
	return _EventGenerator.generate(seed_value, p_curriculum_config, sandbox_overrides)

func _ready() -> void:
	if not rng:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if DisplayServer.get_name() != "headless":
		print("Evolve app started!")
	get_tree().paused = false

	# Initialize core managers
	game_state = _GameStateManagerScript.new()
	difficulty = _DifficultyScalerScript.new()

	# Initialize extracted managers
	score_mgr = load("res://score_manager.gd").new()
	spawn_mgr = load("res://spawn_manager.gd").new()
	spawn_mgr.setup(self, player, rng)
	spawn_mgr.effective_arena_width = effective_arena_width
	spawn_mgr.effective_arena_height = effective_arena_height
	powerup_mgr = load("res://powerup_manager.gd").new()
	powerup_mgr.setup(self, player, score_mgr, spawn_mgr)

	# Set up projectile pool for player
	var _ObjectPool = load("res://scripts/object_pool.gd")
	var proj_pool = _ObjectPool.new(preload("res://projectile.tscn"), self)
	player.projectile_pool = proj_pool

	player.hit.connect(_on_player_hit)
	player.enemy_killed.connect(_on_enemy_killed)
	player.powerup_timer_updated.connect(powerup_mgr.handle_powerup_timer_updated)
	player.shot_fired.connect(_on_shot_fired)
	game_over_label.visible = false
	powerup_label.visible = false
	name_entry.visible = false
	name_prompt.visible = false
	score_mgr.load_high_scores()
	update_lives_display()
	scoreboard_label.text = score_mgr.get_scoreboard_text()
	setup_arena()
	spawn_arena_obstacles()
	spawn_initial_enemies()
	setup_training_manager()
	training_input_handler = load("res://training_input_handler.gd").new()
	training_input_handler.setup(self, training_manager)
	ui_mgr = load("res://ui_manager.gd").new()
	ui_mgr.setup(self, training_manager, ai_status_label)
	ui_mgr.setup_ui_screens()

	# Input coordinator (for interactive modes)
	input_coord = _InputCoordinatorScript.new()
	input_coord.setup(self)

	# Check for command-line flags
	for arg in OS.get_cmdline_user_args():
		if arg == "--auto-train":
			call_deferred("_start_auto_training")
			return
		if arg == "--demo":
			call_deferred("_start_demo_playback")
			return
		if arg == "--auto-play":
			call_deferred("_on_title_mode_selected", "play")
			return

	# Show title screen on startup (only for root viewport / human play)
	if get_viewport() == get_tree().root and not training_mode:
		show_title_screen()
	else:
		game_started = true

func show_title_screen() -> void:
	if not title_screen:
		return
	game_started = false
	game_over = false
	get_tree().paused = true
	score_label.visible = false
	lives_label.visible = false
	scoreboard_label.visible = false
	game_over_label.visible = false
	name_entry.visible = false
	name_prompt.visible = false
	if game_over_screen:
		game_over_screen.hide_screen()
	if ai_status_label:
		ai_status_label.visible = false
	title_screen.show_menu()

func _on_title_mode_selected(mode: String) -> void:
	if mode == "sandbox":
		_show_sandbox_panel()
		return
	if mode == "compare":
		_show_comparison_panel()
		return

	game_started = true
	get_tree().paused = false
	score_label.visible = true
	lives_label.visible = true
	scoreboard_label.visible = true
	if ai_status_label:
		ai_status_label.visible = true

	match mode:
		"play":
			pass
		"watch":
			if training_manager:
				training_manager.start_playback()
		"train":
			if training_manager:
				training_manager.start_training(100, 100)
		"coevolution":
			if training_manager:
				training_manager.start_training(100, 100)
		"rtneat":
			if training_manager:
				training_manager.start_rtneat({"agent_count": 30})
		"teams":
			if training_manager:
				training_manager.start_rtneat_teams({"team_size": 15})

func _show_game_over_stats() -> void:
	if not game_over_screen:
		return
	game_over_label.visible = false
	name_entry.visible = false
	name_prompt.visible = false

	var mode_str := "play"
	if training_manager and training_manager.get_mode() == training_manager.Mode.PLAYBACK:
		mode_str = "watch"
	elif training_manager and training_manager.get_mode() == training_manager.Mode.ARCHIVE_PLAYBACK:
		mode_str = "archive"

	var stats: Dictionary = game_state.get_stats()
	stats["is_high_score"] = score_mgr.is_high_score(int(score))
	stats["mode"] = mode_str
	game_over_screen.show_stats(stats)

func _on_game_over_restart() -> void:
	game_over_screen.hide_screen()
	get_tree().reload_current_scene()

func _on_game_over_menu() -> void:
	game_over_screen.hide_screen()
	get_tree().reload_current_scene()

func _show_sandbox_panel() -> void:
	if sandbox_panel:
		sandbox_panel.visible = true

func _on_sandbox_start(config: Dictionary) -> void:
	sandbox_panel.visible = false
	game_started = true
	get_tree().paused = false
	score_label.visible = true
	lives_label.visible = true
	scoreboard_label.visible = true
	if ai_status_label:
		ai_status_label.visible = true
	if training_manager:
		training_manager.start_sandbox(config)

func _on_sandbox_train(config: Dictionary) -> void:
	sandbox_panel.visible = false
	game_started = true
	get_tree().paused = false
	score_label.visible = true
	lives_label.visible = true
	scoreboard_label.visible = true
	if ai_status_label:
		ai_status_label.visible = true
	if training_manager:
		training_manager.start_sandbox_training(config)

func _on_sandbox_back() -> void:
	sandbox_panel.visible = false
	show_title_screen()

func _show_comparison_panel() -> void:
	if comparison_panel:
		comparison_panel.visible = true

func _on_comparison_start(strategies: Array) -> void:
	comparison_panel.visible = false
	game_started = true
	get_tree().paused = false
	score_label.visible = false
	lives_label.visible = false
	scoreboard_label.visible = false
	if ai_status_label:
		ai_status_label.visible = false
	if training_manager:
		training_manager.start_comparison(strategies)

func _on_comparison_back() -> void:
	comparison_panel.visible = false
	show_title_screen()

func _toggle_network_visualizer() -> void:
	if not network_visualizer:
		return
	network_visualizer.visible = not network_visualizer.visible
	if network_visualizer.visible and training_manager:
		if training_manager.ai_controller and training_manager.ai_controller.network:
			var net = training_manager.ai_controller.network
			if net and net.has_method("get_connection_count"):
				network_visualizer.set_neat_data(null, net)
			else:
				network_visualizer.set_fixed_network(net)

func _toggle_phylogenetic_tree() -> void:
	if not phylogenetic_tree:
		return
	phylogenetic_tree.panel_visible = not phylogenetic_tree.panel_visible
	phylogenetic_tree.visible = phylogenetic_tree.panel_visible

func _toggle_educational_mode() -> void:
	if not educational_overlay:
		return
	educational_overlay.visible = not educational_overlay.visible
	if educational_overlay.visible:
		if sensor_visualizer and not sensor_visualizer.enabled:
			sensor_visualizer.toggle()
		if network_visualizer and not network_visualizer.visible:
			_toggle_network_visualizer()
	else:
		if sensor_visualizer:
			sensor_visualizer.highlighted_ray = -1

func _start_auto_training() -> void:
	if training_manager:
		print("Auto-training started via command line")
		training_manager.start_training()

func _start_demo_playback() -> void:
	game_started = true
	get_tree().paused = false
	score_label.visible = true
	lives_label.visible = true
	scoreboard_label.visible = true
	if ai_status_label:
		ai_status_label.visible = true
	if training_manager:
		training_manager.start_playback()

func _get_speed_target() -> Variant:
	if not training_manager:
		return null
	var mode = training_manager.get_mode()
	if (mode == training_manager.Mode.TRAINING or mode == training_manager.Mode.COEVOLUTION) and not training_manager.is_paused:
		return training_manager
	if mode == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
		return training_manager.rtneat_mgr
	if mode == training_manager.Mode.TEAMS and training_manager.team_mgr:
		return training_manager.team_mgr
	return null

func _unhandled_input(event: InputEvent) -> void:
	var interactive_mgr = input_coord.get_interactive_manager(training_manager)
	if interactive_mgr:
		input_coord.handle_interactive_input(event, interactive_mgr)

func _process(delta: float) -> void:
	# Handle AI training controls
	if training_input_handler:
		training_input_handler.handle_training_input()

	# Visualization toggles
	_handle_viz_toggles()

	# Feed data to overlays
	_update_overlays()

	if not game_started:
		return

	if game_over:
		_handle_game_over_input()
		return

	# Score and survival
	var score_multiplier = powerup_mgr.get_score_multiplier()
	score += delta * 5 * score_multiplier
	score_label.text = "Score: %d" % int(score)
	if ui_mgr:
		ui_mgr.update_ai_status_display()

	game_state.update_survival(delta, score_mgr.MILESTONE_INTERVAL, score_mgr.SURVIVAL_MILESTONE_BONUS)

	# Proximity rewards
	var proximity_bonus = calculate_proximity_bonus(delta)
	if proximity_bonus > 0:
		score += proximity_bonus
		score_from_powerups += proximity_bonus

	# Update screen clear cooldown
	if screen_clear_cooldown > 0:
		screen_clear_cooldown -= delta

	# Enemy spawning
	_process_enemy_spawning()

	# Powerup spawning
	_process_powerup_spawning()


func _handle_viz_toggles() -> void:
	if sensor_visualizer and Input.is_physical_key_pressed(KEY_V):
		if _key_just_pressed("sensor_viz"):
			sensor_visualizer.toggle()
	if network_visualizer and Input.is_physical_key_pressed(KEY_N):
		if _key_just_pressed("net_viz"):
			_toggle_network_visualizer()
	if educational_overlay and Input.is_physical_key_pressed(KEY_E):
		if _key_just_pressed("edu_mode"):
			_toggle_educational_mode()
	if phylogenetic_tree and Input.is_physical_key_pressed(KEY_Y):
		if _key_just_pressed("phylo_tree"):
			_toggle_phylogenetic_tree()


func _update_overlays() -> void:
	# Educational overlay
	if educational_overlay and educational_overlay.visible and training_manager:
		var controller = null
		var sensor = null
		var mode = training_manager.get_mode()
		if mode == training_manager.Mode.PLAYBACK and training_manager.ai_controller:
			controller = training_manager.ai_controller
			sensor = training_manager.ai_controller.sensor
		elif mode == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
			var idx: int = training_manager.rtneat_mgr.inspected_agent_index
			if idx >= 0 and idx < training_manager.rtneat_mgr.controllers.size():
				controller = training_manager.rtneat_mgr.controllers[idx]
				sensor = training_manager.rtneat_mgr.sensors[idx]
		if controller:
			educational_overlay.update_from_controller(controller, sensor)
			if sensor_visualizer:
				sensor_visualizer.highlighted_ray = educational_overlay.get_highlight_ray()

	# Phylogenetic tree
	if phylogenetic_tree and phylogenetic_tree.visible and phylogenetic_tree.panel_visible and training_manager:
		if training_manager.lineage_tracker:
			var mode = training_manager.get_mode()
			var best_id: int = -1
			if mode == training_manager.Mode.TRAINING or mode == training_manager.Mode.COEVOLUTION:
				best_id = training_manager.lineage_tracker.get_best_id(training_manager.generation)
				if best_id < 0 and training_manager.generation > 0:
					best_id = training_manager.lineage_tracker.get_best_id(training_manager.generation - 1)
			elif mode == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
				var pop = training_manager.rtneat_mgr.population
				if pop:
					var best_fit: float = -INF
					for i in pop.pop_size:
						if pop.fitnesses[i] > best_fit:
							best_fit = pop.fitnesses[i]
							if pop._lineage_ids.size() > i:
								best_id = pop._lineage_ids[i]
			if best_id >= 0:
				phylogenetic_tree.set_lineage_data(training_manager.lineage_tracker, best_id)


func _handle_game_over_input() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	if entering_name:
		if Input.is_action_just_pressed("ui_accept") and name_entry.text.strip_edges() != "":
			submit_high_score(name_entry.text.strip_edges())
	else:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().reload_current_scene()


func _process_enemy_spawning() -> void:
	if use_preset_events:
		while preset_enemy_spawns.size() > 0 and preset_enemy_spawns[0].time <= survival_time:
			var spawn_data = preset_enemy_spawns.pop_front()
			spawn_enemy_at(spawn_data.pos, spawn_data.type)
	elif score >= next_spawn_score and screen_clear_cooldown <= 0:
		spawn_enemy()
		var spawn_interval = get_scaled_spawn_interval()
		next_spawn_score += spawn_interval


func _process_powerup_spawning() -> void:
	if use_preset_events:
		while preset_powerup_spawns.size() > 0 and preset_powerup_spawns[0].time <= survival_time:
			var spawn_data = preset_powerup_spawns.pop_front()
			spawn_powerup_at(spawn_data.pos, spawn_data.type)
	elif score >= next_powerup_score:
		var powerup_count = count_local_powerups()
		if powerup_count >= MAX_POWERUPS:
			next_powerup_score = score + _get_powerup_interval(80.0)
		elif spawn_powerup():
			next_powerup_score += _get_powerup_interval(80.0)
		else:
			next_powerup_score = score + _get_powerup_interval(20.0)


# --- Difficulty delegation ---

func get_difficulty_factor() -> float:
	return difficulty.get_difficulty_factor(score)

func get_scaled_enemy_speed() -> float:
	return difficulty.get_scaled_enemy_speed(score)

func get_scaled_spawn_interval() -> float:
	return difficulty.get_scaled_spawn_interval(score, sandbox_spawn_rate_multiplier, sandbox_overrides_active)


# --- Spawning delegation ---

func spawn_enemy() -> void:
	spawn_mgr.spawn_enemy(training_mode, curriculum_config, get_difficulty_factor(), get_scaled_enemy_speed(), enemy_ai_network, powerup_mgr.freeze_active, powerup_mgr.slow_active)

func spawn_enemy_at(pos: Vector2, enemy_type: int) -> void:
	spawn_mgr.spawn_enemy_at(pos, enemy_type, get_scaled_enemy_speed(), training_mode, enemy_ai_network, powerup_mgr.freeze_active, powerup_mgr.slow_active)

func spawn_powerup_at(pos: Vector2, powerup_type: int) -> void:
	spawn_mgr.spawn_powerup_at(pos, powerup_type, MAX_POWERUPS, powerup_mgr.handle_powerup_collected)

func spawn_initial_enemies() -> void:
	spawn_mgr.spawn_initial_enemies(training_mode, _DifficultyScalerScript.BASE_ENEMY_SPEED, enemy_ai_network)

func count_local_powerups() -> int:
	return spawn_mgr.count_local_powerups()

func spawn_powerup() -> bool:
	return spawn_mgr.spawn_powerup(MAX_POWERUPS, powerup_mgr.handle_powerup_collected)

func find_valid_powerup_position() -> Vector2:
	return spawn_mgr.find_valid_powerup_position()


# --- Score/combat ---

func calculate_proximity_bonus(delta: float) -> float:
	return score_mgr.calculate_proximity_bonus(delta, player, self)

func _on_enemy_killed(pos: Vector2, points: int = 1) -> void:
	var multiplier = powerup_mgr.get_score_multiplier()
	var bonus = game_state.add_kill(points, multiplier, score_mgr.KILL_MULTIPLIER)
	spawn_floating_text("+%d" % bonus, Color(1, 1, 0, 1), pos)

func spawn_floating_text(text: String, color: Color, pos: Vector2) -> void:
	var floating = floating_text_scene.instantiate()
	add_child(floating)
	floating.setup(text, color, pos)

func _on_shot_fired(direction: Vector2) -> void:
	if not training_mode:
		return
	var dominated_enemies = get_local_enemies()
	for enemy in dominated_enemies:
		if not is_instance_valid(enemy):
			continue
		var to_enemy = (enemy.position - player.position).normalized()
		var dot = direction.dot(to_enemy)
		var dist = player.position.distance_to(enemy.position)
		if dot > 0.7 and dist < 800:
			var bonus = score_mgr.SHOOT_TOWARD_ENEMY_BONUS
			score += bonus
			# Note: aim bonus is NOT a kill — do not add to score_from_kills
			return

func get_local_enemies() -> Array:
	return spawn_mgr.get_local_enemies()

func update_lives_display() -> void:
	lives_label.text = "Lives: %d" % lives

func _on_player_hit() -> void:
	if not game_started or game_over:
		return
	game_state.take_hit()
	update_lives_display()
	spawn_floating_text("-1 LIFE", Color(1, 0.2, 0.2, 1), player.position + Vector2(0, -30))

	if game_over:
		# Don't pause tree in training mode — it freezes all parallel evals
		if not training_mode:
			get_tree().paused = true
		if score_mgr.is_high_score(int(score)):
			entering_name = true
			game_over_label.text = "NEW HIGH SCORE!\nScore: %d" % int(score)
			game_over_label.visible = true
			name_prompt.visible = true
			name_entry.visible = true
			name_entry.text = ""
			name_entry.grab_focus()
		elif game_over_screen and get_viewport() == get_tree().root:
			_show_game_over_stats()
		else:
			game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
			game_over_label.visible = true
	else:
		var arena_center = Vector2(effective_arena_width / 2, effective_arena_height / 2)
		player.respawn(arena_center, _GameStateManagerScript.RESPAWN_INVINCIBILITY)

func submit_high_score(player_name: String) -> void:
	score_mgr.submit_high_score(player_name, int(score))
	entering_name = false
	name_entry.visible = false
	name_prompt.visible = false
	game_over_label.visible = false
	scoreboard_label.text = score_mgr.get_scoreboard_text()
	if game_over_screen and get_viewport() == get_tree().root:
		_show_game_over_stats()
	else:
		game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
		game_over_label.visible = true


# --- Arena ---

var _ArenaSetup = preload("res://arena_setup.gd")

func setup_arena() -> void:
	var arena_setup_mgr = _ArenaSetup.new()
	arena_camera = arena_setup_mgr.setup_arena(self, player, effective_arena_width, effective_arena_height)
	update_camera_zoom()
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	update_camera_zoom()

func update_camera_zoom() -> void:
	_ArenaSetup.update_camera_zoom(arena_camera, effective_arena_width, effective_arena_height)

func spawn_arena_obstacles() -> void:
	spawn_mgr.spawn_arena_obstacles(use_preset_events, preset_obstacles)

func get_random_edge_spawn_position() -> Vector2:
	return spawn_mgr.get_random_edge_spawn_position()

func get_arena_bounds() -> Rect2:
	return _ArenaSetup.get_arena_bounds(effective_arena_width, effective_arena_height)


# --- Training setup ---

func setup_training_manager() -> void:
	if get_viewport() != get_tree().root:
		return
	var TrainingManager = load("res://training_manager.gd")
	if not TrainingManager or not TrainingManager.can_instantiate():
		push_warning("TrainingManager script failed to load — skipping training setup")
		return
	training_manager = TrainingManager.new()
	add_child(training_manager)
	training_manager.initialize(self)

	ai_status_label = Label.new()
	ai_status_label.position = Vector2(10, 10)
	ai_status_label.add_theme_color_override("font_color", Color.WHITE)
	ai_status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	ai_status_label.add_theme_constant_override("shadow_offset_x", 1)
	ai_status_label.add_theme_constant_override("shadow_offset_y", 1)
	$CanvasLayer/UI.add_child(ai_status_label)
	ai_status_label.text = "T=Train | C=CoEvo | P=Playback | H=Human"


var _pressed_keys: Dictionary = {}

func _key_just_pressed(key_name: String) -> bool:
	if _pressed_keys.get(key_name, false):
		return false
	_pressed_keys[key_name] = true
	get_tree().create_timer(0.3).timeout.connect(func(): _pressed_keys[key_name] = false)
	return true
