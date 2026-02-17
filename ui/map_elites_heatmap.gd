extends Control
class_name MapElitesHeatmap

## Interactive 20×20 heatmap for the MAP-Elites quality-diversity archive.
## Cell color: empty = dark gray, occupied = green intensity ∝ fitness.
## Axes: X = kill rate, Y = collection rate.
## Clicking a cell emits cell_clicked with the bin coordinates.
##
## Uses the _draw() pattern from ParetoChart.

signal cell_clicked(bin: Vector2i)

# Data
var _grid: Array = []  # 2D array from MapElites.get_archive_grid()
var _grid_size: int = 20
var _max_fitness: float = 1.0  # For normalizing color intensity
var _behavior_mins: Vector2 = Vector2.ZERO
var _behavior_maxs: Vector2 = Vector2(0.5, 0.5)

# Layout constants
const MARGIN_LEFT := 55
const MARGIN_BOTTOM := 35
const MARGIN_TOP := 28
const MARGIN_RIGHT := 15
const CELL_GAP := 1  # Pixel gap between cells
const AXIS_LABEL_SIZE := 12
const TITLE_SIZE := 15

# Colors
const COLOR_BG := Color(0.08, 0.08, 0.12, 1.0)
const COLOR_EMPTY := Color(0.15, 0.15, 0.18, 1.0)
const COLOR_BORDER := Color(0.3, 0.3, 0.4, 1.0)
const COLOR_AXIS_LABEL := Color(0.6, 0.6, 0.6)
const COLOR_TITLE := Color.WHITE
const COLOR_HOVER := Color(1.0, 1.0, 1.0, 0.3)

# Hover state
var _hover_cell: Vector2i = Vector2i(-1, -1)


func set_data(grid: Array, grid_sz: int, max_fitness: float, behavior_mins: Vector2, behavior_maxs: Vector2) -> void:
	## Update the heatmap data. Call queue_redraw() automatically.
	_grid = grid
	_grid_size = grid_sz
	_max_fitness = maxf(max_fitness, 1.0)
	_behavior_mins = behavior_mins
	_behavior_maxs = behavior_maxs
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var new_hover := _screen_to_cell(event.position)
		if new_hover != _hover_cell:
			_hover_cell = new_hover
			queue_redraw()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _screen_to_cell(event.position)
		if cell.x >= 0 and cell.x < _grid_size and cell.y >= 0 and cell.y < _grid_size:
			cell_clicked.emit(cell)
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_cell = Vector2i(-1, -1)
		queue_redraw()


func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)

	var plot_rect := _get_plot_rect()
	draw_rect(plot_rect, Color(0.06, 0.06, 0.09, 1.0))
	draw_rect(plot_rect, COLOR_BORDER, false, 1.0)

	if _grid.is_empty() or _grid_size <= 0:
		_draw_empty()
		return

	var cell_w: float = (plot_rect.size.x - CELL_GAP * maxf(_grid_size - 1, 0)) / maxf(_grid_size, 1)
	var cell_h: float = (plot_rect.size.y - CELL_GAP * maxf(_grid_size - 1, 0)) / maxf(_grid_size, 1)

	# Draw cells
	for x in _grid_size:
		for y in _grid_size:
			var px: float = plot_rect.position.x + x * (cell_w + CELL_GAP)
			# Flip Y so row 0 is at bottom (low collection rate at bottom)
			var py: float = plot_rect.position.y + (_grid_size - 1 - y) * (cell_h + CELL_GAP)
			var rect := Rect2(px, py, cell_w, cell_h)

			var cell_data = null
			if x < _grid.size() and y < _grid[x].size():
				cell_data = _grid[x][y]

			if cell_data == null:
				draw_rect(rect, COLOR_EMPTY)
			else:
				var intensity: float = clampf(cell_data.fitness / _max_fitness, 0.05, 1.0)
				var color := Color(0.05, intensity * 0.9 + 0.1, 0.05, 1.0)
				draw_rect(rect, color)

			# Hover highlight
			if Vector2i(x, y) == _hover_cell:
				draw_rect(rect, COLOR_HOVER)

	# Axis labels
	_draw_axis_labels(plot_rect, cell_w, cell_h)

	# Title
	draw_string(
		ThemeDB.fallback_font,
		Vector2(MARGIN_LEFT + 4, MARGIN_TOP - 8),
		"MAP-Elites Archive", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, COLOR_TITLE
	)

	# Stats
	var occupied := 0
	for col in _grid:
		for cell in col:
			if cell != null:
				occupied += 1
	var total_cells := _grid_size * _grid_size
	var percentage := 0.0 if total_cells == 0 else float(occupied) / total_cells * 100
	var stats_text := "%d/%d cells  (%.0f%%)" % [occupied, total_cells, percentage]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 180, MARGIN_TOP - 8),
		stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_AXIS_LABEL
	)

	# Hover tooltip
	if _hover_cell.x >= 0 and _hover_cell.x < _grid_size and _hover_cell.y >= 0 and _hover_cell.y < _grid_size:
		var hcell = null
		if _hover_cell.x < _grid.size() and _hover_cell.y < _grid[_hover_cell.x].size():
			hcell = _grid[_hover_cell.x][_hover_cell.y]
		var tooltip_text: String
		if hcell == null:
			tooltip_text = "(%d, %d) — empty" % [_hover_cell.x, _hover_cell.y]
		else:
			tooltip_text = "(%d, %d) — fitness: %.0f" % [_hover_cell.x, _hover_cell.y, hcell.fitness]
		draw_string(
			ThemeDB.fallback_font,
			Vector2(MARGIN_LEFT + 4, size.y - 4),
			tooltip_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.YELLOW
		)


