extends RefCounted
## Training pause overlay, graph visualization, and stats bar formatting.
## Extracted from training_manager.gd to reduce its responsibility.

signal heatmap_cell_clicked(cell: Vector2i)
signal replay_best_requested
signal training_exited  # When user presses SPACE on complete screen

var is_paused: bool = false
var training_complete: bool = false
var pause_overlay: Control = null

# Dependencies injected via setup()
var stats_tracker: RefCounted
var arena_pool: RefCounted


func setup(tracker: RefCounted, pool: RefCounted) -> void:
	stats_tracker = tracker
	arena_pool = pool


# ============================================================
# Pause control
# ============================================================

func toggle_pause(state: Dictionary, eval_instances: Array) -> void:
	## Toggle pause state. state contains scalars for display.
	## If training_complete, emits training_exited instead.
	if training_complete:
		training_exited.emit()
		return

	if is_paused:
		resume(eval_instances)
	else:
		pause(state, eval_instances)


func pause(state: Dictionary, eval_instances: Array) -> void:
	if is_paused:
		return

	is_paused = true
	for eval in eval_instances:
		if is_instance_valid(eval.viewport):
			eval.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(eval.scene):
			eval.scene.set_physics_process(false)
			eval.scene.set_process(false)
	_create_pause_overlay(state)
	print("Training paused")


func resume(eval_instances: Array) -> void:
	if not is_paused:
		return

	is_paused = false
	for eval in eval_instances:
		if is_instance_valid(eval.viewport):
			eval.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if is_instance_valid(eval.scene):
			eval.scene.set_physics_process(true)
			eval.scene.set_process(true)
	destroy_pause_overlay()
	print("Training resumed")


# ============================================================
# Training complete
# ============================================================

func show_complete(reason: String, state: Dictionary, eval_instances: Array) -> void:
	## Training finished — auto-replay best network (visual) or freeze evals (headless).
	print("Training complete: %s" % reason)
	training_complete = true

	# Visual mode: auto-replay best network fullscreen with topology viz
	if DisplayServer.get_name() != "headless":
		replay_best_requested.emit()
		return

	# Headless: freeze evals so metrics bridge detects completion
	is_paused = true
	for eval in eval_instances:
		if is_instance_valid(eval.viewport):
			eval.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(eval.scene):
			eval.scene.set_physics_process(false)
			eval.scene.set_process(false)


# ============================================================
# Stats display
# ============================================================

func update_training_stats(state: Dictionary) -> void:
	## Update the stats bar for standard training mode.
	## state keys: generation, current_eval_seed, evals_per_individual, evaluated_count,
	##   population_size, best_current, all_time_best, generations_without_improvement,
	##   stagnation_limit, curriculum_enabled, curriculum_label, use_nsga2, use_neat,
	##   use_map_elites, evolution, map_elites_archive, time_scale, fullscreen
	var seed_info = "seed %d/%d" % [state.current_eval_seed + 1, state.evals_per_individual]

	var controls_hint: String
	if state.get("fullscreen", false):
		controls_hint = "[Click/ESC]=Grid [-/+]=Speed [SPACE]=Pause [T]=Stop"
	else:
		controls_hint = "[Click]=Fullscreen [-/+]=Speed [SPACE]=Pause [T]=Stop"

	var curriculum_text = ""
	if state.get("curriculum_enabled", false):
		curriculum_text = " | %s" % state.get("curriculum_label", "")

	var nsga2_text = ""
	if state.get("use_nsga2", false):
		var front_size = state.get("pareto_front_size", 0)
		nsga2_text = " | NSGA-II (F0: %d)" % front_size

	var neat_text = ""
	if state.get("use_neat", false):
		neat_text = " | NEAT (Sp: %d, Ct: %.1f)" % [state.get("neat_species_count", 0), state.get("neat_compat_threshold", 0.0)]

	var me_text = ""
	if state.get("use_map_elites", false):
		me_text = " | ME: %d/%d" % [state.get("me_occupied", 0), state.get("me_total", 0)]

	arena_pool.set_stats_text("Gen %d (%s) | Progress: %d/%d | Best: %.0f | All-time: %.0f | Stagnant: %d/%d%s%s%s%s | Speed: %.1fx | %s" % [
		state.generation,
		seed_info,
		state.evaluated_count,
		state.population_size,
		state.best_current,
		state.all_time_best,
		state.generations_without_improvement,
		state.stagnation_limit,
		curriculum_text,
		nsga2_text,
		neat_text,
		me_text,
		state.time_scale,
		controls_hint
	])


