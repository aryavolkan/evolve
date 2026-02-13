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

# Cached font
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func update_display(stats: Dictionary, log: Array, speed: float, inspected: int) -> void:
	_stats = stats
	_log = log
	_speed = speed
	_inspected_index = inspected
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

	# Top stats bar background
	var bar_height: float = 65.0
	draw_rect(Rect2(0, 0, size.x, bar_height), Color(0.0, 0.0, 0.0, 0.7))

	var x: float = 15.0
	var y1: float = 22.0
	var y2: float = 42.0
	var y3: float = 58.0
	var fs: int = 14

	# Row 1: Agent count, species, best fitness, all-time best
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

	# Row 2: avg fitness, replacements, speed
	draw_string(_font, Vector2(x, y2), "Avg: %.0f" % avg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
	draw_string(_font, Vector2(x + 140, y2), "Replacements: %d" % replacements, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
	draw_string(_font, Vector2(x + 360, y2), "Speed: %.2fx" % _speed, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.5, 1.0, 0.5) if _speed > 1.0 else Color(0.7, 0.7, 0.7))

	# Row 3: Species legend (color swatches with counts)
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

	# Controls hint (top right)
	var hint := "[-/+] Speed  [Click] Inspect  [H] Stop"
	draw_string(_font, Vector2(size.x - 380, y1), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5, 0.8))

	# Replacement log (bottom left)
	if not _log.is_empty():
		var log_y: float = size.y - 20.0 - (_log.size() - 1) * 18.0
		var log_bg_height: float = _log.size() * 18.0 + 10.0
		draw_rect(Rect2(0, log_y - 15, 500, log_bg_height), Color(0.0, 0.0, 0.0, 0.5))
		for i in _log.size():
			var entry: Dictionary = _log[i]
			var alpha: float = 1.0 - i * 0.15  # Fade older entries
			draw_string(_font, Vector2(10, log_y + i * 18.0), entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.6, alpha))

	# Inspect panel (bottom right)
	if not _inspect_data.is_empty():
		_draw_inspect_panel()


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
