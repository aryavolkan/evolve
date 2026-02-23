extends Control
class_name ParetoChart

## Interactive Pareto front scatter plot for multi-objective visualization.
## Displays population individuals as points with Pareto front highlighted.
##
## Axes can be toggled between 3 objective pairs:
##   Mode 0: X=Kills, Y=Survival (default)
##   Mode 1: X=Powerups, Y=Survival
##   Mode 2: X=Kills, Y=Powerups
## The third objective is encoded as point color intensity.

signal mode_changed(mode: int)

# Data
var _objectives: Array = []  # Array of Vector3 (survival, kills, powerups) for all individuals
var _pareto_indices: PackedInt32Array = PackedInt32Array()  # Indices of front-0 individuals

# Display mode (which 2 objectives to plot)
var _mode: int = 0
const MODE_COUNT := 3
const MODE_LABELS: Array[Dictionary] = [
    {"x": "Kill Score", "y": "Survival Time", "color": "Powerup Score"},
    {"x": "Powerup Score", "y": "Survival Time", "color": "Kill Score"},
    {"x": "Kill Score", "y": "Powerup Score", "color": "Survival Time"},
]

# Layout constants
const MARGIN_LEFT := 60
const MARGIN_BOTTOM := 40
const MARGIN_TOP := 30
const MARGIN_RIGHT := 20
const POINT_RADIUS := 4.0
const PARETO_POINT_RADIUS := 6.0
const AXIS_LABEL_SIZE := 13
const TITLE_SIZE := 16

# Colors
const COLOR_BG := Color(0.08, 0.08, 0.12, 1.0)
const COLOR_BORDER := Color(0.3, 0.3, 0.4, 1.0)
const COLOR_GRID := Color(0.2, 0.2, 0.25, 0.5)
const COLOR_AXIS_LABEL := Color(0.6, 0.6, 0.6)
const COLOR_TITLE := Color.WHITE
const COLOR_POINT_LOW := Color(0.3, 0.3, 0.5, 0.6)
const COLOR_POINT_HIGH := Color(0.2, 0.9, 0.9, 0.9)
const COLOR_PARETO_OUTLINE := Color.YELLOW
const COLOR_PARETO_LINE := Color(1.0, 0.85, 0.0, 0.5)


func set_data(objectives: Array, pareto_indices: Array = []) -> void:
    ## Set the population data to visualize.
    ## objectives: Array of Vector3 (survival_time, kill_score, powerup_score)
    ## pareto_indices: Array of int indices that are on the Pareto front
    _objectives = objectives
    _pareto_indices.clear()
    for idx in pareto_indices:
        if idx is int and idx >= 0:  # Validate index type and range
            _pareto_indices.append(idx)
    queue_redraw()


func set_mode(mode: int) -> void:
    ## Set which objective pair to display (0-2).
    _mode = clampi(mode, 0, MODE_COUNT - 1)
    mode_changed.emit(_mode)
    queue_redraw()


func cycle_mode() -> void:
    ## Cycle to the next display mode.
    set_mode((_mode + 1) % MODE_COUNT)


func get_mode() -> int:
    return _mode


func get_mode_label() -> Dictionary:
    return MODE_LABELS[_mode]


func _get_xy(obj: Vector3) -> Vector2:
    ## Extract the 2 plotted objectives based on current mode.
    match _mode:
        0: return Vector2(obj.y, obj.x)  # kills, survival
        1: return Vector2(obj.z, obj.x)  # powerups, survival
        2: return Vector2(obj.y, obj.z)  # kills, powerups
    return Vector2(obj.y, obj.x)


func _get_color_value(obj: Vector3) -> float:
    ## Extract the 3rd objective (used for color) based on current mode.
    match _mode:
        0: return obj.z  # powerups
        1: return obj.y  # kills
        2: return obj.x  # survival
    return obj.z


