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
var spawn_mgr  # SpawnManager
var score_mgr  # ScoreManager

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

const POWERUP_DURATION: float = 5.0
const SLOW_MULTIPLIER: float = 0.5
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
	if spawn_mgr:
		spawn_mgr.effective_arena_width = effective_arena_width
		spawn_mgr.effective_arena_height = effective_arena_height

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

	# Initialize extracted managers
	score_mgr = load("res://score_manager.gd").new()
	spawn_mgr = load("res://spawn_manager.gd").new()
	spawn_mgr.setup(self, player, rng)
	spawn_mgr.effective_arena_width = effective_arena_width
	spawn_mgr.effective_arena_height = effective_arena_height

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
	setup_ui_screens()

	# Check for command-line flags
	for arg in OS.get_cmdline_user_args():
		if arg == "--auto-train":
			call_deferred("_start_auto_training")
			return
		if arg == "--demo":
			call_deferred("_start_demo_playback")
			return

	# Show title screen on startup (only for root viewport / human play)
	if get_viewport() == get_tree().root:
		show_title_screen()


func setup_ui_screens() -> void:
	## Create UI overlay screens (title, game over, sensor viz).
	## Only set up for root viewport (not training sub-arenas).
	if get_viewport() != get_tree().root:
		return

	# Title screen
	var TitleScreenScript = preload("res://ui/title_screen.gd")
	title_screen = TitleScreenScript.new()
	title_screen.name = "TitleScreen"
	$CanvasLayer/UI.add_child(title_screen)
	title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_screen.mode_selected.connect(_on_title_mode_selected)
	title_screen.hide_menu()

	# Game over screen
	var GameOverScript = preload("res://ui/game_over_screen.gd")
	game_over_screen = GameOverScript.new()
	game_over_screen.name = "GameOverScreen"
	$CanvasLayer/UI.add_child(game_over_screen)
	game_over_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_screen.hide_screen()
	game_over_screen.restart_requested.connect(_on_game_over_restart)
	game_over_screen.menu_requested.connect(_on_game_over_menu)

	# Sensor visualizer (child of main scene, draws in world space)
	var SensorVizScript = preload("res://ui/sensor_visualizer.gd")
	sensor_visualizer = SensorVizScript.new()
	sensor_visualizer.name = "SensorVisualizer"
	add_child(sensor_visualizer)
	sensor_visualizer.setup(player)
	sensor_visualizer.visible = false

	# Sandbox panel
	var SandboxPanelScript = preload("res://ui/sandbox_panel.gd")
	sandbox_panel = SandboxPanelScript.new()
	sandbox_panel.name = "SandboxPanel"
	$CanvasLayer/UI.add_child(sandbox_panel)
	sandbox_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sandbox_panel.visible = false
	sandbox_panel.start_requested.connect(_on_sandbox_start)
	sandbox_panel.back_requested.connect(_on_sandbox_back)

	# Comparison panel
	var ComparisonPanelScript = preload("res://ui/comparison_panel.gd")
	comparison_panel = ComparisonPanelScript.new()
	comparison_panel.name = "ComparisonPanel"
	$CanvasLayer/UI.add_child(comparison_panel)
	comparison_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	comparison_panel.visible = false
	comparison_panel.start_requested.connect(_on_comparison_start)
	comparison_panel.back_requested.connect(_on_comparison_back)

	# Network visualizer
	var NetworkVizScript = preload("res://ui/network_visualizer.gd")
	network_visualizer = NetworkVizScript.new()
	network_visualizer.name = "NetworkVisualizer"
	$CanvasLayer/UI.add_child(network_visualizer)
	network_visualizer.set_anchors_preset(Control.PRESET_FULL_RECT)
	network_visualizer.visible = false

	# Educational overlay
	var EduOverlayScript = preload("res://ui/educational_overlay.gd")
	educational_overlay = EduOverlayScript.new()
	educational_overlay.name = "EducationalOverlay"
	$CanvasLayer/UI.add_child(educational_overlay)
	educational_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	educational_overlay.visible = false

	# Phylogenetic tree overlay
	var PhyloTreeScript = preload("res://ui/phylogenetic_tree.gd")
	phylogenetic_tree = PhyloTreeScript.new()
	phylogenetic_tree.name = "PhylogeneticTree"
	$CanvasLayer/UI.add_child(phylogenetic_tree)
	phylogenetic_tree.set_anchors_preset(Control.PRESET_FULL_RECT)
	phylogenetic_tree.visible = false


