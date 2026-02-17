extends Control

## Educational mode overlay: narrates AI decisions in plain text.
## Shows threat detection, movement intent, shooting action, and active power-ups.
## Includes a horizontal bar chart of the 6 network outputs.
##
## Toggle with E key during playback or rtNEAT (with inspected agent).

# Panel dimensions
const PANEL_WIDTH: float = 340.0
const PANEL_HEIGHT: float = 200.0
const PANEL_MARGIN: float = 15.0

# Colors
const BG_COLOR := Color(0.06, 0.06, 0.1, 0.92)
const BORDER_COLOR := Color(0.3, 0.4, 0.6, 0.8)
const THREAT_COLOR := Color(1.0, 0.3, 0.3, 1.0)
const MOVE_COLOR := Color(0.4, 0.6, 1.0, 1.0)
const SHOOT_COLOR := Color(1.0, 0.7, 0.2, 1.0)
const STATE_COLOR := Color(0.3, 1.0, 0.5, 1.0)
const HEADER_COLOR := Color(0.8, 0.85, 0.95, 1.0)
const BAR_POS_COLOR := Color(0.3, 0.5, 1.0, 0.8)
const BAR_NEG_COLOR := Color(1.0, 0.3, 0.3, 0.8)
const LABEL_COLOR := Color(0.6, 0.65, 0.75, 1.0)

# Sensor constants (mirror ai/sensor.gd)
const NUM_RAYS: int = 16
const INPUTS_PER_RAY: int = 5
const PLAYER_STATE_OFFSET: int = 80  # NUM_RAYS * INPUTS_PER_RAY

# Output labels
const OUTPUT_LABELS: PackedStringArray = ["MX", "MY", "SU", "SD", "SL", "SR"]
const SHOOT_DIR_NAMES: PackedStringArray = ["UP", "DOWN", "LEFT", "RIGHT"]

# Enemy type names by encoded value ranges
const ENEMY_TYPES: Array = [
	{"min": 0.0, "max": 0.25, "name": "Pawn"},
	{"min": 0.25, "max": 0.5, "name": "Knight"},
	{"min": 0.5, "max": 0.7, "name": "Bishop"},
	{"min": 0.7, "max": 0.9, "name": "Rook"},
	{"min": 0.9, "max": 1.1, "name": "Queen"},
]

# Throttle redraws
var _redraw_timer: float = 0.0
const REDRAW_INTERVAL: float = 0.1

# Cached analysis results
var _threat_info: Dictionary = {}
var _move_text: String = ""
var _shoot_text: String = ""
var _state_text: String = ""
var _outputs: PackedFloat32Array = PackedFloat32Array()
var _highlight_ray: int = -1

# Font
var _font: Font = null
const FONT_SIZE: int = 13
const SMALL_FONT_SIZE: int = 11


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	if not visible:
		return
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		queue_redraw()


func update_from_controller(ai_controller, sensor) -> void:
	## Read inputs/outputs from the AI controller and generate narration.
	if not ai_controller or not sensor:
		return

	var inputs: PackedFloat32Array = ai_controller.get_inputs()
	_outputs = ai_controller.get_outputs()

	if inputs.size() < PLAYER_STATE_OFFSET + 6 or _outputs.size() < 6:
		return

	_threat_info = _analyze_threats(inputs)
	_highlight_ray = _threat_info.get("ray_index", -1)
	_move_text = _describe_movement(_outputs, _threat_info)
	_shoot_text = _describe_shooting(_outputs)
	_state_text = _describe_state(inputs)


func get_highlight_ray() -> int:
	return _highlight_ray


# ============================================================
# Analysis methods (pure, testable)
# ============================================================

