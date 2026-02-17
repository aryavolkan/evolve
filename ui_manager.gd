## Manages UI setup and status display
extends RefCounted
class_name UIManager

# References to main game systems
var main_game: Node2D
var training_manager: Node

# UI components references (managed by main_game)
var ai_status_label: Label

func setup(p_main_game: Node2D, p_training_manager: Node, p_ai_status_label: Label) -> void:
	"""Initialize the UI manager with references to game systems."""
	main_game = p_main_game
	training_manager = p_training_manager
	ai_status_label = p_ai_status_label

func setup_ui_screens() -> void:
	"""Create UI overlay screens (title, game over, sensor viz).
	Only set up for root viewport (not training sub-arenas)."""
	if main_game.get_viewport() != main_game.get_tree().root:
		return

	# Check UI container exists
	var ui_container = main_game.get_node_or_null("CanvasLayer/UI")
	if not ui_container:
		push_error("UI container not found at CanvasLayer/UI")
		return

	# Title screen
	var TitleScreenScript = preload("res://ui/title_screen.gd")
	main_game.title_screen = TitleScreenScript.new()
	main_game.title_screen.name = "TitleScreen"
	ui_container.add_child(main_game.title_screen)
	main_game.title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_game.title_screen.mode_selected.connect(main_game._on_title_mode_selected)
	main_game.title_screen.hide_menu()

	# Game over screen
	var GameOverScript = preload("res://ui/game_over_screen.gd")
	main_game.game_over_screen = GameOverScript.new()
	main_game.game_over_screen.name = "GameOverScreen"
	ui_container.add_child(main_game.game_over_screen)
	main_game.game_over_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_game.game_over_screen.hide_screen()
	main_game.game_over_screen.restart_requested.connect(main_game._on_game_over_restart)
	main_game.game_over_screen.menu_requested.connect(main_game._on_game_over_menu)

	# Sensor visualizer (child of main scene, draws in world space)
	var SensorVizScript = preload("res://ui/sensor_visualizer.gd")
	main_game.sensor_visualizer = SensorVizScript.new()
	main_game.sensor_visualizer.name = "SensorVisualizer"
	main_game.add_child(main_game.sensor_visualizer)
	main_game.sensor_visualizer.setup(main_game.player)
	main_game.sensor_visualizer.visible = false

	# Sandbox panel
	var SandboxPanelScript = preload("res://ui/sandbox_panel.gd")
	main_game.sandbox_panel = SandboxPanelScript.new()
	main_game.sandbox_panel.name = "SandboxPanel"
	ui_container.add_child(main_game.sandbox_panel)
	main_game.sandbox_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_game.sandbox_panel.visible = false
	main_game.sandbox_panel.start_requested.connect(main_game._on_sandbox_start)
	main_game.sandbox_panel.train_requested.connect(main_game._on_sandbox_train)
	main_game.sandbox_panel.back_requested.connect(main_game._on_sandbox_back)

	# Comparison panel
	var ComparisonPanelScript = preload("res://ui/comparison_panel.gd")
	main_game.comparison_panel = ComparisonPanelScript.new()
	main_game.comparison_panel.name = "ComparisonPanel"
	ui_container.add_child(main_game.comparison_panel)
	main_game.comparison_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_game.comparison_panel.visible = false
	main_game.comparison_panel.start_requested.connect(main_game._on_comparison_start)
	main_game.comparison_panel.back_requested.connect(main_game._on_comparison_back)

	# Network visualizer
	var NetworkVizScript = preload("res://ui/network_visualizer.gd")
	main_game.network_visualizer = NetworkVizScript.new()
	main_game.network_visualizer.name = "NetworkVisualizer"
	ui_container.add_child(main_game.network_visualizer)
	main_game.network_visualizer.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_game.network_visualizer.visible = false

	# Educational overlay
	var EduOverlayScript = preload("res://ui/educational_overlay.gd")
	main_game.educational_overlay = EduOverlayScript.new()
	main_game.educational_overlay.name = "EducationalOverlay"
	ui_container.add_child(main_game.educational_overlay)
	main_game.educational_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_game.educational_overlay.visible = false

	# Phylogenetic tree overlay
	var PhyloTreeScript = preload("res://ui/phylogenetic_tree.gd")
	main_game.phylogenetic_tree = PhyloTreeScript.new()
	main_game.phylogenetic_tree.name = "PhylogeneticTree"
	ui_container.add_child(main_game.phylogenetic_tree)
	main_game.phylogenetic_tree.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_game.phylogenetic_tree.visible = false

func update_ai_status_display() -> void:
	"""Update AI status display based on current training mode and stats."""
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
		if training_manager.get("rtneat_mgr"):
			var rtneat_mgr = training_manager.rtneat_mgr
			if rtneat_mgr and rtneat_mgr.get("population"):
				rtneat_stats = rtneat_mgr.population.get_stats()
		ai_status_label.text = "LIVE EVOLUTION | Agents: %d | Species: %d | Best: %.0f\n[H]=Stop [-/+]=Speed" % [
			rtneat_stats.get("alive_count", 0),
			rtneat_stats.get("species_count", 0),
			rtneat_stats.get("best_fitness", 0),
		]
		ai_status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	elif mode_str == "TEAMS":
		var team_stats = {}
		if training_manager.get("team_mgr"):
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