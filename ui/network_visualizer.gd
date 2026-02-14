extends Control
class_name NetworkVisualizer

## Real-time neural network topology visualization.
## Renders NEAT variable-topology networks as directed graphs with live activations.
##
## Nodes: positioned in layers (input → hidden → output)
##   - Color: blue (negative), white (zero), red (positive activation)
##   - Size: proportional to importance (connections count)
##
## Connections: drawn between nodes
##   - Thickness: proportional to weight magnitude
##   - Color: green (positive), red (negative)
##
## For fixed-topology networks: fixed column layout (input, hidden, output).
## Updates throttled to ~10fps for performance.

signal closed

# Layout
const MARGIN := 20.0
const NODE_RADIUS := 8.0
const NODE_RADIUS_INPUT := 5.0
const NODE_RADIUS_OUTPUT := 10.0
const MAX_CONNECTION_WIDTH := 3.0
const MIN_CONNECTION_WIDTH := 0.5
const LAYER_GAP := 0.25  # Fraction of width per layer

# Colors
const BG_COLOR := Color(0.06, 0.06, 0.1, 0.95)
const BORDER_COLOR := Color(0.25, 0.3, 0.4, 0.6)
const LABEL_COLOR := Color(0.6, 0.65, 0.7)
const TITLE_COLOR := Color(0.8, 0.85, 0.9)
const CONN_POSITIVE := Color(0.2, 0.8, 0.3, 0.6)
const CONN_NEGATIVE := Color(0.8, 0.2, 0.2, 0.6)
const CONN_DISABLED := Color(0.3, 0.3, 0.3, 0.2)

# Data (NEAT)
var _neat_genome: RefCounted = null  # NeatGenome
var _neat_network: RefCounted = null  # NeatNetwork
var _node_positions: Dictionary = {}  # node_id → Vector2 (screen coords)
var _node_types: Dictionary = {}  # node_id → 0=input, 1=hidden, 2=output

# Data (fixed topology)
var _fixed_network: RefCounted = null  # NeuralNetwork

# Throttling
var _redraw_timer: float = 0.0
const REDRAW_INTERVAL := 0.1  # ~10fps


func set_neat_data(genome: RefCounted, network: RefCounted) -> void:
	## Set a NEAT genome and its compiled network for visualization.
	_neat_genome = genome
	_neat_network = network
	_fixed_network = null
	_compute_layout()
	queue_redraw()


func set_fixed_network(network: RefCounted) -> void:
	## Set a fixed-topology network for visualization.
	_fixed_network = network
	_neat_genome = null
	_neat_network = null
	_compute_fixed_layout()
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_N:
			closed.emit()
			visible = false


