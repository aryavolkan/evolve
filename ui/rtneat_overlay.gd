extends Control

## Overlay UI for rtNEAT mode.
## Shows stats bar, replacement log, species legend, controls hint.
## Click-to-inspect handled by rtneat_manager; this just displays the panel.

var _RtNeatPop = preload("res://ai/rtneat_population.gd")

var _stats: Dictionary = {}
var _log: Array = []
var _speed: float = 1.0
var _inspected_index: int = -1
var _inspect_data: Dictionary = {}
var _current_tool: int = 0  # RtNeatManager.Tool enum value
var _teams_mode: bool = false

# Cached font
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func update_display(stats: Dictionary, log: Array, speed: float, inspected: int, tool: int = 0) -> void:
	_stats = stats
	_log = log
	_speed = speed
	_inspected_index = inspected
	_current_tool = tool
	queue_redraw()


func update_teams_display(stats: Dictionary, log: Array, speed: float, inspected: int, tool: int = 0) -> void:
	_teams_mode = true
	_stats = stats
	_log = log
	_speed = speed
	_inspected_index = inspected
	_current_tool = tool
	queue_redraw()


func show_inspect(data: Dictionary) -> void:
	_inspect_data = data
	queue_redraw()


func hide_inspect() -> void:
	_inspect_data = {}
	_inspected_index = -1
	queue_redraw()


func _draw() -> void:
	if _stats.is_empty():
		return

	if _teams_mode:
		_draw_teams()
	else:
		_draw_standard()

	# Active tool indicator (below stats bar)
	var bar_height: float = 80.0 if _teams_mode else 65.0
	if _current_tool != 0:
		var tool_names := ["INSPECT", "PLACE", "REMOVE", "SPAWN", "BLESS", "CURSE"]
		var tool_colors := [Color.WHITE, Color(0.3, 0.9, 0.3), Color(0.9, 0.5, 0.2), Color(0.4, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.3)]
		var tool_name: String = tool_names[_current_tool] if _current_tool >= 0 and _current_tool < tool_names.size() else "?"
		var tool_color: Color = tool_colors[_current_tool] if _current_tool >= 0 and _current_tool < tool_colors.size() else Color.WHITE
		var tool_text := "Tool: %s" % tool_name
		var tw: float = 120.0
		var tx: float = 15.0
		var ty: float = bar_height + 5.0
		draw_rect(Rect2(tx, ty, tw, 22), Color(0.0, 0.0, 0.0, 0.7))
		draw_rect(Rect2(tx, ty, tw, 22), tool_color * Color(1, 1, 1, 0.6), false, 1.0)
		draw_string(_font, Vector2(tx + 8, ty + 16), tool_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tool_color)

	# Replacement log (bottom left)
	if not _log.is_empty():
		var log_y: float = size.y - 20.0 - (_log.size() - 1) * 18.0
		var log_bg_height: float = _log.size() * 18.0 + 10.0
		draw_rect(Rect2(0, log_y - 15, 500, log_bg_height), Color(0.0, 0.0, 0.0, 0.5))
		for i in _log.size():
			var entry: Dictionary = _log[i]
			var alpha: float = 1.0 - i * 0.15
			draw_string(_font, Vector2(10, log_y + i * 18.0), entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.6, alpha))

	# Inspect panel (bottom right)
	if not _inspect_data.is_empty():
		_draw_inspect_panel()


func _draw_teams() -> void:
	## Draw team battle mode stats.
	var bar_height: float = 80.0
	draw_rect(Rect2(0, 0, size.x, bar_height), Color(0.0, 0.0, 0.0, 0.7))

	var x: float = 15.0
	var fs: int = 14

	# Row 1: Title, total agents, speed
	var total: int = _stats.get("total_agents", 0)
	var alive: int = _stats.get("alive_count", 0)
	draw_string(_font, Vector2(x, 20), "TEAM BATTLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.8, 0.2))
	draw_string(_font, Vector2(x + 160, 20), "Agents: %d/%d" % [alive, total], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.9, 1.0))
	draw_string(_font, Vector2(x + 320, 20), "Speed: %.2fx" % _speed, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.5, 1.0, 0.5) if _speed > 1.0 else Color(0.7, 0.7, 0.7))

	var hint := "[0-5] Tools  [-/+] Speed  [H] Stop"
	draw_string(_font, Vector2(size.x - 380, 20), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5, 0.8))

	# Row 2: Team A (blue bar)
	var team_a: Dictionary = _stats.get("team_a", {})
	var a_alive: int = team_a.get("alive_count", 0)
	var a_total: int = team_a.get("agent_count", 0)
	var a_best: float = team_a.get("best_fitness", 0)
	var a_kills: int = _stats.get("team_a_pvp_kills", 0)
	var blue := Color(0.3, 0.5, 1.0)
	draw_rect(Rect2(x, 30, size.x - 30, 20), blue * Color(1, 1, 1, 0.15))
	draw_string(_font, Vector2(x + 5, 46), "Team A: %d/%d alive" % [a_alive, a_total], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, blue)
	draw_string(_font, Vector2(x + 200, 46), "Best: %.0f" % a_best, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 0.5))
	draw_string(_font, Vector2(x + 340, 46), "PvP Kills: %d" % a_kills, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.8, 0.8))

	# Row 3: Team B (red bar)
	var team_b: Dictionary = _stats.get("team_b", {})
	var b_alive: int = team_b.get("alive_count", 0)
	var b_total: int = team_b.get("agent_count", 0)
	var b_best: float = team_b.get("best_fitness", 0)
	var b_kills: int = _stats.get("team_b_pvp_kills", 0)
	var red := Color(1.0, 0.3, 0.3)
	draw_rect(Rect2(x, 52, size.x - 30, 20), red * Color(1, 1, 1, 0.15))
	draw_string(_font, Vector2(x + 5, 68), "Team B: %d/%d alive" % [b_alive, b_total], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, red)
	draw_string(_font, Vector2(x + 200, 68), "Best: %.0f" % b_best, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 0.5))
	draw_string(_font, Vector2(x + 340, 68), "PvP Kills: %d" % b_kills, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.8, 0.8))


