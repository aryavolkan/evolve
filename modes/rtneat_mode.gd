extends TrainingModeBase
class_name RtNeatMode

## RTNEAT mode: continuous real-time neuroevolution.

var rtneat_config: Dictionary = {}


func enter(context) -> void:
	super.enter(context)
	Engine.time_scale = 1.0

	# Initialize lineage tracker
	ctx.lineage_tracker = ctx.LineageTrackerScript.new()

	var RtNeatManagerScript = load("res://ai/rtneat_manager.gd")
	ctx.rtneat_mgr = RtNeatManagerScript.new()
	ctx.rtneat_mgr.setup(ctx.main_scene, rtneat_config)

	if ctx.rtneat_mgr.population:
		ctx.rtneat_mgr.population.lineage = ctx.lineage_tracker

	# Hide the main player (agents replace it)
	ctx.player.visible = false
	ctx.player.set_physics_process(false)

	# Create overlay
	var RtNeatOverlayScript = load("res://ui/rtneat_overlay.gd")
	var overlay_node = RtNeatOverlayScript.new()
	overlay_node.name = "RtNeatOverlay"
	var ui_node = ctx.main_scene.get_node_or_null("CanvasLayer/UI")
	if ui_node:
		ui_node.add_child(overlay_node)
		overlay_node.set_anchors_preset(Control.PRESET_FULL_RECT)
		ctx.rtneat_mgr.overlay = overlay_node
	else:
		push_error("Failed to find UI node for RtNeatOverlay")

	ctx.rtneat_mgr.start()

	ctx.training_status_changed.emit("rtNEAT started")
	print("rtNEAT started: %d agents" % rtneat_config.get("agent_count", 30))


func exit() -> void:
	if ctx.rtneat_mgr:
		ctx.rtneat_mgr.population.save_best(ctx.BEST_NETWORK_PATH)
		ctx.rtneat_mgr.stop()
		ctx.rtneat_mgr = null

	Engine.time_scale = 1.0

	ctx.player.visible = true
	ctx.player.set_physics_process(true)
	ctx.player.enable_ai_control(false)
	ctx.main_scene.training_mode = false

	ctx.training_status_changed.emit("rtNEAT stopped")


func process(delta: float) -> void:
	if ctx.rtneat_mgr:
		ctx.rtneat_mgr.process(delta)