func _analyze_threats(inputs: PackedFloat32Array) -> Dictionary:
	## Scan 16 rays and return info about the most significant detection.
	## Priority: enemy > powerup > wall > none.
	## Enemy significance = distance_value * type_weight.
	var best: Dictionary = {"ray_index": -1, "kind": "none", "dist_value": 0.0, "type_value": 0.0}
	var best_score: float = 0.0

	for i in NUM_RAYS:
		var base_idx: int = i * INPUTS_PER_RAY
		var enemy_dist: float = inputs[base_idx]
		var enemy_type: float = inputs[base_idx + 1]
		var powerup_dist: float = inputs[base_idx + 3]

		# Enemy significance: proximity × type weight (queen=1.0 scores highest)
		if enemy_dist > 0.01:
			var score: float = enemy_dist * maxf(enemy_type, 0.2)
			if score > best_score or best.kind != "enemy":
				if best.kind != "enemy" or score > best_score:
					best_score = score
					best = {"ray_index": i, "kind": "enemy", "dist_value": enemy_dist, "type_value": enemy_type}

		# Powerup only if no enemy found yet
		if powerup_dist > 0.01 and best.kind != "enemy":
			if powerup_dist > best_score or best.kind == "none":
				best_score = powerup_dist
				best = {"ray_index": i, "kind": "powerup", "dist_value": powerup_dist, "type_value": 0.0}

	return best


func _describe_threat(info: Dictionary) -> String:
	## Generate human-readable threat description.
	if info.kind == "none":
		return "No threats detected"

	if info.kind == "powerup":
		var pct: int = int(info.dist_value * 100)
		return "Power-up detected at %d%% proximity (Ray %d)" % [pct, info.ray_index]

	# Enemy
	var type_name: String = _get_enemy_type_name(info.type_value)
	var pct: int = int(info.dist_value * 100)
	return "Detecting %s at %d%% proximity (Ray %d)" % [type_name, pct, info.ray_index]


func _describe_movement(outputs: PackedFloat32Array, threat_info: Dictionary) -> String:
	## Describe movement direction and intent.
	if outputs.size() < 2:
		return "No movement data"

	var mx: float = outputs[0]
	var my: float = outputs[1]
	var move_vec := Vector2(mx, my)

	if move_vec.length() < 0.05:
		return "Standing still"

	var dir_name: String = _direction_name(move_vec)

	# Determine context: evading threat or approaching powerup
	if threat_info.kind == "enemy" and threat_info.ray_index >= 0:
		var ray_angle: float = (float(threat_info.ray_index) / NUM_RAYS) * TAU
		var ray_dir := Vector2(cos(ray_angle), sin(ray_angle))
		var dot: float = move_vec.normalized().dot(ray_dir)
		if dot < -0.3:
			return "Moving %s (evading threat)" % dir_name
		elif dot > 0.3:
			return "Moving %s (toward threat!)" % dir_name

	if threat_info.kind == "powerup" and threat_info.ray_index >= 0:
		var ray_angle: float = (float(threat_info.ray_index) / NUM_RAYS) * TAU
		var ray_dir := Vector2(cos(ray_angle), sin(ray_angle))
		var dot: float = move_vec.normalized().dot(ray_dir)
		if dot > 0.3:
			return "Moving %s (toward power-up)" % dir_name

	return "Moving %s" % dir_name


func _describe_shooting(outputs: PackedFloat32Array) -> String:
	## Describe which direction the AI is shooting, if any.
	if outputs.size() < 6:
		return "No shooting data"

	var best_val: float = 0.0
	var best_idx: int = -1

	for i in 4:
		var val: float = outputs[i + 2]  # Shoot outputs start at index 2
		if val > best_val:
			best_val = val
			best_idx = i

	if best_idx < 0 or best_val <= 0.0:
		return "Not shooting"

	return "Firing %s (output: %.2f)" % [SHOOT_DIR_NAMES[best_idx], best_val]


func _describe_state(inputs: PackedFloat32Array) -> String:
	## Describe active power-up states from player state inputs.
	## Indices 80-85: vel_x, vel_y, invincible, speed_boost, can_shoot, shield
	if inputs.size() < PLAYER_STATE_OFFSET + 6:
		return ""

	var states: PackedStringArray = PackedStringArray()

	if inputs[PLAYER_STATE_OFFSET + 2] > 0.5:
		states.append("INVINCIBLE")
	if inputs[PLAYER_STATE_OFFSET + 3] > 0.5:
		states.append("SPEED BOOST")
	if inputs[PLAYER_STATE_OFFSET + 5] > 0.5:
		states.append("SHIELD")

	if states.size() == 0:
		return "No active power-ups"

	return " | ".join(states)


# ============================================================
# Helpers
# ============================================================

func _get_enemy_type_name(type_value: float) -> String:
	for entry in ENEMY_TYPES:
		if type_value >= entry.min and type_value < entry.max:
			return entry.name
	return "Queen"  # Fallback for 1.0


