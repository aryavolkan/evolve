class_name TeamsMode
extends TrainingModeBase

## TEAMS mode: two rtNEAT populations compete in team battle.

var teams_config: Dictionary = {}


func enter(context) -> void:
    super.enter(context)
    Engine.time_scale = 1.0

    # Initialize lineage tracker
    ctx.lineage_tracker = ctx.lineage_tracker_script.new()

    if not ctx.team_manager_script:
        ctx.team_manager_script = load("res://ai/team_manager.gd")
    ctx.team_mgr = ctx.team_manager_script.new()
    ctx.team_mgr.setup(ctx.main_scene, teams_config)

    if ctx.team_mgr.pop_a:
        ctx.team_mgr.pop_a.lineage = ctx.lineage_tracker
    if ctx.team_mgr.pop_b:
        ctx.team_mgr.pop_b.lineage = ctx.lineage_tracker

    # Hide the main player
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
        ctx.team_mgr.overlay = overlay_node
    else:
        push_error("Failed to find UI node for RtNeatOverlay")

    ctx.team_mgr.start()

    ctx.training_status_changed.emit("Team battle started")
    print("Team battle started: %d agents per team" % teams_config.get("team_size", 15))


func exit() -> void:
    if ctx.team_mgr:
        if ctx.team_mgr.pop_a:
            ctx.team_mgr.pop_a.save_best(ctx.best_network_path.replace(".nn", "_team_a.nn"))
        if ctx.team_mgr.pop_b:
            ctx.team_mgr.pop_b.save_best(ctx.best_network_path.replace(".nn", "_team_b.nn"))
        ctx.team_mgr.stop()
        ctx.team_mgr = null

    Engine.time_scale = 1.0

    ctx.player.visible = true
    ctx.player.set_physics_process(true)
    ctx.player.enable_ai_control(false)
    ctx.main_scene.training_mode = false

    ctx.training_status_changed.emit("Team battle stopped")


func process(delta: float) -> void:
    if ctx.team_mgr:
        ctx.team_mgr.process(delta)
