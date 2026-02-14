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
var floating_text_scene: PackedScene = preload("res://floating_text.tscn")
var spawned_obstacle_positions: Array = []

# Extracted module managers
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

const RESPAWN_INVINCIBILITY: float = 2.0

# Arena configuration - large square arena
const ARENA_WIDTH: float = 3840.0   # 3x viewport width
const ARENA_HEIGHT: float = 3840.0  # Square arena

# Power-up limit
const MAX_POWERUPS: int = 15  # Maximum power-ups on the map at once

# Difficulty scaling
const BASE_ENEMY_SPEED: float = 150.0
const MAX_ENEMY_SPEED: float = 300.0
const BASE_SPAWN_INTERVAL: float = 50.0
const MIN_SPAWN_INTERVAL: float = 20.0
const DIFFICULTY_SCALE_SCORE: float = 500.0  # Score at which difficulty is maxed

# Screen clear spawn cooldown
var screen_clear_cooldown: float = 0.0
const SCREEN_CLEAR_SPAWN_DELAY: float = 2.0  # No enemy spawns for 2 seconds after clear

# Survival milestone tracking
var survival_time: float = 0.0
var last_milestone: int = 0

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
	score = sandbox_starting_difficulty * DIFFICULTY_SCALE_SCORE
	next_spawn_score = score + get_scaled_spawn_interval()
	next_powerup_score = score + _get_powerup_interval(80.0)


func _get_powerup_interval(base: float = 80.0) -> float:
	var interval = base
	if sandbox_overrides_active:
		interval = interval / maxf(sandbox_powerup_frequency, 0.1)
	return interval

var preset_powerup_spawns: Array = []  # [{time: float, pos: Vector2, type: int}, ...]

# Co-evolution: if set, all spawned enemies use this neural network for AI control
var enemy_ai_network = null

func set_preset_events(obstacles: Array, enemy_spawns: Array, powerup_spawns: Array = []) -> void:
	## Use pre-generated events for deterministic gameplay.
	preset_obstacles = obstacles
	preset_enemy_spawns = enemy_spawns.duplicate()  # Copy so we can pop from it
	preset_powerup_spawns = powerup_spawns.duplicate()
	use_preset_events = true

static func generate_random_events(seed_value: int, p_curriculum_config: Dictionary = {}, sandbox_overrides: Dictionary = {}) -> Dictionary:
	return EventGenerator.generate(seed_value, p_curriculum_config, sandbox_overrides)

func _ready() -> void:
	if not rng:
		# Human mode: create unseeded RNG (random each run)
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if DisplayServer.get_name() != "headless":
		print("Evolve app started!")
	get_tree().paused = false

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

	# Check for command-line flags
	for arg in OS.get_cmdline_user_args():
		if arg == "--auto-train":
			call_deferred("_start_auto_training")
			return
		if arg == "--demo":
			call_deferred("_start_demo_playback")
			return

	# Show title screen on startup (only for root viewport / human play)
	if get_viewport() == get_tree().root and not training_mode:
		show_title_screen()
	else:
		# Training/test mode: start immediately
		game_started = true

func show_title_screen() -> void:
	## Show title screen and pause game.
	if not title_screen:
		return
	game_started = false
	game_over = false
	get_tree().paused = true
	# Hide all gameplay/game-over UI
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
	## Handle mode selection from the title screen.
	if mode == "sandbox":
		# Show sandbox config panel instead of starting game immediately
		_show_sandbox_panel()
		return

	if mode == "compare":
		# Show comparison config panel
		_show_comparison_panel()
		return

	game_started = true
	get_tree().paused = false
	# Show gameplay UI
	score_label.visible = true
	lives_label.visible = true
	scoreboard_label.visible = true
	if ai_status_label:
		ai_status_label.visible = true

	match mode:
		"play":
			# Already set up for human play
			pass
		"watch":
			if training_manager:
				training_manager.start_playback()
		"train":
			if training_manager:
				training_manager.start_training(100, 100)
		"coevolution":
			if training_manager:
				# Start training with co-evolution mode flag
				training_manager.start_training(100, 100)
		"rtneat":
			if training_manager:
				training_manager.start_rtneat({"agent_count": 30})
		"teams":
			if training_manager:
				training_manager.start_rtneat_teams({"team_size": 15})