func show_title_screen() -> void:
	## Show title screen and pause game.
	if not title_screen:
		return
	game_started = false
	get_tree().paused = true
	# Hide gameplay UI
	score_label.visible = false
	lives_label.visible = false
	scoreboard_label.visible = false
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
		"is_high_score": is_high_score(int(score)),
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
			# Check if it's a NEAT network (has _connections property)
			if net is NeatNetwork:
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


func _unhandled_input(event: InputEvent) -> void:
	# Team battle interactions
	if training_manager and training_manager.get_mode() == training_manager.Mode.TEAMS and training_manager.team_mgr:
		var mgr = training_manager.team_mgr

		# Tool selection keys (0-5)
		if event is InputEventKey and event.pressed:
			var TmTool = mgr.Tool
			match event.keycode:
				KEY_0: mgr.set_tool(TmTool.INSPECT)
				KEY_1: mgr.set_tool(TmTool.PLACE_OBSTACLE)
				KEY_2: mgr.set_tool(TmTool.REMOVE_OBSTACLE)
				KEY_3: mgr.set_tool(TmTool.SPAWN_WAVE)
				KEY_4: mgr.set_tool(TmTool.BLESS)
				KEY_5: mgr.set_tool(TmTool.CURSE)
				KEY_ESCAPE:
					mgr.set_tool(TmTool.INSPECT)
					mgr.clear_inspection()
					if mgr.overlay:
						mgr.overlay.hide_inspect()
					if network_visualizer:
						network_visualizer.visible = false

		# Click handling
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var world_pos: Vector2 = event.position
			if arena_camera:
				world_pos = arena_camera.get_screen_center_position() + (event.position - get_viewport().get_visible_rect().size / 2.0) / arena_camera.zoom

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

	# rtNEAT interactions
	if training_manager and training_manager.get_mode() == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
		var mgr = training_manager.rtneat_mgr

		# Tool selection keys (0-5)
		if event is InputEventKey and event.pressed:
			var RtTool = mgr.Tool
			match event.keycode:
				KEY_0: mgr.set_tool(RtTool.INSPECT)
				KEY_1: mgr.set_tool(RtTool.PLACE_OBSTACLE)
				KEY_2: mgr.set_tool(RtTool.REMOVE_OBSTACLE)
				KEY_3: mgr.set_tool(RtTool.SPAWN_WAVE)
				KEY_4: mgr.set_tool(RtTool.BLESS)
				KEY_5: mgr.set_tool(RtTool.CURSE)
				KEY_ESCAPE:
					mgr.set_tool(RtTool.INSPECT)
					mgr.clear_inspection()
					if mgr.overlay:
						mgr.overlay.hide_inspect()
					if network_visualizer:
						network_visualizer.visible = false

		# Click handling
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Convert screen position to world position
			var world_pos: Vector2 = event.position
			if arena_camera:
				world_pos = arena_camera.get_screen_center_position() + (event.position - get_viewport().get_visible_rect().size / 2.0) / arena_camera.zoom

			# Try tool action first; if not handled, fall through to inspect
			if not mgr.handle_click(world_pos):
				# Inspect mode: find agent at position
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


func _process(delta: float) -> void:
	# Handle AI training controls (always check these)
	handle_training_input()

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
			next_powerup_score = score + 80.0
		elif spawn_powerup():
			next_powerup_score += 80.0
		else:
			next_powerup_score = score + 20.0

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
	return lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, factor)