func _draw() -> void:
    if _objectives.is_empty():
        _draw_empty()
        return

    var plot_rect := _get_plot_rect()

    # Background
    draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
    draw_rect(plot_rect, Color(0.06, 0.06, 0.09, 1.0))
    draw_rect(plot_rect, COLOR_BORDER, false, 1.0)

    # Compute data ranges
    var x_range := Vector2(INF, -INF)
    var y_range := Vector2(INF, -INF)
    var c_range := Vector2(INF, -INF)

    for obj in _objectives:
        var xy := _get_xy(obj)
        var c := _get_color_value(obj)
        x_range.x = minf(x_range.x, xy.x)
        x_range.y = maxf(x_range.y, xy.x)
        y_range.x = minf(y_range.x, xy.y)
        y_range.y = maxf(y_range.y, xy.y)
        c_range.x = minf(c_range.x, c)
        c_range.y = maxf(c_range.y, c)

    # Ensure non-zero ranges
    if x_range.x >= x_range.y:
        x_range.y = x_range.x + 1.0
    if y_range.x >= y_range.y:
        y_range.y = y_range.x + 1.0
    if c_range.x >= c_range.y:
        c_range.y = c_range.x + 1.0

    # Add 5% padding to ranges
    var x_pad := (x_range.y - x_range.x) * 0.05
    var y_pad := (y_range.y - y_range.x) * 0.05
    x_range.x -= x_pad
    x_range.y += x_pad
    y_range.x -= y_pad
    y_range.y += y_pad

    # Draw grid lines and axis labels
    _draw_grid(plot_rect, x_range, y_range)

    # Draw non-Pareto points first (behind)
    var pareto_set := {}
    for idx in _pareto_indices:
        pareto_set[idx] = true

    for i in _objectives.size():
        if pareto_set.has(i):
            continue
        var xy := _get_xy(_objectives[i])
        var c := _get_color_value(_objectives[i])
        var screen_pos := _data_to_screen(xy, plot_rect, x_range, y_range)
        var t_denom := c_range.y - c_range.x
        var t := 0.5 if t_denom == 0.0 else (c - c_range.x) / t_denom  # Division by zero guard
        var color := COLOR_POINT_LOW.lerp(COLOR_POINT_HIGH, clampf(t, 0.0, 1.0))
        draw_circle(screen_pos, POINT_RADIUS, color)

    # Draw Pareto front line (connecting sorted front points)
    if _pareto_indices.size() > 1:
        var pareto_screen_points: Array[Vector2] = []
        for idx in _pareto_indices:
            if idx >= 0 and idx < _objectives.size():  # Proper bounds check
                var xy := _get_xy(_objectives[idx])
                pareto_screen_points.append(_data_to_screen(xy, plot_rect, x_range, y_range))

        # Sort by x position for line drawing
        if pareto_screen_points.size() > 1:  # Only draw if we have points
            pareto_screen_points.sort_custom(func(a, b): return a.x < b.x)

            for i in range(pareto_screen_points.size() - 1):
                draw_line(pareto_screen_points[i], pareto_screen_points[i + 1], COLOR_PARETO_LINE, 2.0, true)

    # Draw Pareto points on top
    for idx in _pareto_indices:
        if idx < 0 or idx >= _objectives.size():  # Proper bounds check
            continue
        var xy := _get_xy(_objectives[idx])
        var c := _get_color_value(_objectives[idx])
        var screen_pos := _data_to_screen(xy, plot_rect, x_range, y_range)
        var t_denom := c_range.y - c_range.x
        var t := 0.5 if t_denom == 0.0 else (c - c_range.x) / t_denom  # Division by zero guard
        var color := COLOR_POINT_LOW.lerp(COLOR_POINT_HIGH, clampf(t, 0.0, 1.0))
        draw_circle(screen_pos, PARETO_POINT_RADIUS, color)
        draw_arc(screen_pos, PARETO_POINT_RADIUS + 1.0, 0, TAU, 24, COLOR_PARETO_OUTLINE, 1.5, true)

    # Title and labels
    var labels := get_mode_label()
    _draw_title("%s vs %s (color: %s)" % [labels.x, labels.y, labels.color])
    _draw_axis_labels(labels.x, labels.y)

    # Mode hint
    var hint_text := "[Tab] Cycle view  (%d/%d)" % [_mode + 1, MODE_COUNT]
    draw_string(
        ThemeDB.fallback_font, Vector2(size.x - 200, MARGIN_TOP - 8),
        hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5)
    )

    # Pareto front count
    var front_text := "Front 0: %d / %d" % [_pareto_indices.size(), _objectives.size()]
    draw_string(
        ThemeDB.fallback_font, Vector2(MARGIN_LEFT + 8, MARGIN_TOP + 16),
        front_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR_PARETO_OUTLINE
    )


func _draw_empty() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
    var msg := "No multi-objective data (enable NSGA-II)"
    draw_string(
        ThemeDB.fallback_font,
        Vector2(size.x / 2 - 140, size.y / 2),
        msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.5, 0.5)
    )


func _get_plot_rect() -> Rect2:
    return Rect2(
        MARGIN_LEFT, MARGIN_TOP,
        size.x - MARGIN_LEFT - MARGIN_RIGHT,
        size.y - MARGIN_TOP - MARGIN_BOTTOM
    )