func update_coevo_stats(state: Dictionary) -> void:
	## Update the stats bar for co-evolution training mode.
	## state keys: generation, current_eval_seed, evals_per_individual, evaluated_count,
	##   population_size, best_current, all_time_best, generations_without_improvement,
	##   stagnation_limit, coevo_is_hof_generation, curriculum_enabled, curriculum_label,
	##   enemy_best_str, hof_size, time_scale, fullscreen
	var seed_info = "seed %d/%d" % [state.current_eval_seed + 1, state.evals_per_individual]
	var hof_tag = " [HoF]" if state.get("coevo_is_hof_generation", false) else ""

	var controls_hint: String
	if state.get("fullscreen", false):
		controls_hint = "[Click/ESC]=Grid [-/+]=Speed [SPACE]=Pause [C]=Stop"
	else:
		controls_hint = "[Click]=Fullscreen [-/+]=Speed [SPACE]=Pause [C]=Stop"

	var curriculum_text = ""
	if state.get("curriculum_enabled", false):
		curriculum_text = " | %s" % state.get("curriculum_label", "")

	var hof_text = ""
	var hof_size = state.get("hof_size", 0)
	if hof_size > 0:
		hof_text = " | HoF: %d" % hof_size

	arena_pool.set_stats_text("COEVO Gen %d%s (%s) | Progress: %d/%d | P.Best: %.0f | P.All-time: %.0f | E.Best: %s%s%s | Stagnant: %d/%d | Speed: %.1fx | %s" % [
		state.generation, hof_tag, seed_info,
		state.evaluated_count, state.population_size,
		state.best_current, state.all_time_best,
		state.get("enemy_best_str", "?"), curriculum_text, hof_text,
		state.generations_without_improvement, state.stagnation_limit,
		state.time_scale, controls_hint
	])


# ============================================================
# Pause overlay with graphs
# ============================================================