func _show_game_over_stats() -> void:
	## Show the enhanced game over screen with stats.
	if not game_over_screen:
		return
	# Hide the old game over label
	game_over_label.visible = false
	name_entry.visible = false
	name_prompt.visible = false

	var mode_str := "play"
	if training_manager and training_manager.get_mode() == training_manager.Mode.PLAYBACK:
		mode_str = "watch"
	elif training_manager and training_manager.get_mode() == training_manager.Mode.ARCHIVE_PLAYBACK:
		mode_str = "archive"

	game_over_screen.show_stats({
		"score": score,
		"kills": kills,
		"powerups_collected": powerups_collected,
		"survival_time": survival_time,
		"score_from_kills": score_from_kills,
		"score_from_powerups": score_from_powerups,
		"is_high_score": score_mgr.is_high_score(int(score)),
		"mode": mode_str,
	})

func _on_game_over_restart() -> void:
	## Restart game from the game over screen.
	game_over_screen.hide_screen()
	get_tree().reload_current_scene()

func _on_game_over_menu() -> void:
	## Return to title screen from game over.
	game_over_screen.hide_screen()
	# Reset game state and show title
	get_tree().reload_current_scene()

func _show_sandbox_panel() -> void:
	## Show the sandbox configuration panel.
	if sandbox_panel:
		sandbox_panel.visible = true

func _on_sandbox_start(config: Dictionary) -> void:
	## Start sandbox mode with given configuration.
	sandbox_panel.visible = false
	game_started = true
	get_tree().paused = false
	# Show gameplay UI
	score_label.visible = true
	lives_label.visible = true
	scoreboard_label.visible = true
	if ai_status_label:
		ai_status_label.visible = true

	if training_manager:
		training_manager.start_sandbox(config)

func _on_sandbox_train(config: Dictionary) -> void:
	## Start full training using the current sandbox configuration.
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
	## Return to title screen from sandbox panel.
	sandbox_panel.visible = false
	show_title_screen()

func _show_comparison_panel() -> void:
	## Show the comparison configuration panel.
	if comparison_panel:
		comparison_panel.visible = true

func _on_comparison_start(strategies: Array) -> void:
	## Start comparison mode with selected strategies.
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
	## Return to title screen from comparison panel.
	comparison_panel.visible = false
	show_title_screen()

func _toggle_network_visualizer() -> void:
	## Toggle the network topology visualization.
	if not network_visualizer:
		return
	network_visualizer.visible = not network_visualizer.visible
	if network_visualizer.visible and training_manager:
		# Try to get the current network being played
		if training_manager.ai_controller and training_manager.ai_controller.network:
			var net = training_manager.ai_controller.network
			# Check if it's a NEAT network (duck-typed: has connection helpers)
			if net and net.has_method("get_connection_count"):
				# For NEAT, we'd need the genome too — for now just show the network
				network_visualizer.set_neat_data(null, net)
			else:
				network_visualizer.set_fixed_network(net)

func _toggle_phylogenetic_tree() -> void:
	## Toggle the phylogenetic lineage tree overlay.
	if not phylogenetic_tree:
		return
	phylogenetic_tree.panel_visible = not phylogenetic_tree.panel_visible
	phylogenetic_tree.visible = phylogenetic_tree.panel_visible

func _toggle_educational_mode() -> void:
	## Toggle the educational narration overlay.
	if not educational_overlay:
		return
	educational_overlay.visible = not educational_overlay.visible
	if educational_overlay.visible:
		# Auto-show sensor visualizer and network visualizer
		if sensor_visualizer and not sensor_visualizer.enabled:
			sensor_visualizer.toggle()
		if network_visualizer and not network_visualizer.visible:
			_toggle_network_visualizer()
	else:
		# Clear ray highlighting when disabling
		if sensor_visualizer:
			sensor_visualizer.highlighted_ray = -1

func _start_auto_training() -> void:
	## Start training automatically (for headless sweep runs)
	if training_manager:
		print("Auto-training started via command line")
		training_manager.start_training()

func _start_demo_playback() -> void:
	## Start AI playback directly, skipping the title screen (for .pck demos).
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
	## Return the object that owns adjust_speed() for the current mode, or null.
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

func _get_interactive_manager() -> Variant:
	## Return the active interactive manager (rtNEAT or Teams), or null.
	if not training_manager:
		return null
	var mode = training_manager.get_mode()
	if mode == training_manager.Mode.TEAMS and training_manager.team_mgr:
		return training_manager.team_mgr
	if mode == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
		return training_manager.rtneat_mgr
	return null

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	## Convert screen position to world position using arena camera.
	if arena_camera:
		return arena_camera.get_screen_center_position() + (screen_pos - get_viewport().get_visible_rect().size / 2.0) / arena_camera.zoom
	return screen_pos

