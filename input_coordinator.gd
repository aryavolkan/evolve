extends RefCounted
class_name InputCoordinator

## Handles interactive-mode input (rtNEAT/Teams tool selection and click interactions).

var main_game: Node2D
var network_visualizer: Control


func setup(p_main_game: Node2D) -> void:
	main_game = p_main_game
	network_visualizer = main_game.network_visualizer


func get_interactive_manager(training_manager) -> Variant:
	## Return the active interactive manager (rtNEAT or Teams), or null.
	if not training_manager:
		return null
	var mode = training_manager.get_mode()
	if mode == training_manager.Mode.TEAMS and training_manager.team_mgr:
		return training_manager.team_mgr
	if mode == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
		return training_manager.rtneat_mgr
	return null


func screen_to_world(screen_pos: Vector2) -> Vector2:
	## Convert screen position to world position using arena camera.
	var arena_camera = main_game.arena_camera
	if arena_camera:
		return arena_camera.get_screen_center_position() + (screen_pos - main_game.get_viewport().get_visible_rect().size / 2.0) / arena_camera.zoom
	return screen_pos


func handle_interactive_input(event: InputEvent, mgr) -> void:
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
		var world_pos := screen_to_world(event.position)

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