func _create_pause_overlay(state: Dictionary) -> void:
	if pause_overlay:
		return

	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Semi-transparent background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.85)
	pause_overlay.add_child(bg)

	# Title
	var title = Label.new()
	title.text = "TRAINING PAUSED"
	title.position = Vector2(40, 30)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.YELLOW)
	pause_overlay.add_child(title)

	# Instructions
	var instructions = Label.new()
	instructions.text = "[SPACE] Resume  |  [T] Stop Training  |  [H] Human Mode"
	instructions.position = Vector2(40, 75)
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	pause_overlay.add_child(instructions)

	# Stats summary
	var stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.position = Vector2(40, 120)
	stats_label.add_theme_font_size_override("font_size", 18)
	stats_label.add_theme_color_override("font_color", Color.WHITE)
	stats_label.text = "Generation: %d\nBest Fitness: %.1f\nAll-time Best: %.1f\nAvg Fitness: %.1f\nStagnation: %d/%d" % [
		state.get("generation", 0),
		state.get("best_fitness", 0.0),
		state.get("all_time_best", 0.0),
		state.get("avg_fitness", 0.0),
		state.get("generations_without_improvement", 0),
		state.get("stagnation_limit", 10)
	]
	pause_overlay.add_child(stats_label)

	# Layout: if MAP-Elites active, split space between graph and heatmap
	var window_size = _get_window_size()
	var has_heatmap: bool = state.get("has_heatmap", false)

	if has_heatmap:
		# Left side: graph panel (60% width)
		var graph_panel = _create_graph_panel(window_size)
		var graph_w: float = (window_size.x - 100) * 0.58
		graph_panel.position = Vector2(40, 260)
		graph_panel.size = Vector2(graph_w, window_size.y - 320)
		pause_overlay.add_child(graph_panel)

		# Right side: MAP-Elites heatmap (40% width)
		var heatmap := MapElitesHeatmap.new()
		heatmap.name = "Heatmap"
		heatmap.position = Vector2(60 + graph_w, 260)
		heatmap.size = Vector2((window_size.x - 100) * 0.38, window_size.y - 320)
		heatmap.mouse_filter = Control.MOUSE_FILTER_STOP

		var heatmap_data: Dictionary = state.get("heatmap_data", {})
		heatmap.set_data(
			heatmap_data.get("grid", []),
			heatmap_data.get("grid_size", 20),
			heatmap_data.get("best_fitness", 0.0),
			heatmap_data.get("behavior_mins", Vector2.ZERO),
			heatmap_data.get("behavior_maxs", Vector2.ONE)
		)
		heatmap.cell_clicked.connect(_on_heatmap_cell_clicked)
		pause_overlay.add_child(heatmap)

		# Hint for heatmap clicks
		var click_hint = Label.new()
		click_hint.text = "Click a heatmap cell to watch that strategy play"
		click_hint.position = Vector2(60 + graph_w, 245)
		click_hint.add_theme_font_size_override("font_size", 12)
		click_hint.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
		pause_overlay.add_child(click_hint)
	else:
		# Full-width graph panel (no heatmap)
		var graph_panel = _create_graph_panel(window_size)
		graph_panel.position = Vector2(40, 260)
		pause_overlay.add_child(graph_panel)

	# Add to training canvas layer
	if arena_pool.canvas_layer:
		arena_pool.canvas_layer.add_child(pause_overlay)


func _on_heatmap_cell_clicked(cell: Vector2i) -> void:
	heatmap_cell_clicked.emit(cell)


func destroy_pause_overlay() -> void:
	if pause_overlay:
		pause_overlay.queue_free()
		pause_overlay = null


func _get_window_size() -> Vector2:
	return arena_pool.get_window_size() if arena_pool else Vector2(1280, 720)