func _handle_interactive_input(event: InputEvent, mgr) -> void:
	## Handle tool selection and click interactions for an interactive manager.
	# Tool selection keys (0-5)
	if event is InputEventKey and event.pressed:
		var ToolEnum = mgr.Tool
		match event.keycode:
			KEY_0: mgr.set_tool(ToolEnum.INSPECT)
			KEY_1: mgr.set_tool(ToolEnum.PLACE_OBSTACLE)
			KEY_2: mgr.set_tool(ToolEnum.REMOVE_OBSTACLE)
			KEY_3: mgr.set_tool(ToolEnum.SPAWN_WAVE)
			KEY_4: mgr.set_tool(ToolEnum.BLESS)
			KEY_5: mgr.set_tool(ToolEnum.CURSE)
			KEY_ESCAPE:
				mgr.set_tool(ToolEnum.INSPECT)
				mgr.clear_inspection()
				if mgr.overlay:
					mgr.overlay.hide_inspect()
				if network_visualizer:
					network_visualizer.visible = false

	# Click handling
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := _screen_to_world(event.position)

		if not mgr.handle_click(world_pos):
			var idx: int = mgr.get_agent_at_position(world_pos)
			if idx >= 0:
				var data: Dictionary = mgr.inspect_agent(idx)
				if mgr.overlay:
					mgr.overlay.show_inspect(data)
				if network_visualizer and data.has("genome") and data.has("network"):
					network_visualizer.set_neat_data(data.genome, data.network)
					network_visualizer.visible = true
			else:
				mgr.clear_inspection()
				if mgr.overlay:
					mgr.overlay.hide_inspect()
				if network_visualizer:
					network_visualizer.visible = false

func _unhandled_input(event: InputEvent) -> void:
	# Interactive mode input (shared by rtNEAT and Teams)
	var interactive_mgr = _get_interactive_manager()
	if interactive_mgr:
		_handle_interactive_input(event, interactive_mgr)

func _process(delta: float) -> void:
	# Handle AI training controls (always check these)
	if training_input_handler:
		training_input_handler.handle_training_input()

	# Sensor viz toggle (V key)
	if sensor_visualizer and Input.is_physical_key_pressed(KEY_V):
		if _key_just_pressed("sensor_viz"):
			sensor_visualizer.toggle()

	# Network viz toggle (N key)
	if network_visualizer and Input.is_physical_key_pressed(KEY_N):
		if _key_just_pressed("net_viz"):
			_toggle_network_visualizer()

	# Educational mode toggle (E key)
	if educational_overlay and Input.is_physical_key_pressed(KEY_E):
		if _key_just_pressed("edu_mode"):
			_toggle_educational_mode()

	# Phylogenetic tree toggle (Y key)
	if phylogenetic_tree and Input.is_physical_key_pressed(KEY_Y):
		if _key_just_pressed("phylo_tree"):
			_toggle_phylogenetic_tree()

	# Feed data to educational overlay each frame when visible
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

	# Feed data to phylogenetic tree when visible
	if phylogenetic_tree and phylogenetic_tree.visible and phylogenetic_tree.panel_visible and training_manager:
		if training_manager.lineage_tracker:
			var mode = training_manager.get_mode()
			var best_id: int = -1
			if mode == training_manager.Mode.TRAINING or mode == training_manager.Mode.COEVOLUTION:
				best_id = training_manager.lineage_tracker.get_best_id(training_manager.generation)
				# If current gen has no evaluated individuals yet, try previous gen
				if best_id < 0 and training_manager.generation > 0:
					best_id = training_manager.lineage_tracker.get_best_id(training_manager.generation - 1)
			elif mode == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
				# For rtNEAT, find the best across all tracked records
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

	if not game_started:
		return

	if game_over:
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
		return

	var score_multiplier = powerup_mgr.get_score_multiplier()
	score += delta * 5 * score_multiplier  # Reduced base survival (5 pts/sec)
	score_label.text = "Score: %d" % int(score)
	if ui_mgr:
		ui_mgr.update_ai_status_display()

	# Track survival time and award milestone bonuses
	survival_time += delta
	var current_milestone = int(survival_time / score_mgr.MILESTONE_INTERVAL)
	if current_milestone > last_milestone:
		var bonus = score_mgr.SURVIVAL_MILESTONE_BONUS * current_milestone
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
			next_powerup_score = score + _get_powerup_interval(80.0)
		elif spawn_powerup():
			next_powerup_score += _get_powerup_interval(80.0)
		else:
			next_powerup_score = score + _get_powerup_interval(20.0)

func get_difficulty_factor() -> float:
	return clampf(score / DIFFICULTY_SCALE_SCORE, 0.0, 1.0)

func calculate_proximity_bonus(delta: float) -> float:
	## Reward AI for being close to powerups (continuous shaping signal).
	return score_mgr.calculate_proximity_bonus(delta, player, self)

