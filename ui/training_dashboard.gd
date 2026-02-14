extends Control
class_name TrainingDashboard

## Real-time training metrics dashboard overlaid on the training view.
## Shows fitness curves, score breakdowns, generation stats, and species count.
## Toggle with D key during training.

# Data source
var stats_tracker: RefCounted = null
var training_manager: Node = null

# Species history (tracked here since neat_evolution doesn't store it)
var _species_history: Array[int] = []

# Layout
const PANEL_W := 420.0
const PANEL_H := 320.0
const MARGIN := 10.0
const CHART_MARGIN_LEFT := 50.0
const CHART_MARGIN_BOTTOM := 20.0
const CHART_MARGIN_TOP := 18.0
const CHART_MARGIN_RIGHT := 10.0

# Colors
const COLOR_BG := Color(0.05, 0.05, 0.08, 0.85)
const COLOR_BORDER := Color(0.3, 0.3, 0.4, 0.8)
const COLOR_GRID := Color(0.2, 0.2, 0.25, 0.4)
const COLOR_TEXT := Color(0.8, 0.8, 0.8)
const COLOR_TEXT_DIM := Color(0.5, 0.5, 0.5)
const COLOR_BEST := Color(0.2, 1.0, 0.3)
const COLOR_AVG := Color(1.0, 1.0, 0.2)
const COLOR_MIN := Color(1.0, 0.3, 0.3)
const COLOR_KILL := Color(1.0, 0.4, 0.4)
const COLOR_POWERUP := Color(0.4, 1.0, 0.4)
const COLOR_SURVIVAL := Color(0.4, 0.6, 1.0)
const COLOR_SPECIES := Color(0.8, 0.5, 1.0)

const FONT_SIZE_TITLE := 14
const FONT_SIZE_LABEL := 11
const FONT_SIZE_STAT := 12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(tm: Node) -> void:
	training_manager = tm
	stats_tracker = tm.stats_tracker


func _process(_delta: float) -> void:
	if visible and stats_tracker:
		queue_redraw()


func update_species_count(count: int) -> void:
	_species_history.append(count)


func _draw() -> void:
	if not stats_tracker:
		return

	var window_size := get_viewport_rect().size
	var panel_origin := Vector2(window_size.x - PANEL_W - MARGIN, window_size.y - PANEL_H - MARGIN)

	# Background
	draw_rect(Rect2(panel_origin, Vector2(PANEL_W, PANEL_H)), COLOR_BG)
	draw_rect(Rect2(panel_origin, Vector2(PANEL_W, PANEL_H)), COLOR_BORDER, false, 1.0)

	var font := ThemeDB.fallback_font

	# Layout: top section = stats text, middle = fitness chart, bottom = score bars
	var x0 := panel_origin.x
	var y0 := panel_origin.y

	# --- Stats text (top) ---
	_draw_stats_text(font, x0 + 8, y0 + 4)

	# --- Fitness curve chart (middle) ---
	var chart_y := y0 + 42
	var chart_h := 110.0
	_draw_fitness_chart(font, x0, chart_y, PANEL_W, chart_h)

	# --- Score breakdown bars (bottom left) ---
	var bars_y := chart_y + chart_h + 8
	var bars_h := PANEL_H - (bars_y - y0) - 8
	var bars_w := PANEL_W * 0.6
	_draw_score_bars(font, x0, bars_y, bars_w, bars_h)

	# --- Species count (bottom right, if NEAT) ---
	if training_manager and training_manager.use_neat and _species_history.size() > 0:
		var sp_x := x0 + bars_w
		var sp_w := PANEL_W - bars_w
		_draw_species_chart(font, sp_x, bars_y, sp_w, bars_h)