func _data_to_screen(data_point: Vector2, plot_rect: Rect2, x_range: Vector2, y_range: Vector2) -> Vector2:
    ## Convert data coordinates to screen pixel position within the plot area.
    var x_span := x_range.y - x_range.x
    var y_span := y_range.y - y_range.x
    var nx := 0.5 if x_span == 0.0 else clampf((data_point.x - x_range.x) / x_span, 0.0, 1.0)
    var ny := 0.5 if y_span == 0.0 else clampf((data_point.y - y_range.x) / y_span, 0.0, 1.0)
    return Vector2(
        plot_rect.position.x + nx * plot_rect.size.x,
        plot_rect.position.y + (1.0 - ny) * plot_rect.size.y  # Y inverted
    )


func _draw_grid(plot_rect: Rect2, x_range: Vector2, y_range: Vector2) -> void:
    ## Draw grid lines and axis value labels.
    var grid_count := 5

    for i in range(grid_count + 1):
        var t := float(i) / grid_count

        # Vertical grid lines
        var x_pos := plot_rect.position.x + t * plot_rect.size.x
        draw_line(
            Vector2(x_pos, plot_rect.position.y),
            Vector2(x_pos, plot_rect.position.y + plot_rect.size.y),
            COLOR_GRID, 1.0
        )
        var x_val := lerpf(x_range.x, x_range.y, t)
        draw_string(
            ThemeDB.fallback_font,
            Vector2(x_pos - 15, plot_rect.position.y + plot_rect.size.y + 18),
            _format_value(x_val), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_AXIS_LABEL
        )

        # Horizontal grid lines
        var y_pos := plot_rect.position.y + (1.0 - t) * plot_rect.size.y
        draw_line(
            Vector2(plot_rect.position.x, y_pos),
            Vector2(plot_rect.position.x + plot_rect.size.x, y_pos),
            COLOR_GRID, 1.0
        )
        var y_val := lerpf(y_range.x, y_range.y, t)
        draw_string(
            ThemeDB.fallback_font,
            Vector2(5, y_pos + 4),
            _format_value(y_val), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_AXIS_LABEL
        )


func _draw_title(text: String) -> void:
    draw_string(
        ThemeDB.fallback_font,
        Vector2(MARGIN_LEFT + 8, MARGIN_TOP - 8),
        text, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, COLOR_TITLE
    )


func _draw_axis_labels(x_label: String, y_label: String) -> void:
    # X-axis label (centered below)
    var plot_rect := _get_plot_rect()
    draw_string(
        ThemeDB.fallback_font,
        Vector2(plot_rect.position.x + plot_rect.size.x / 2 - 30, size.y - 4),
        x_label, HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_LABEL_SIZE, COLOR_AXIS_LABEL
    )

    # Y-axis label (rotated text not easily supported in _draw, so place vertically)
    # Use abbreviated text placed at top-left of Y axis
    draw_string(
        ThemeDB.fallback_font,
        Vector2(2, MARGIN_TOP + 35),
        y_label, HORIZONTAL_ALIGNMENT_LEFT, 55, AXIS_LABEL_SIZE, COLOR_AXIS_LABEL
    )


static func _format_value(v: float) -> String:
    if absf(v) >= 1000:
        return "%.0f" % v
    elif absf(v) >= 100:
        return "%.0f" % v
    elif absf(v) >= 10:
        return "%.1f" % v
    else:
        return "%.1f" % v


# ============================================================
# Static helpers for testing (no rendering needed)
# ============================================================

static func compute_axis_values(objectives: Array, mode: int) -> Dictionary:
    ## Extract x, y, color arrays from objectives for a given mode.
    ## Useful for testing data extraction without rendering.
    var x_vals: PackedFloat32Array = PackedFloat32Array()
    var y_vals: PackedFloat32Array = PackedFloat32Array()
    var c_vals: PackedFloat32Array = PackedFloat32Array()

    for obj in objectives:
        var v: Vector3 = obj
        match mode:
            0:  # kills vs survival, color=powerups
                x_vals.append(v.y)
                y_vals.append(v.x)
                c_vals.append(v.z)
            1:  # powerups vs survival, color=kills
                x_vals.append(v.z)
                y_vals.append(v.x)
                c_vals.append(v.y)
            2:  # kills vs powerups, color=survival
                x_vals.append(v.y)
                y_vals.append(v.z)
                c_vals.append(v.x)

    return {"x": x_vals, "y": y_vals, "color": c_vals}


static func compute_ranges(values: PackedFloat32Array) -> Vector2:
    ## Compute min/max range for an array of values.
    if values.is_empty():
        return Vector2(0, 1)
    var mn := INF
    var mx := -INF
    for v in values:
        mn = minf(mn, v)
        mx = maxf(mx, v)
    if mn >= mx:
        mx = mn + 1.0
    return Vector2(mn, mx)