func _draw_empty() -> void:
	var msg := "No MAP-Elites data yet"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x / 2 - 80, size.y / 2),
		msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5)
	)


func _draw_axis_labels(plot_rect: Rect2, cell_w: float, cell_h: float) -> void:
	## Draw axis tick labels showing behavior values.
	var tick_count := 4  # Number of labeled ticks per axis

	var range_x: float = _behavior_maxs.x - _behavior_mins.x
	var range_y: float = _behavior_maxs.y - _behavior_mins.y
	if range_x <= 0:
		range_x = 1.0
	if range_y <= 0:
		range_y = 1.0

	for i in range(tick_count + 1):
		var t := float(i) / tick_count

		# X-axis (kill rate)
		var x_pos: float = plot_rect.position.x + t * plot_rect.size.x
		var x_val: float = lerpf(_behavior_mins.x, _behavior_maxs.x, t)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(x_pos - 10, plot_rect.position.y + plot_rect.size.y + 15),
			"%.2f" % x_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_AXIS_LABEL
		)

		# Y-axis (collection rate) — flipped so 0 is at bottom
		var y_pos: float = plot_rect.position.y + (1.0 - t) * plot_rect.size.y
		var y_val: float = lerpf(_behavior_mins.y, _behavior_maxs.y, t)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(2, y_pos + 4),
			"%.2f" % y_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_AXIS_LABEL
		)

	# Axis names
	draw_string(
		ThemeDB.fallback_font,
		Vector2(plot_rect.position.x + plot_rect.size.x / 2 - 25, size.y - 2),
		"Kill Rate", HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_SIZE, COLOR_AXIS_LABEL
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(1, MARGIN_TOP + 40),
		"Collect", HORIZONTAL_ALIGNMENT_LEFT, 50, AXIS_LABEL_SIZE, COLOR_AXIS_LABEL
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(1, MARGIN_TOP + 55),
		"Rate", HORIZONTAL_ALIGNMENT_LEFT, 50, AXIS_LABEL_SIZE, COLOR_AXIS_LABEL
	)


func _get_plot_rect() -> Rect2:
	return Rect2(
		MARGIN_LEFT, MARGIN_TOP,
		size.x - MARGIN_LEFT - MARGIN_RIGHT,
		size.y - MARGIN_TOP - MARGIN_BOTTOM
	)


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	## Convert a screen position to a grid cell coordinate.
	var plot_rect := _get_plot_rect()
	if not plot_rect.has_point(screen_pos) or _grid_size <= 0:
		return Vector2i(-1, -1)

	var rel_x: float = (screen_pos.x - plot_rect.position.x) / plot_rect.size.x
	var rel_y: float = (screen_pos.y - plot_rect.position.y) / plot_rect.size.y

	var cx: int = clampi(int(rel_x * _grid_size), 0, _grid_size - 1)
	# Flip Y: top of plot = high Y cell index
	var cy: int = clampi(_grid_size - 1 - int(rel_y * _grid_size), 0, _grid_size - 1)

	return Vector2i(cx, cy)