func _draw_stats_text(font: Font, x: float, y: float) -> void:
	var gen := 0
	var pop := 0
	var best := 0.0
	var stage_label := ""

	if training_manager:
		gen = training_manager.generation
		pop = training_manager.population_size
		best = training_manager.all_time_best
		stage_label = training_manager.get_curriculum_label()

	var text := "Gen: %d  |  Pop: %d  |  Best: %.0f" % [gen, pop, best]
	if stage_label != "":
		text += "  |  %s" % stage_label

	draw_string(font, Vector2(x, y + FONT_SIZE_STAT + 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_STAT, COLOR_TEXT)

	# Legend line
	var ly := y + FONT_SIZE_STAT + 16
	var lx := x
	_draw_legend_item(font, lx, ly, COLOR_BEST, "Best")
	lx += 50
	_draw_legend_item(font, lx, ly, COLOR_AVG, "Avg")
	lx += 45
	_draw_legend_item(font, lx, ly, COLOR_MIN, "Min")
	lx += 45
	_draw_legend_item(font, lx, ly, COLOR_KILL, "Kill$")
	lx += 50
	_draw_legend_item(font, lx, ly, COLOR_POWERUP, "Pwr$")
	lx += 50
	_draw_legend_item(font, lx, ly, COLOR_SURVIVAL, "Surv$")


func _draw_legend_item(font: Font, x: float, y: float, color: Color, label: String) -> void:
	draw_line(Vector2(x, y - 3), Vector2(x + 12, y - 3), color, 2.0)
	draw_string(font, Vector2(x + 15, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)


func _draw_fitness_chart(font: Font, x0: float, y0: float, w: float, h: float) -> void:
	var best: Array = stats_tracker.history_best_fitness
	var avg: Array = stats_tracker.history_avg_fitness
	var mn: Array = stats_tracker.history_min_fitness

	var plot_x := x0 + CHART_MARGIN_LEFT
	var plot_y := y0 + CHART_MARGIN_TOP
	var plot_w := w - CHART_MARGIN_LEFT - CHART_MARGIN_RIGHT
	var plot_h := h - CHART_MARGIN_TOP - CHART_MARGIN_BOTTOM

	# Plot background
	draw_rect(Rect2(plot_x, plot_y, plot_w, plot_h), Color(0.04, 0.04, 0.06, 0.8))
	draw_rect(Rect2(plot_x, plot_y, plot_w, plot_h), COLOR_GRID, false, 1.0)

	if best.is_empty():
		draw_string(font, Vector2(plot_x + plot_w / 2 - 30, plot_y + plot_h / 2), "No data", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_LABEL, COLOR_TEXT_DIM)
		return

	# Auto-scale Y
	var y_max := 100.0
	for v in best:
		y_max = maxf(y_max, v)
	y_max = _nice_ceil(y_max)

	# Grid lines (4 horizontal)
	for i in 5:
		var t := float(i) / 4.0
		var gy := plot_y + plot_h * (1.0 - t)
		draw_line(Vector2(plot_x, gy), Vector2(plot_x + plot_w, gy), COLOR_GRID, 1.0)
		var val_text := "%.0f" % (y_max * t)
		draw_string(font, Vector2(x0 + 4, gy + 4), val_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_TEXT_DIM)

	# Draw lines
	_draw_line_series(best, plot_x, plot_y, plot_w, plot_h, y_max, COLOR_BEST)
	_draw_line_series(avg, plot_x, plot_y, plot_w, plot_h, y_max, COLOR_AVG)
	_draw_line_series(mn, plot_x, plot_y, plot_w, plot_h, y_max, COLOR_MIN)


func _draw_line_series(data: Array[float], px: float, py: float, pw: float, ph: float, y_max: float, color: Color) -> void:
	if data.size() < 2:
		return
	var count := data.size()
	var x_step := pw / maxf(count - 1, 1)
	for i in range(count - 1):
		var x1 := px + i * x_step
		var x2 := px + (i + 1) * x_step
		var y1 := py + ph * (1.0 - clampf(data[i] / y_max, 0.0, 1.0))
		var y2 := py + ph * (1.0 - clampf(data[i + 1] / y_max, 0.0, 1.0))
		draw_line(Vector2(x1, y1), Vector2(x2, y2), color, 1.5, true)


func _draw_score_bars(font: Font, x0: float, y0: float, w: float, h: float) -> void:
	var kill: Array = stats_tracker.history_avg_kill_score
	var pwr: Array = stats_tracker.history_avg_powerup_score
	var surv: Array = stats_tracker.history_avg_survival_score

	var plot_x := x0 + CHART_MARGIN_LEFT
	var plot_y := y0 + 2
	var plot_w := w - CHART_MARGIN_LEFT - CHART_MARGIN_RIGHT
	var plot_h := h - 4

	if kill.is_empty():
		return

	# Show last N generations as grouped bars
	var max_bars := 15
	var start_idx := maxi(0, kill.size() - max_bars)
	var count := kill.size() - start_idx

	# Find max for scaling
	var y_max := 100.0
	for i in range(start_idx, kill.size()):
		y_max = maxf(y_max, kill[i])
		if i < pwr.size():
			y_max = maxf(y_max, pwr[i])
		if i < surv.size():
			y_max = maxf(y_max, surv[i])
	y_max = _nice_ceil(y_max)

	var group_w := plot_w / maxf(count, 1)
	var bar_w := maxf(group_w / 4.0, 2.0)
	var gap := 1.0

	for i in count:
		var idx := start_idx + i
		var gx := plot_x + i * group_w

		# Kill bar
		var kill_val: float = kill[idx]
		var kh := plot_h * clampf(kill_val / y_max, 0.0, 1.0)
		draw_rect(Rect2(gx, plot_y + plot_h - kh, bar_w, kh), COLOR_KILL)

		# Powerup bar
		var pwr_val: float = pwr[idx] if idx < pwr.size() else 0.0
		var ph2 := plot_h * clampf(pwr_val / y_max, 0.0, 1.0)
		draw_rect(Rect2(gx + bar_w + gap, plot_y + plot_h - ph2, bar_w, ph2), COLOR_POWERUP)

		# Survival bar
		var surv_val: float = surv[idx] if idx < surv.size() else 0.0
		var sh := plot_h * clampf(surv_val / y_max, 0.0, 1.0)
		draw_rect(Rect2(gx + 2 * (bar_w + gap), plot_y + plot_h - sh, bar_w, sh), COLOR_SURVIVAL)

	# Baseline
	draw_line(Vector2(plot_x, plot_y + plot_h), Vector2(plot_x + plot_w, plot_y + plot_h), COLOR_GRID, 1.0)

	# Y-axis label
	draw_string(font, Vector2(x0 + 4, plot_y + 10), "%.0f" % y_max, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLOR_TEXT_DIM)


func _draw_species_chart(font: Font, x0: float, y0: float, w: float, h: float) -> void:
	var plot_x := x0 + 8
	var plot_y := y0 + 2
	var plot_w := w - 16
	var plot_h := h - 14

	draw_string(font, Vector2(plot_x, plot_y + 10), "Species", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_SPECIES)

	if _species_history.size() < 2:
		return

	var y_max := 1
	for v in _species_history:
		y_max = maxi(y_max, v)
	y_max += 1

	var chart_top := plot_y + 14
	var chart_h := plot_h - 14
	var count := _species_history.size()
	var x_step := plot_w / maxf(count - 1, 1)

	for i in range(count - 1):
		var x1 := plot_x + i * x_step
		var x2 := plot_x + (i + 1) * x_step
		var y1 := chart_top + chart_h * (1.0 - float(_species_history[i]) / y_max)
		var y2 := chart_top + chart_h * (1.0 - float(_species_history[i + 1]) / y_max)
		draw_line(Vector2(x1, y1), Vector2(x2, y2), COLOR_SPECIES, 1.5, true)

	# Current count label
	var current := _species_history[-1]
	draw_string(font, Vector2(plot_x + plot_w - 20, chart_top + 10), str(current), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_SPECIES)


static func _nice_ceil(v: float) -> float:
	if v <= 100:
		return 100.0
	elif v <= 500:
		return ceilf(v / 100.0) * 100.0
	elif v <= 5000:
		return ceilf(v / 500.0) * 500.0
	else:
		return ceilf(v / 1000.0) * 1000.0