func _draw_standard() -> void:
	## Draw standard rtNEAT overlay.
	var bar_height: float = 65.0
	draw_rect(Rect2(0, 0, size.x, bar_height), Color(0.0, 0.0, 0.0, 0.7))

	var x: float = 15.0
	var y1: float = 22.0
	var y2: float = 42.0
	var y3: float = 58.0
	var fs: int = 14

	var alive: int = _stats.get("alive_count", 0)
	var total: int = _stats.get("agent_count", 0)
	var species: int = _stats.get("species_count", 0)
	var best: float = _stats.get("best_fitness", 0)
	var atb: float = _stats.get("all_time_best", 0)
	var avg: float = _stats.get("avg_fitness", 0)
	var replacements: int = _stats.get("total_replacements", 0)

	draw_string(_font, Vector2(x, y1), "Agents: %d/%d" % [alive, total], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.9, 1.0))
	draw_string(_font, Vector2(x + 140, y1), "Species: %d" % species, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.8, 1.0))
	draw_string(_font, Vector2(x + 260, y1), "Best: %.0f" % best, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 0.5))
	draw_string(_font, Vector2(x + 380, y1), "All-time: %.0f" % atb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.8, 0.3))

	draw_string(_font, Vector2(x, y2), "Avg: %.0f" % avg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
	draw_string(_font, Vector2(x + 140, y2), "Replacements: %d" % replacements, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
	draw_string(_font, Vector2(x + 360, y2), "Speed: %.2fx" % _speed, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.5, 1.0, 0.5) if _speed > 1.0 else Color(0.7, 0.7, 0.7))

	var species_counts: Dictionary = _stats.get("species_counts", {})
	var legend_x: float = x
	for sid in species_counts:
		var count: int = species_counts[sid]
		var color: Color = _RtNeatPop.SPECIES_COLORS[int(sid) % _RtNeatPop.SPECIES_COLORS.size()]
		draw_rect(Rect2(legend_x, y3 - 10, 12, 12), color)
		draw_string(_font, Vector2(legend_x + 15, y3), "%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.6))
		legend_x += 40
		if legend_x > size.x - 200:
			break

	var hint := "[0-5] Tools  [-/+] Speed  [H] Stop"
	draw_string(_font, Vector2(size.x - 380, y1), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5, 0.8))



func _draw_inspect_panel() -> void:
	var panel_w: float = 260.0
	var panel_h: float = 180.0
	var px: float = size.x - panel_w - 15.0
	var py: float = size.y - panel_h - 15.0

	# Background
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.05, 0.05, 0.1, 0.9))
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.3, 0.4, 0.5, 0.6), false, 1.0)

	var lx: float = px + 12.0
	var ly: float = py + 22.0
	var gap: float = 20.0
	var fs: int = 13

	# Title with species color
	var sp_color: Color = _inspect_data.get("species_color", Color.WHITE)
	draw_rect(Rect2(lx, ly - 12, 14, 14), sp_color)
	draw_string(_font, Vector2(lx + 20, ly), "Agent #%d" % _inspect_data.get("agent_id", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	ly += gap + 4

	draw_string(_font, Vector2(lx, ly), "Species: %d" % _inspect_data.get("species_id", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.8, 1.0))
	ly += gap
	draw_string(_font, Vector2(lx, ly), "Fitness: %.0f" % _inspect_data.get("fitness", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 0.5))
	ly += gap
	draw_string(_font, Vector2(lx, ly), "Age: %.1fs" % _inspect_data.get("age", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
	ly += gap
	draw_string(_font, Vector2(lx, ly), "Lives: %d" % _inspect_data.get("lives", 0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.9, 0.5, 0.5) if _inspect_data.get("lives", 0) <= 1 else Color(0.7, 0.7, 0.7))
	ly += gap
	var nodes: int = _inspect_data.get("nodes", 0)
	var conns: int = _inspect_data.get("connections", 0)
	draw_string(_font, Vector2(lx, ly), "Network: %d nodes, %d conns" % [nodes, conns], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.6, 0.8, 0.6))
	ly += gap
	var status_text: String = "ALIVE" if _inspect_data.get("alive", true) else "DEAD"
	var status_color: Color = Color(0.3, 1.0, 0.3) if _inspect_data.get("alive", true) else Color(1.0, 0.3, 0.3)
	draw_string(_font, Vector2(lx, ly), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, status_color)