func _compute_layout() -> void:
	## Compute node positions for NEAT network.
	_node_positions.clear()
	_node_types.clear()

	if not _neat_genome and not _neat_network:
		return

	var plot_rect := _get_plot_rect()

	# Categorize nodes by type
	var inputs: Array = []
	var hidden: Array = []
	var outputs: Array = []

	if _neat_genome:
		for node in _neat_genome.node_genes:
			_node_types[node.id] = node.type
			match node.type:
				0: inputs.append(node.id)
				1: hidden.append(node.id)
				2: outputs.append(node.id)
	elif _neat_network:
		for node_id in _neat_network._input_ids:
			inputs.append(node_id)
			_node_types[node_id] = 0
		for node_id in _neat_network._output_ids:
			outputs.append(node_id)
			_node_types[node_id] = 2
		for node_id in _neat_network._node_order:
			if _node_types.has(node_id):
				continue
			hidden.append(node_id)
			_node_types[node_id] = 1

	# Assign x positions by layer
	var num_layers: int = 2 + (1 if hidden.size() > 0 else 0)

	# If there are hidden nodes, try to assign depth based on connectivity
	var node_depths: Dictionary = {}  # node_id → 0.0 to 1.0
	for id in inputs:
		node_depths[id] = 0.0
	for id in outputs:
		node_depths[id] = 1.0

	var connections: Array = []
	if _neat_genome:
		connections = _neat_genome.connection_genes
	elif _neat_network:
		connections = _neat_network._connections

	if hidden.size() > 0:
		# Simple depth assignment: average of connected inputs/outputs
		# Do multiple passes for convergence
		for h_id in hidden:
			node_depths[h_id] = 0.5  # Start in the middle

		for _pass in range(3):
			for h_id in hidden:
				var total_depth: float = 0.0
				var count: int = 0
				for conn in connections:
					if _neat_genome and not conn.enabled:
						continue
					var in_id: int = conn.in_id if _neat_genome else int(conn.get("in_id", -1))
					var out_id: int = conn.out_id if _neat_genome else int(conn.get("out_id", -1))
					if out_id == h_id and node_depths.has(in_id):
						total_depth += node_depths[in_id]
						count += 1
					if in_id == h_id and node_depths.has(out_id):
						total_depth += node_depths[out_id]
						count += 1
				if count > 0:
					node_depths[h_id] = clampf(total_depth / count, 0.1, 0.9)

	# Position nodes
	var _place_layer = func(nodes: Array, depth: float, start_y: float, end_y: float) -> void:
		if nodes.is_empty():
			return
		var x_pos: float = plot_rect.position.x + depth * plot_rect.size.x
		var spacing: float = (end_y - start_y) / maxf(nodes.size() + 1, 2)
		for i in nodes.size():
			var y_pos: float = start_y + spacing * (i + 1)
			_node_positions[nodes[i]] = Vector2(x_pos, y_pos)

	# Place input and output layers
	_place_layer.call(inputs, 0.0, plot_rect.position.y, plot_rect.end.y)
	_place_layer.call(outputs, 1.0, plot_rect.position.y, plot_rect.end.y)

	# Place hidden nodes at their computed depths, spread vertically
	if hidden.size() > 0:
		# Group hidden nodes by approximate depth for vertical spacing
		hidden.sort_custom(func(a, b): return node_depths.get(a, 0.5) < node_depths.get(b, 0.5))
		for i in hidden.size():
			var depth: float = node_depths.get(hidden[i], 0.5)
			var x_pos: float = plot_rect.position.x + depth * plot_rect.size.x
			var spread: float = plot_rect.size.y * 0.8
			var start_y: float = plot_rect.position.y + plot_rect.size.y * 0.1
			var spacing: float = spread / maxf(hidden.size() + 1, 2)
			_node_positions[hidden[i]] = Vector2(x_pos, start_y + spacing * (i + 1))


func _compute_fixed_layout() -> void:
	## Compute node positions for fixed-topology network.
	_node_positions.clear()
	_node_types.clear()

	if not _fixed_network:
		return

	var plot_rect := _get_plot_rect()
	var input_size: int = _fixed_network.input_size
	var hidden_size: int = _fixed_network.hidden_size
	var output_size: int = _fixed_network.output_size

	# For fixed networks, limit displayed input nodes to avoid clutter
	var display_inputs: int = mini(input_size, 20)
	var input_skip: int = maxi(1, input_size / display_inputs)

	# Input layer
	var input_spacing: float = plot_rect.size.y / (display_inputs + 1)
	for i in display_inputs:
		var node_id: int = i * input_skip
		_node_positions[node_id] = Vector2(plot_rect.position.x, plot_rect.position.y + input_spacing * (i + 1))
		_node_types[node_id] = 0

	# Hidden layer
	var display_hidden: int = mini(hidden_size, 20)
	var hidden_skip: int = maxi(1, hidden_size / display_hidden)
	var hidden_spacing: float = plot_rect.size.y / (display_hidden + 1)
	for i in display_hidden:
		var node_id: int = input_size + i * hidden_skip
		_node_positions[node_id] = Vector2(plot_rect.position.x + plot_rect.size.x * 0.5, plot_rect.position.y + hidden_spacing * (i + 1))
		_node_types[node_id] = 1

	# Output layer
	var output_spacing: float = plot_rect.size.y / (output_size + 1)
	for i in output_size:
		var node_id: int = input_size + hidden_size + i
		_node_positions[node_id] = Vector2(plot_rect.end.x, plot_rect.position.y + output_spacing * (i + 1))
		_node_types[node_id] = 2


