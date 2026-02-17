extends Control

## Game over screen with detailed stats.
## Shows final score, time survived, kills breakdown, powerups collected.

signal restart_requested
signal menu_requested

const BG_COLOR := Color(0.02, 0.02, 0.06, 0.92)
const TITLE_COLOR := Color(1.0, 0.3, 0.3, 1.0)
const SCORE_COLOR := Color(1.0, 0.9, 0.3, 1.0)
const STAT_LABEL_COLOR := Color(0.6, 0.65, 0.7, 1.0)
const STAT_VALUE_COLOR := Color(0.9, 0.95, 1.0, 1.0)
const HINT_COLOR := Color(0.5, 0.55, 0.6, 0.8)

var stats: Dictionary = {}
# Expected keys: score, kills, powerups_collected, survival_time,
#                score_from_kills, score_from_powerups, is_high_score, mode


func show_stats(p_stats: Dictionary) -> void:
	stats = p_stats
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func hide_screen() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				hide_screen()
				restart_requested.emit()
			KEY_ESCAPE:
				hide_screen()
				menu_requested.emit()


func _draw() -> void:
	if not visible or stats.is_empty():
		return

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)

	var font := ThemeDB.fallback_font
	var cx: float = size.x / 2.0
	var y: float = size.y * 0.12

	# Title
	var title := "GAME OVER"
	if stats.get("is_high_score", false):
		title = "NEW HIGH SCORE!"
	draw_string(font, Vector2(cx - 120, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, TITLE_COLOR)
	y += 60

	# Final score
	var score_text := "Score: %d" % int(stats.get("score", 0))
	draw_string(font, Vector2(cx - 100, y), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, SCORE_COLOR)
	y += 55

	# Divider
	draw_line(Vector2(cx - 160, y), Vector2(cx + 160, y), Color(0.3, 0.35, 0.4, 0.6), 1.0)
	y += 25

	# Stats table
	var stat_rows: Array = [
		{"label": "Time Survived", "value": _format_time(stats.get("survival_time", 0.0))},
		{"label": "Enemies Killed", "value": str(stats.get("kills", 0))},
		{"label": "Score from Kills", "value": "%d" % int(stats.get("score_from_kills", 0))},
		{"label": "Powerups Collected", "value": str(stats.get("powerups_collected", 0))},
		{"label": "Score from Powerups", "value": "%d" % int(stats.get("score_from_powerups", 0))},
	]

	var label_x: float = cx - 150
	var value_x: float = cx + 80
	var row_h: float = 30.0

	for row in stat_rows:
		draw_string(font, Vector2(label_x, y), row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, STAT_LABEL_COLOR)
		draw_string(font, Vector2(value_x, y), row.value, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, STAT_VALUE_COLOR)
		y += row_h

	# Score breakdown bar
	y += 15
	_draw_score_bar(cx, y)
	y += 50

	# Mode-specific hint
	var mode: String = stats.get("mode", "play")
	var hint: String
	match mode:
		"watch", "archive":
			hint = "[SPACE] Replay    [ESC] Main Menu"
		_:
			hint = "[SPACE] Play Again    [ESC] Main Menu"

	draw_string(font, Vector2(cx - 140, y + 20), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, HINT_COLOR)


func _draw_score_bar(cx: float, y: float) -> void:
	var font := ThemeDB.fallback_font
	var total_score: float = maxf(stats.get("score", 1.0), 1.0)
	var kill_score: float = stats.get("score_from_kills", 0.0)
	var powerup_score: float = stats.get("score_from_powerups", 0.0)
	var survival_score: float = maxf(total_score - kill_score - powerup_score, 0.0)

	var bar_w: float = 320.0
	var bar_h: float = 18.0
	var bar_x: float = cx - bar_w / 2.0

	# Label
	draw_string(font, Vector2(bar_x, y - 5), "Score Breakdown", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, STAT_LABEL_COLOR)

	# Background
	draw_rect(Rect2(bar_x, y, bar_w, bar_h), Color(0.1, 0.1, 0.15, 1.0))

	# Segments
	var kill_w: float = clampf((kill_score / total_score) * bar_w, 0.0, bar_w)
	var powerup_w: float = clampf((powerup_score / total_score) * bar_w, 0.0, bar_w - kill_w)
	var surv_w: float = maxf(0.0, bar_w - kill_w - powerup_w)

	if kill_w > 0:
		draw_rect(Rect2(bar_x, y, kill_w, bar_h), Color(0.2, 0.7, 0.9, 1.0))
	if powerup_w > 0:
		draw_rect(Rect2(bar_x + kill_w, y, powerup_w, bar_h), Color(0.8, 0.2, 0.9, 1.0))
	if surv_w > 0:
		draw_rect(Rect2(bar_x + kill_w + powerup_w, y, surv_w, bar_h), Color(1.0, 0.6, 0.2, 1.0))

	# Legend
	var leg_y: float = y + bar_h + 12
	draw_rect(Rect2(bar_x, leg_y, 10, 10), Color(0.2, 0.7, 0.9, 1.0))
	draw_string(font, Vector2(bar_x + 14, leg_y + 10), "Kills", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, STAT_LABEL_COLOR)
	draw_rect(Rect2(bar_x + 70, leg_y, 10, 10), Color(0.8, 0.2, 0.9, 1.0))
	draw_string(font, Vector2(bar_x + 84, leg_y + 10), "Powerups", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, STAT_LABEL_COLOR)
	draw_rect(Rect2(bar_x + 160, leg_y, 10, 10), Color(1.0, 0.6, 0.2, 1.0))
	draw_string(font, Vector2(bar_x + 174, leg_y + 10), "Survival", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, STAT_LABEL_COLOR)


func _format_time(seconds: float) -> String:
	var mins: int = int(seconds) / 60
	var secs: int = int(seconds) % 60
	if mins > 0:
		return "%d:%02d" % [mins, secs]
	return "%.1fs" % seconds