func _direction_name(vec: Vector2) -> String:
	## Convert a movement vector to a human-readable direction name.
	var angle: float = vec.angle()
	# Normalize to 0..TAU
	if angle < 0:
		angle += TAU

	# 8 cardinal directions (each 45 degrees = PI/4)
	var sector: int = int(round(angle / (TAU / 8))) % 8
	var names: PackedStringArray = ["RIGHT", "DOWN-RIGHT", "DOWN", "DOWN-LEFT", "LEFT", "UP-LEFT", "UP", "UP-RIGHT"]
	if sector >= 0 and sector < names.size():
		return names[sector]
	return "RIGHT"  # Fallback


# ============================================================
# Drawing
# ============================================================

func _draw() -> void:
	if not visible or not _font:
		return

	var vp_size: Vector2 = get_viewport_rect().size
	var panel_pos := Vector2(PANEL_MARGIN, vp_size.y - PANEL_HEIGHT - PANEL_MARGIN)

	# Background
	var bg_rect := Rect2(panel_pos, Vector2(PANEL_WIDTH, PANEL_HEIGHT))
	draw_rect(bg_rect, BG_COLOR)
	draw_rect(bg_rect, BORDER_COLOR, false, 1.0)

	var x: float = panel_pos.x + 10.0
	var y: float = panel_pos.y + 18.0
	var line_h: float = 16.0

	# Header
	draw_string(_font, Vector2(x, y), "AI DECISION ANALYSIS", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, HEADER_COLOR)
	draw_string(_font, Vector2(panel_pos.x + PANEL_WIDTH - 60, y), "[E] Close", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT_SIZE, LABEL_COLOR)
	y += line_h + 4.0

	# Threat line
	var threat_text: String = _describe_threat(_threat_info)
	draw_string(_font, Vector2(x, y), threat_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - 20, FONT_SIZE, THREAT_COLOR)
	y += line_h

	# Movement line
	draw_string(_font, Vector2(x, y), _move_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - 20, FONT_SIZE, MOVE_COLOR)
	y += line_h

	# Shooting line
	draw_string(_font, Vector2(x, y), _shoot_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - 20, FONT_SIZE, SHOOT_COLOR)
	y += line_h

	# State line
	draw_string(_font, Vector2(x, y), _state_text, HORIZONTAL_ALIGNMENT_LEFT, PANEL_WIDTH - 20, FONT_SIZE, STATE_COLOR)
	y += line_h + 6.0

	# Output bar chart
	draw_string(_font, Vector2(x, y), "Network Outputs:", HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT_SIZE, LABEL_COLOR)
	y += 14.0

	if _outputs.size() >= 6:
		_draw_output_bars(Vector2(x, y), PANEL_WIDTH - 20.0)


func _draw_output_bars(pos: Vector2, total_width: float) -> void:
	## Draw horizontal bar chart for 6 output values.
	var bar_count: int = 6
	var bar_width: float = total_width / bar_count
	var bar_height: float = 28.0
	var center_y: float = pos.y + bar_height / 2.0

	for i in bar_count:
		var bx: float = pos.x + i * bar_width
		var val: float = clampf(_outputs[i], -1.0, 1.0)

		# Label above
		draw_string(_font, Vector2(bx + 4, pos.y - 2), OUTPUT_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_FONT_SIZE, LABEL_COLOR)

		# Bar background
		draw_rect(Rect2(bx + 2, pos.y, bar_width - 4, bar_height), Color(0.15, 0.15, 0.2, 0.6))

		# Center line
		draw_line(Vector2(bx + 2, center_y), Vector2(bx + bar_width - 2, center_y), Color(0.4, 0.4, 0.5, 0.5), 1.0)

		# Value bar (from center, positive=up/blue, negative=down/red)
		var bar_max_extent: float = bar_height / 2.0 - 2.0
		var extent: float = absf(val) * bar_max_extent
		var color: Color = BAR_POS_COLOR if val >= 0 else BAR_NEG_COLOR

		if val >= 0:
			draw_rect(Rect2(bx + 4, center_y - extent, bar_width - 8, extent), color)
		else:
			draw_rect(Rect2(bx + 4, center_y, bar_width - 8, extent), color)