func _draw() -> void:
	if not visible:
		return

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)

	var plot_rect := _get_plot_rect()
	draw_rect(plot_rect, Color(0.04, 0.04, 0.07, 1.0))
	draw_rect(plot_rect, BORDER_COLOR, false, 1.0)

	var font := ThemeDB.fallback_font

	if _neat_genome:
		_draw_neat_network(font)
	elif _fixed_network:
		_draw_fixed_network(font)
	else:
		draw_string(font, Vector2(size.x / 2 - 60, size.y / 2), "No network loaded", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, LABEL_COLOR)
		return

	# Title
	var net_type := "NEAT" if _neat_genome else "Fixed"
	var node_count := _node_positions.size()
	var title_text := "Network Topology (%s, %d nodes)" % [net_type, node_count]
	draw_string(font, Vector2(MARGIN + 5, MARGIN + 12), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TITLE_COLOR)

	# Layer labels
	draw_string(font, Vector2(plot_rect.position.x - 5, plot_rect.end.y + 15), "Input", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LABEL_COLOR)
	draw_string(font, Vector2(plot_rect.end.x - 25, plot_rect.end.y + 15), "Output", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LABEL_COLOR)

	# Hint
	draw_string(font, Vector2(MARGIN + 5, size.y - 8), "[N] or [ESC] Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LABEL_COLOR)


func _draw_neat_network(font: Font) -> void:
	## Draw NEAT network with live activations.
	if not _neat_genome or _node_positions.is_empty():
		return

	# Get live activations if network is available
	var activations: Dictionary = {}
	if _neat_network and _neat_network.has_method("get_node_count"):
		activations = _neat_network._activations

	# Draw connections first (behind nodes)
	var connections: Array = _neat_genome.connection_genes if _neat_genome else _neat_network._connections
	for conn in connections:
		var in_id: int = conn.in_id if _neat_genome else int(conn.get("in_id", -1))
		var out_id: int = conn.out_id if _neat_genome else int(conn.get("out_id", -1))
		if not _node_positions.has(in_id) or not _node_positions.has(out_id):
			continue

		var from_pos: Vector2 = _node_positions[in_id]
		var to_pos: Vector2 = _node_positions[out_id]

		var color: Color
		var width: float

		if _neat_genome and not conn.enabled:
			color = CONN_DISABLED
			width = MIN_CONNECTION_WIDTH
		else:
			var w: float = conn.weight if _neat_genome else float(conn.get("weight", 0.0))
			width = clampf(absf(w) * 1.5, MIN_CONNECTION_WIDTH, MAX_CONNECTION_WIDTH)
			color = CONN_POSITIVE if w >= 0 else CONN_NEGATIVE
			color.a = clampf(0.2 + absf(w) * 0.4, 0.1, 0.7)

		draw_line(from_pos, to_pos, color, width, true)

	# Draw nodes
	var node_ids: Array = []
	if _neat_genome:
		for node in _neat_genome.node_genes:
			node_ids.append(node.id)
	else:
		for node_id in _node_positions.keys():
			node_ids.append(node_id)

	for node_id in node_ids:
		if not _node_positions.has(node_id):
			continue

		var pos: Vector2 = _node_positions[node_id]
		var radius: float = NODE_RADIUS
		match _node_types.get(node_id, 1):
			0: radius = NODE_RADIUS_INPUT
			2: radius = NODE_RADIUS_OUTPUT

		var activation: float = activations.get(node_id, 0.0)
		var color: Color = _activation_color(activation)

		draw_circle(pos, radius, color)
		draw_arc(pos, radius, 0, TAU, 32, Color(0.5, 0.55, 0.6, 0.5), 1.0)


func _draw_fixed_network(font: Font) -> void:
	## Draw fixed-topology network with live activations.
	if not _fixed_network or _node_positions.is_empty():
		return

	# Get activations
	var hidden_activations: PackedFloat32Array = _fixed_network._hidden
	var output_activations: PackedFloat32Array = _fixed_network._output

	# Draw connections (simplified — just show patterns, not every connection)
	# For fixed topology with 86 inputs × 32 hidden, drawing all would be clutter
	# Instead draw representative connections with averaged weights
	var display_inputs: Array = []
	var display_hidden: Array = []
	var display_outputs: Array = []

	for node_id in _node_positions:
		match _node_types.get(node_id, -1):
			0: display_inputs.append(node_id)
			1: display_hidden.append(node_id)
			2: display_outputs.append(node_id)

	# Draw input→hidden connections (sampled)
	for h_id in display_hidden:
		var h_idx: int = h_id - _fixed_network.input_size
		if h_idx < 0 or h_idx >= _fixed_network.hidden_size:
			continue
		for i_id in display_inputs:
			if i_id >= _fixed_network.input_size:
				continue
			var w_idx: int = i_id * _fixed_network.hidden_size + h_idx
			if w_idx >= _fixed_network.weights_ih.size():
				continue
			var w: float = _fixed_network.weights_ih[w_idx]
			if absf(w) < 0.3:
				continue  # Skip weak connections
			var color: Color = CONN_POSITIVE if w >= 0 else CONN_NEGATIVE
			color.a = clampf(absf(w) * 0.3, 0.05, 0.4)
			var width: float = clampf(absf(w), MIN_CONNECTION_WIDTH, MAX_CONNECTION_WIDTH * 0.7)
			draw_line(_node_positions[i_id], _node_positions[h_id], color, width, true)

	# Draw hidden→output connections
	for o_id in display_outputs:
		var o_idx: int = o_id - _fixed_network.input_size - _fixed_network.hidden_size
		if o_idx < 0 or o_idx >= _fixed_network.output_size:
			continue
		for h_id in display_hidden:
			var h_idx: int = h_id - _fixed_network.input_size
			if h_idx < 0 or h_idx >= _fixed_network.hidden_size:
				continue
			var w_idx: int = h_idx * _fixed_network.output_size + o_idx
			if w_idx >= _fixed_network.weights_ho.size():
				continue
			var w: float = _fixed_network.weights_ho[w_idx]
			if absf(w) < 0.2:
				continue
			var color: Color = CONN_POSITIVE if w >= 0 else CONN_NEGATIVE
			color.a = clampf(absf(w) * 0.4, 0.1, 0.6)
			var width: float = clampf(absf(w) * 1.5, MIN_CONNECTION_WIDTH, MAX_CONNECTION_WIDTH)
			draw_line(_node_positions[h_id], _node_positions[o_id], color, width, true)

	# Draw nodes
	for node_id in _node_positions:
		var pos: Vector2 = _node_positions[node_id]
		var type: int = _node_types.get(node_id, 0)
		var radius: float = NODE_RADIUS
		match type:
			0: radius = NODE_RADIUS_INPUT
			2: radius = NODE_RADIUS_OUTPUT

		var activation: float = 0.0
		if type == 1:
			var h_idx: int = node_id - _fixed_network.input_size
			if h_idx >= 0 and h_idx < hidden_activations.size():
				activation = hidden_activations[h_idx]
		elif type == 2:
			var o_idx: int = node_id - _fixed_network.input_size - _fixed_network.hidden_size
			if o_idx >= 0 and o_idx < output_activations.size():
				activation = output_activations[o_idx]

		var color: Color = _activation_color(activation)
		draw_circle(pos, radius, color)
		draw_arc(pos, radius, 0, TAU, 32, Color(0.5, 0.55, 0.6, 0.5), 1.0)

		# Label output nodes
		if type == 2:
			var o_idx: int = node_id - _fixed_network.input_size - _fixed_network.hidden_size
			var labels: Array = ["MX", "MY", "SU", "SD", "SL", "SR"]
			if o_idx >= 0 and o_idx < labels.size():
				draw_string(ThemeDB.fallback_font, pos + Vector2(12, 4), labels[o_idx], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LABEL_COLOR)


func _activation_color(activation: float) -> Color:
	## Map activation value to color: blue(neg) → white(0) → red(pos).
	var t: float = clampf(activation, -1.0, 1.0)
	if t >= 0:
		return Color(0.5 + t * 0.5, 0.5 - t * 0.3, 0.5 - t * 0.4, 1.0)
	else:
		var at: float = absf(t)
		return Color(0.5 - at * 0.3, 0.5 - at * 0.2, 0.5 + at * 0.5, 1.0)


func _get_plot_rect() -> Rect2:
	return Rect2(MARGIN + 10, MARGIN + 25, size.x - MARGIN * 2 - 20, size.y - MARGIN * 2 - 40)
