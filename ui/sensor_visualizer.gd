extends Node2D

## Visual sensor feedback overlay for watching AI play.
## Draws sensor rays from the player, color-coded by what they detect:
##   - Red: enemy detected (brighter = closer)
##   - Green: powerup detected (brighter = closer)
##   - Blue-gray: wall distance
##   - Dark gray: obstacle detected
##   - Dim line: nothing detected
##
## Toggle with V key.

var enabled: bool = false
var sensor: RefCounted = null  # ai/sensor.gd instance
var player: CharacterBody2D = null
var highlighted_ray: int = -1  # Ray index to highlight (-1 = none)

# Colors
const COLOR_ENEMY := Color(1.0, 0.2, 0.2, 0.7)
const COLOR_POWERUP := Color(0.2, 1.0, 0.4, 0.7)
const COLOR_OBSTACLE := Color(0.5, 0.5, 0.6, 0.5)
const COLOR_WALL := Color(0.3, 0.4, 0.7, 0.4)
const COLOR_NONE := Color(0.2, 0.2, 0.25, 0.15)

# Throttle redraws to ~10fps
var _redraw_timer: float = 0.0
const REDRAW_INTERVAL: float = 0.1


func setup(p_player: CharacterBody2D) -> void:
	player = p_player
	if not player:
		push_error("SensorVisualizer: Cannot setup with null player")
		return
	var SensorScript = preload("res://ai/sensor.gd")
	sensor = SensorScript.new()
	sensor.set_player(player)


func toggle() -> void:
	enabled = not enabled
	visible = enabled
	if enabled:
		queue_redraw()


func _process(delta: float) -> void:
	if not enabled or not player or not is_instance_valid(player):
		return
	_redraw_timer += delta
	if _redraw_timer >= REDRAW_INTERVAL:
		_redraw_timer = 0.0
		queue_redraw()


func _draw() -> void:
	if not enabled or not sensor or not player or not is_instance_valid(player):
		return

	if not sensor.has_method("get_inputs"):
		push_error("SensorVisualizer: sensor missing get_inputs() method")
		return

	var inputs: PackedFloat32Array = sensor.get_inputs()
	if not sensor.has("TOTAL_INPUTS") or inputs.size() < sensor.TOTAL_INPUTS:
		return

	var player_pos: Vector2 = player.global_position
	var ray_length: float = sensor.RAY_LENGTH

	for i in sensor.NUM_RAYS:
		var angle: float = (float(i) / sensor.NUM_RAYS) * TAU
		var ray_dir := Vector2(cos(angle), sin(angle))
		var base_idx: int = i * sensor.INPUTS_PER_RAY

		var enemy_dist_val: float = inputs[base_idx]      # 1=close, 0=far/none
		var obstacle_dist_val: float = inputs[base_idx + 2]
		var powerup_dist_val: float = inputs[base_idx + 3]
		var wall_dist_val: float = inputs[base_idx + 4]

		# Determine the dominant detection and draw accordingly
		var color: Color = COLOR_NONE
		var draw_length: float = ray_length * 0.3  # Default short line

		if enemy_dist_val > 0.01:
			color = COLOR_ENEMY
			color.a = 0.3 + enemy_dist_val * 0.6
			draw_length = (1.0 - enemy_dist_val) * ray_length
		elif powerup_dist_val > 0.01:
			color = COLOR_POWERUP
			color.a = 0.3 + powerup_dist_val * 0.6
			draw_length = (1.0 - powerup_dist_val) * ray_length
		elif obstacle_dist_val > 0.01:
			color = COLOR_OBSTACLE
			draw_length = (1.0 - obstacle_dist_val) * ray_length
		elif wall_dist_val > 0.01:
			color = COLOR_WALL
			draw_length = (1.0 - wall_dist_val) * ray_length

		var end_pos: Vector2 = player_pos + ray_dir * draw_length
		var width: float = 2.0 if (enemy_dist_val > 0.01 or powerup_dist_val > 0.01) else 1.0
		if i == highlighted_ray:
			width = maxf(width, 3.0)
			color.a = minf(color.a + 0.3, 1.0)
		draw_line(player_pos, end_pos, color, width, true)

		# Draw a small dot at detection point for enemies and powerups
		if enemy_dist_val > 0.3:
			draw_circle(end_pos, 4.0, COLOR_ENEMY)
		elif powerup_dist_val > 0.3:
			draw_circle(end_pos, 4.0, COLOR_POWERUP)