func spawn_enemy() -> void:
	spawn_mgr.spawn_enemy(training_mode, curriculum_config, get_difficulty_factor(), get_scaled_enemy_speed(), enemy_ai_network, freeze_active, slow_active)


func spawn_enemy_at(pos: Vector2, enemy_type: int) -> void:
	## Spawn enemy at specific position with specific type (for preset events).
	spawn_mgr.spawn_enemy_at(pos, enemy_type, get_scaled_enemy_speed(), training_mode, enemy_ai_network, freeze_active, slow_active)


func spawn_powerup_at(pos: Vector2, powerup_type: int) -> void:
	## Spawn powerup at specific position with specific type (for preset events).
	spawn_mgr.spawn_powerup_at(pos, powerup_type, MAX_POWERUPS, _on_powerup_collected)


func spawn_initial_enemies() -> void:
	spawn_mgr.spawn_initial_enemies(training_mode, BASE_ENEMY_SPEED, enemy_ai_network)


func count_local_powerups() -> int:
	return spawn_mgr.count_local_powerups()


func spawn_powerup() -> bool:
	return spawn_mgr.spawn_powerup(MAX_POWERUPS, _on_powerup_collected)


func find_valid_powerup_position() -> Vector2:
	return spawn_mgr.find_valid_powerup_position()

func _on_powerup_collected(type: String, collector: Node2D = null) -> void:
	# Route to the collector; fallback to main player for backward compat
	var target = collector if collector else player
	powerups_collected += 1
	show_powerup_message(type)

	# Bonus for collecting powerup
	var multiplier = 2 if double_points_active else 1
	var bonus = score_mgr.POWERUP_COLLECT_BONUS * multiplier
	score += bonus
	score_from_powerups += bonus
	var bonus_text = "+%d" % bonus
	spawn_floating_text(bonus_text, Color(0, 1, 0.5, 1), target.position)

	# Notify agent of powerup collection (for rtNEAT fitness tracking)
	if collector and collector != player and collector.has_signal("powerup_collected_by_agent"):
		collector.powerup_collected_by_agent.emit(collector, type)

	match type:
		"SPEED BOOST":
			target.activate_speed_boost(POWERUP_DURATION)
		"INVINCIBILITY":
			target.activate_invincibility(POWERUP_DURATION)
		"SLOW ENEMIES":
			activate_slow_enemies()
		"SCREEN CLEAR":
			clear_all_enemies()
		"RAPID FIRE":
			target.activate_rapid_fire(POWERUP_DURATION)
		"PIERCING":
			target.activate_piercing(POWERUP_DURATION)
		"SHIELD":
			target.activate_shield()
		"FREEZE":
			activate_freeze_enemies()
		"DOUBLE POINTS":
			activate_double_points()
		"BOMB":
			explode_nearby_enemies(target.position)

func _on_enemy_killed(pos: Vector2, points: int = 1) -> void:
	kills += 1
	var multiplier = 2 if double_points_active else 1
	var bonus = points * score_mgr.KILL_MULTIPLIER * multiplier
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
			var bonus = score_mgr.SHOOT_TOWARD_ENEMY_BONUS
			score += bonus
			score_from_kills += bonus  # Count as kill-related
			return  # Only reward once per shot


func activate_slow_enemies() -> void:
	# Apply slow to all current enemies if not already active
	if not slow_active:
		for enemy in get_local_enemies():
			enemy.apply_slow(SLOW_MULTIPLIER)
	slow_active = true
	if player.is_physics_processing():
		player.activate_slow_effect(POWERUP_DURATION)
	else:
		# rtNEAT mode: player physics disabled, use standalone timer
		get_tree().create_timer(POWERUP_DURATION).timeout.connect(end_slow_enemies)