func _create_graph_panel(window_size: Vector2) -> Control:
	var panel = Control.new()
	panel.name = "GraphPanel"

	var graph_width = window_size.x - 80
	var graph_height = window_size.y - 320

	# Graph background
	var graph_bg = ColorRect.new()
	graph_bg.size = Vector2(graph_width, graph_height)
	graph_bg.color = Color(0.1, 0.1, 0.15, 1)
	panel.add_child(graph_bg)

	# Graph border
	var border = ColorRect.new()
	border.size = Vector2(graph_width, graph_height)
	border.color = Color(0.3, 0.3, 0.4, 1)
	panel.add_child(border)

	var inner = ColorRect.new()
	inner.position = Vector2(2, 2)
	inner.size = Vector2(graph_width - 4, graph_height - 4)
	inner.color = Color(0.08, 0.08, 0.12, 1)
	panel.add_child(inner)

	# Graph title
	var graph_title = Label.new()
	graph_title.text = "Fitness Over Generations"
	graph_title.position = Vector2(10, 5)
	graph_title.add_theme_font_size_override("font_size", 16)
	graph_title.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(graph_title)

	# Legend
	var legend = _create_legend()
	legend.position = Vector2(graph_width - 450, 5)
	panel.add_child(legend)

	# Draw the graph lines
	var history_best: Array[float] = stats_tracker.history_best_fitness
	if history_best.size() > 1:
		var graph_area = Rect2(50, 35, graph_width - 70, graph_height - 60)
		var max_val = stats_tracker.get_max_history_value()
		var min_val = 0.0

		# Y-axis labels
		for i in range(5):
			var y_val = lerpf(min_val, max_val, 1.0 - float(i) / 4.0)
			var y_pos = graph_area.position.y + graph_area.size.y * (float(i) / 4.0)
			var y_label = Label.new()
			y_label.text = "%.0f" % y_val
			y_label.position = Vector2(5, y_pos - 8)
			y_label.add_theme_font_size_override("font_size", 12)
			y_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			panel.add_child(y_label)

			# Grid line
			var grid_line = ColorRect.new()
			grid_line.position = Vector2(graph_area.position.x, y_pos)
			grid_line.size = Vector2(graph_area.size.x, 1)
			grid_line.color = Color(0.2, 0.2, 0.25, 0.5)
			panel.add_child(grid_line)

		# X-axis labels
		var x_step = maxi(1, history_best.size() / 10)
		for i in range(0, history_best.size(), x_step):
			var x_pos = graph_area.position.x + graph_area.size.x * (float(i) / (history_best.size() - 1))
			var x_label = Label.new()
			x_label.text = "%d" % (i + 1)
			x_label.position = Vector2(x_pos - 10, graph_area.position.y + graph_area.size.y + 5)
			x_label.add_theme_font_size_override("font_size", 12)
			x_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			panel.add_child(x_label)

		# Draw lines using Line2D
		var best_line = _create_graph_line(history_best, graph_area, min_val, max_val, Color.GREEN)
		panel.add_child(best_line)

		var avg_line = _create_graph_line(stats_tracker.history_avg_fitness, graph_area, min_val, max_val, Color.YELLOW)
		panel.add_child(avg_line)

		var min_line = _create_graph_line(stats_tracker.history_min_fitness, graph_area, min_val, max_val, Color.RED)
		panel.add_child(min_line)

		if stats_tracker.history_avg_survival_score.size() > 1:
			var survival_line = _create_graph_line(stats_tracker.history_avg_survival_score, graph_area, min_val, max_val, Color.ORANGE)
			panel.add_child(survival_line)

		if stats_tracker.history_avg_kill_score.size() > 1:
			var kills_line = _create_graph_line(stats_tracker.history_avg_kill_score, graph_area, min_val, max_val, Color.CYAN)
			panel.add_child(kills_line)

		if stats_tracker.history_avg_powerup_score.size() > 1:
			var powerups_line = _create_graph_line(stats_tracker.history_avg_powerup_score, graph_area, min_val, max_val, Color.MAGENTA)
			panel.add_child(powerups_line)
	else:
		var no_data = Label.new()
		no_data.text = "Not enough data yet (need at least 2 generations)"
		no_data.position = Vector2(graph_width / 2 - 180, graph_height / 2)
		no_data.add_theme_font_size_override("font_size", 16)
		no_data.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		panel.add_child(no_data)

	return panel


func _create_legend() -> Control:
	var legend = Control.new()

	var items = [
		{"label": "Best", "color": Color.GREEN},
		{"label": "Avg", "color": Color.YELLOW},
		{"label": "Min", "color": Color.RED},
		{"label": "Surv$", "color": Color.ORANGE},
		{"label": "Kill$", "color": Color.CYAN},
		{"label": "Pwr$", "color": Color.MAGENTA}
	]

	var x_offset = 0
	for item in items:
		var color_box = ColorRect.new()
		color_box.position = Vector2(x_offset, 2)
		color_box.size = Vector2(12, 12)
		color_box.color = item.color
		legend.add_child(color_box)

		var label = Label.new()
		label.text = item.label
		label.position = Vector2(x_offset + 16, 0)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", item.color)
		legend.add_child(label)

		x_offset += 70

	return legend


func _create_graph_line(data: Array[float], area: Rect2, min_val: float, max_val: float, color: Color) -> Line2D:
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color
	line.antialiased = true

	var range_val = max_val - min_val
	if range_val <= 0:
		range_val = 1.0

	for i in data.size():
		var x = area.position.x + area.size.x * (float(i) / (data.size() - 1))
		var normalized = (data[i] - min_val) / range_val
		var y = area.position.y + area.size.y * (1.0 - normalized)
		line.add_point(Vector2(x, y))

	return line
