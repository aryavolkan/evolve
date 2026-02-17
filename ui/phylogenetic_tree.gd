extends Control

## Phylogenetic tree visualization — shows champion ancestry as a DAG.
## Toggle with Y key during training/playback.

var panel_visible: bool = false
var _tracker: RefCounted = null
var _best_id: int = -1

# Cached layout data
var _node_positions: Dictionary = {}  # {id: Vector2}
var _ancestry: Dictionary = {"nodes": [], "edges": []}
var _direct_ancestors: Dictionary = {}  # IDs on the direct parent_a chain

# Layout constants
const PANEL_WIDTH: float = 450.0
const PANEL_HEIGHT: float = 280.0
const PANEL_MARGIN: float = 10.0
const NODE_RADIUS: float = 6.0
const HEADER_HEIGHT: float = 24.0
const FOOTER_HEIGHT: float = 20.0

# Throttle redraws
var _redraw_timer: float = 0.0
const REDRAW_INTERVAL: float = 0.2  # 5 fps


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	if not visible or not panel_visible:
		return
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		queue_redraw()


func set_lineage_data(tracker: RefCounted, best_id: int) -> void:
	## Update tracker reference and best individual to trace.
	_tracker = tracker
	if best_id != _best_id and best_id >= 0:
		_best_id = best_id
		_recompute()


func _recompute() -> void:
	## Recompute ancestry and layout from tracker.
	if not _tracker or _best_id < 0:
		_ancestry = {"nodes": [], "edges": []}
		_node_positions.clear()
		_direct_ancestors.clear()
		return

	_ancestry = _tracker.get_ancestry(_best_id, 20)
	_compute_direct_chain()
	_compute_layout()


func _compute_direct_chain() -> void:
	## Walk parent_a chain from best to build the "main line" ancestors.
	_direct_ancestors.clear()
	if not _tracker:
		return
	var current: int = _best_id
	for i in 100:  # Safety limit
		_direct_ancestors[current] = true
		var rec: Dictionary = _tracker.get_record(current)
		if rec.is_empty() or rec.parent_a_id < 0:
			break
		current = rec.parent_a_id


func _compute_layout() -> void:
	## Assign x/y positions to each node.
	## x = generation column, y = spread within generation.
	_node_positions.clear()
	if _ancestry.nodes.is_empty():
		return

	# Group nodes by generation
	var gen_groups: Dictionary = {}  # {gen: [node_data, ...]}
	var min_gen: int = 999999
	var max_gen: int = -999999
	for node in _ancestry.nodes:
		var gen: int = node.generation
		if not gen_groups.has(gen):
			gen_groups[gen] = []
		gen_groups[gen].append(node)
		min_gen = mini(min_gen, gen)
		max_gen = maxi(max_gen, gen)

	if min_gen > max_gen:
		return

	var draw_area_x: float = PANEL_WIDTH - 80.0  # Left/right padding
	var draw_area_y: float = PANEL_HEIGHT - HEADER_HEIGHT - FOOTER_HEIGHT - 20.0
	var gen_span: int = max_gen - min_gen
	var x_step: float = draw_area_x / maxf(gen_span, 1)

	for gen in gen_groups:
		var group: Array = gen_groups[gen]
		var x: float = 40.0 + (gen - min_gen) * x_step
		var y_step: float = draw_area_y / maxf(group.size() + 1, 2)
		for i in group.size():
			var y: float = HEADER_HEIGHT + 10.0 + (i + 1) * y_step
			_node_positions[group[i].id] = Vector2(x, y)


func _draw() -> void:
	if not panel_visible or _ancestry.nodes.is_empty():
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_pos := Vector2(viewport_size.x - PANEL_WIDTH - PANEL_MARGIN, PANEL_MARGIN)

	# Background
	var bg_rect := Rect2(panel_pos, Vector2(PANEL_WIDTH, PANEL_HEIGHT))
	draw_rect(bg_rect, Color(0.05, 0.05, 0.1, 0.9))
	draw_rect(bg_rect, Color(0.3, 0.4, 0.6, 0.5), false, 1.0)

	# Header
	var header_font := ThemeDB.fallback_font
	var header_size := 14
	draw_string(header_font, panel_pos + Vector2(10, 18), "LINEAGE TREE", HORIZONTAL_ALIGNMENT_LEFT, -1, header_size, Color(0.8, 0.9, 1.0))
	draw_string(header_font, panel_pos + Vector2(PANEL_WIDTH - 70, 18), "[Y] Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.7))

	# Find fitness range for color mapping
	var min_fit: float = INF
	var max_fit: float = -INF
	for node in _ancestry.nodes:
		min_fit = minf(min_fit, node.fitness)
		max_fit = maxf(max_fit, node.fitness)
	if min_fit >= max_fit:
		max_fit = min_fit + 1.0

	# Draw edges
	for edge in _ancestry.edges:
		var from_pos = _node_positions.get(edge.from_id)
		var to_pos = _node_positions.get(edge.to_id)
		if from_pos == null or to_pos == null:
			continue
		var is_direct: bool = _direct_ancestors.has(edge.from_id) and _direct_ancestors.has(edge.to_id)
		var line_color: Color
		var line_width: float
		if is_direct:
			line_color = Color(1.0, 0.85, 0.3, 0.9)  # Gold for main chain
			line_width = 2.0
		else:
			line_color = Color(0.4, 0.4, 0.5, 0.4)
			line_width = 1.0
		draw_line(panel_pos + from_pos, panel_pos + to_pos, line_color, line_width)

	# Draw nodes
	for node in _ancestry.nodes:
		var pos = _node_positions.get(node.id)
		if pos == null:
			continue
		var fitness_t: float = clampf((node.fitness - min_fit) / (max_fit - min_fit), 0.0, 1.0)
		var node_color := Color(1.0 - fitness_t, fitness_t, 0.1)  # Red → Green

		if node.id == _best_id:
			# Star for best: larger, bright
			draw_circle(panel_pos + pos, NODE_RADIUS + 3, Color(1.0, 0.9, 0.2, 0.5))
			draw_circle(panel_pos + pos, NODE_RADIUS + 1, Color(1.0, 0.85, 0.1))
		elif _direct_ancestors.has(node.id):
			# Direct ancestor: filled circle
			draw_circle(panel_pos + pos, NODE_RADIUS, node_color)
		else:
			# Other ancestor: smaller
			draw_circle(panel_pos + pos, NODE_RADIUS - 2, node_color * Color(1, 1, 1, 0.6))

	# Legend and stats footer
	var foot_y: float = PANEL_HEIGHT - FOOTER_HEIGHT + 4
	var small_size := 10
	draw_string(header_font, panel_pos + Vector2(10, foot_y + 10), "★=Best", HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(1.0, 0.85, 0.1))
	draw_string(header_font, panel_pos + Vector2(65, foot_y + 10), "●=Ancestor", HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(0.5, 0.9, 0.3))
	draw_string(header_font, panel_pos + Vector2(145, foot_y + 10), "○=Other", HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(0.5, 0.5, 0.5))

	# Stats
	var best_fit: float = 0.0
	var rec: Dictionary = {}
	if _tracker and _tracker.has_method("get_record"):
		rec = _tracker.get_record(_best_id)
	if not rec.is_empty() and rec.has("fitness"):
		best_fit = rec.fitness
	var stats_text := "Best: %d  Ancestors: %d" % [int(best_fit), _ancestry.nodes.size()]
	draw_string(header_font, panel_pos + Vector2(210, foot_y + 10), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(0.6, 0.7, 0.8))