func get_local_enemies() -> Array:
	return spawn_mgr.get_local_enemies()


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
	if player.is_physics_processing():
		player.activate_freeze_effect(POWERUP_DURATION)
	else:
		# rtNEAT mode: player physics disabled, use standalone timer
		get_tree().create_timer(POWERUP_DURATION).timeout.connect(end_freeze_enemies)


func end_freeze_enemies() -> void:
	if freeze_active:
		freeze_active = false
		for enemy in get_local_enemies():
			enemy.remove_freeze()


func activate_double_points() -> void:
	double_points_active = true
	if player.is_physics_processing():
		player.activate_double_points(POWERUP_DURATION)
	else:
		# rtNEAT mode: player physics disabled, use standalone timer
		get_tree().create_timer(POWERUP_DURATION).timeout.connect(end_double_points)


func end_double_points() -> void:
	double_points_active = false


func clear_all_enemies() -> void:
	if player.is_physics_processing():
		player.trigger_screen_clear_effect()
	var local_enemies = get_local_enemies()
	var total_points = 0
	for enemy in local_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			if enemy.has_method("get_point_value"):
				total_points += enemy.get_point_value() * score_mgr.KILL_MULTIPLIER
			else:
				total_points += score_mgr.KILL_MULTIPLIER
			enemy.die()

	# Bonus points for screen clear (scaled piece values + flat bonus)
	if total_points > 0:
		total_points += score_mgr.SCREEN_CLEAR_BONUS
		score += total_points
		spawn_floating_text("+%d CLEAR!" % total_points, Color(1, 0.3, 0.3, 1), player.position + Vector2(0, -50))

	# Prevent immediate respawning - set cooldown and advance spawn threshold
	screen_clear_cooldown = SCREEN_CLEAR_SPAWN_DELAY
	next_spawn_score = score + get_scaled_spawn_interval()


const BOMB_RADIUS: float = 600.0  # Radius of bomb explosion

func explode_nearby_enemies(center_pos: Vector2 = Vector2.ZERO) -> void:
	## Kill all enemies within BOMB_RADIUS of center_pos (defaults to player).
	if center_pos == Vector2.ZERO:
		center_pos = player.position
	var local_enemies = get_local_enemies()
	var total_points = 0
	var killed_count = 0

	for enemy in local_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			var distance = center_pos.distance_to(enemy.position)
			if distance <= BOMB_RADIUS:
				if enemy.has_method("get_point_value"):
					total_points += enemy.get_point_value() * score_mgr.KILL_MULTIPLIER
				else:
					total_points += score_mgr.KILL_MULTIPLIER
				killed_count += 1
				enemy.die()

	# Award points and show feedback
	if total_points > 0:
		var multiplier = 2 if double_points_active else 1
		total_points *= multiplier
		score += total_points
		score_from_kills += total_points
		spawn_floating_text("+%d BOMB!" % total_points, Color(1, 0.5, 0, 1), center_pos + Vector2(0, -50))


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

		# Use new game over screen if available (root viewport only)
		if game_over_screen and get_viewport() == get_tree().root:
			if is_high_score(int(score)):
				# Still need name entry for high scores
				entering_name = true
				game_over_label.text = "NEW HIGH SCORE!\nScore: %d" % int(score)
				game_over_label.visible = true
				name_prompt.visible = true
				name_entry.visible = true
				name_entry.text = ""
				name_entry.grab_focus()
			else:
				_show_game_over_stats()
		else:
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

# High score functions (delegated to ScoreManager)
func load_high_scores() -> void:
	score_mgr.load_high_scores()

func is_high_score(new_score: int) -> bool:
	return score_mgr.is_high_score(new_score)

func submit_high_score(player_name: String) -> void:
	score_mgr.submit_high_score(player_name, int(score))

	entering_name = false
	name_entry.visible = false
	name_prompt.visible = false
	game_over_label.visible = false
	update_scoreboard_display()

	# Show enhanced game over screen after name entry
	if game_over_screen and get_viewport() == get_tree().root:
		_show_game_over_stats()
	else:
		game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
		game_over_label.visible = true