func get_scaled_enemy_speed() -> float:
	var factor = get_difficulty_factor()
	return lerpf(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, factor)

func get_scaled_spawn_interval() -> float:
	var factor = get_difficulty_factor()
	var interval = lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, factor)
	if sandbox_overrides_active:
		interval = interval / maxf(sandbox_spawn_rate_multiplier, 0.1)
	return interval

func spawn_enemy() -> void:
	spawn_mgr.spawn_enemy(training_mode, curriculum_config, get_difficulty_factor(), get_scaled_enemy_speed(), enemy_ai_network, powerup_mgr.freeze_active, powerup_mgr.slow_active)

func spawn_enemy_at(pos: Vector2, enemy_type: int) -> void:
	## Spawn enemy at specific position with specific type (for preset events).
	spawn_mgr.spawn_enemy_at(pos, enemy_type, get_scaled_enemy_speed(), training_mode, enemy_ai_network, powerup_mgr.freeze_active, powerup_mgr.slow_active)

func spawn_powerup_at(pos: Vector2, powerup_type: int) -> void:
	## Spawn powerup at specific position with specific type (for preset events).
	spawn_mgr.spawn_powerup_at(pos, powerup_type, MAX_POWERUPS, powerup_mgr.handle_powerup_collected)

func spawn_initial_enemies() -> void:
	spawn_mgr.spawn_initial_enemies(training_mode, BASE_ENEMY_SPEED, enemy_ai_network)

func count_local_powerups() -> int:
	return spawn_mgr.count_local_powerups()

func spawn_powerup() -> bool:
	return spawn_mgr.spawn_powerup(MAX_POWERUPS, powerup_mgr.handle_powerup_collected)

func find_valid_powerup_position() -> Vector2:
	return spawn_mgr.find_valid_powerup_position()

func _on_enemy_killed(pos: Vector2, points: int = 1) -> void:
	kills += 1
	var multiplier = powerup_mgr.get_score_multiplier()
	var bonus = points * score_mgr.KILL_MULTIPLIER * multiplier
	score += bonus
	score_from_kills += bonus
	var bonus_text = "+%d" % bonus
	spawn_floating_text(bonus_text, Color(1, 1, 0, 1), pos)

func spawn_floating_text(text: String, color: Color, pos: Vector2) -> void:
	var floating = floating_text_scene.instantiate()
	add_child(floating)
	floating.setup(text, color, pos)


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
			var bonus = score_mgr.SHOOT_TOWARD_ENEMY_BONUS
			score += bonus
			score_from_kills += bonus  # Count as kill-related
			return  # Only reward once per shot

func get_local_enemies() -> Array:
	return spawn_mgr.get_local_enemies()

func update_lives_display() -> void:
	lives_label.text = "Lives: %d" % lives

func _on_player_hit() -> void:
	if not game_started or game_over:
		return
	lives -= 1
	update_lives_display()

	# Show life lost indicator
	spawn_floating_text("-1 LIFE", Color(1, 0.2, 0.2, 1), player.position + Vector2(0, -30))

	if lives <= 0:
		game_over = true
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
		# Respawn player at arena center with brief invincibility
		var arena_center = Vector2(effective_arena_width / 2, effective_arena_height / 2)
		player.respawn(arena_center, RESPAWN_INVINCIBILITY)

func submit_high_score(player_name: String) -> void:
	score_mgr.submit_high_score(player_name, int(score))

	entering_name = false
	name_entry.visible = false
	name_prompt.visible = false
	game_over_label.visible = false
	scoreboard_label.text = score_mgr.get_scoreboard_text()

	# Show enhanced game over screen after name entry
	if game_over_screen and get_viewport() == get_tree().root:
		_show_game_over_stats()
	else:
		game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
		game_over_label.visible = true

var _ArenaSetup = preload("res://arena_setup.gd")

# Arena setup functions (delegated to ArenaSetup)
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

# AI Training functions
func setup_training_manager() -> void:
	# Don't setup training manager if we're inside a SubViewport (training instance)
	if get_viewport() != get_tree().root:
		return

	var TrainingManager = load("res://training_manager.gd")
	if not TrainingManager or not TrainingManager.can_instantiate():
		push_warning("TrainingManager script failed to load — skipping training setup")
		return
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

var _pressed_keys: Dictionary = {}

func _key_just_pressed(key_name: String) -> bool:
	if _pressed_keys.get(key_name, false):
		return false  # Already pressed
	_pressed_keys[key_name] = true
	# Reset after a short delay
	get_tree().create_timer(0.3).timeout.connect(func(): _pressed_keys[key_name] = false)
	return true