func update_scoreboard_display() -> void:
	scoreboard_label.text = score_mgr.get_scoreboard_text()

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
		elif training_manager.get_mode() == training_manager.Mode.SANDBOX:
			training_manager.stop_sandbox()
		elif training_manager.get_mode() == training_manager.Mode.COMPARISON:
			training_manager.stop_comparison()
		elif training_manager.get_mode() == training_manager.Mode.RTNEAT:
			training_manager.stop_rtneat()
		elif training_manager.get_mode() == training_manager.Mode.TEAMS:
			training_manager.stop_rtneat_teams()

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

	# rtNEAT speed controls
	if training_manager.get_mode() == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
		var speed_down = Input.is_physical_key_pressed(KEY_BRACKETLEFT) or Input.is_physical_key_pressed(KEY_MINUS)
		var speed_up = Input.is_physical_key_pressed(KEY_BRACKETRIGHT) or Input.is_physical_key_pressed(KEY_EQUAL)

		if speed_down and not _speed_down_held:
			training_manager.rtneat_mgr.adjust_speed(-1.0)
		if speed_up and not _speed_up_held:
			training_manager.rtneat_mgr.adjust_speed(1.0)

		_speed_down_held = speed_down
		_speed_up_held = speed_up

	# Teams speed controls
	if training_manager.get_mode() == training_manager.Mode.TEAMS and training_manager.team_mgr:
		var speed_down = Input.is_physical_key_pressed(KEY_BRACKETLEFT) or Input.is_physical_key_pressed(KEY_MINUS)
		var speed_up = Input.is_physical_key_pressed(KEY_BRACKETRIGHT) or Input.is_physical_key_pressed(KEY_EQUAL)

		if speed_down and not _speed_down_held:
			training_manager.team_mgr.adjust_speed(-1.0)
		if speed_up and not _speed_up_held:
			training_manager.team_mgr.adjust_speed(1.0)

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
		ai_status_label.text = "PLAYBACK | Watching best AI\n[P]=Stop [H]=Human [V]=Sensors [N]=Network [E]=Educate [Y]=Lineage"
		ai_status_label.add_theme_color_override("font_color", Color.CYAN)
	elif mode_str == "GENERATION_PLAYBACK":
		ai_status_label.text = "GENERATION %d/%d\n[SPACE]=Next [G]=Restart [H]=Human" % [
			stats.get("playback_generation", 1),
			stats.get("max_playback_generation", 1)
		]
		ai_status_label.add_theme_color_override("font_color", Color.GREEN)
	elif mode_str == "RTNEAT":
		var rtneat_stats = {}
		if training_manager.rtneat_mgr:
			rtneat_stats = training_manager.rtneat_mgr.population.get_stats() if training_manager.rtneat_mgr.population else {}
		ai_status_label.text = "LIVE EVOLUTION | Agents: %d | Species: %d | Best: %.0f\n[H]=Stop [-/+]=Speed" % [
			rtneat_stats.get("alive_count", 0),
			rtneat_stats.get("species_count", 0),
			rtneat_stats.get("best_fitness", 0),
		]
		ai_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	elif mode_str == "TEAMS":
		var team_stats = {}
		if training_manager.team_mgr:
			team_stats = training_manager.team_mgr.get_stats()
		ai_status_label.text = "TEAM BATTLE | Agents: %d | PvP: A=%d B=%d\n[H]=Stop [-/+]=Speed" % [
			team_stats.get("total_agents", 0),
			team_stats.get("team_a_pvp_kills", 0),
			team_stats.get("team_b_pvp_kills", 0),
		]
		ai_status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	else:
		ai_status_label.text = "[T]=Train | [C]=CoEvo | [P]=Playback | [G]=Gen Play | [V]=Sensors [N]=Net [Y]=Lineage"
		ai_status_label.add_theme_color_override("font_color", Color.WHITE)
