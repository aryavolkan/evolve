extends CharacterBody2D

enum Type { CHASER, SPEEDSTER, TANK, ZIGZAG }

@export var speed: float = 150.0
@export var type: Type = Type.CHASER

var player: CharacterBody2D

# Zigzag state
var zigzag_timer: float = 0.0
var zigzag_direction: float = 1.0

# Speedster state (dash behavior)
var dash_timer: float = 0.0
var is_dashing: bool = true
const DASH_DURATION: float = 0.8
const PAUSE_DURATION: float = 0.3

# Tank state (slow turning)
var current_direction: Vector2 = Vector2.ZERO
const TANK_TURN_SPEED: float = 1.5  # Radians per second

const TYPE_CONFIG = {
	Type.CHASER: { "color": Color(0.9, 0.2, 0.2, 1), "size": 30.0, "speed_mult": 1.0 },
	Type.SPEEDSTER: { "color": Color(1.0, 0.5, 0.0, 1), "size": 20.0, "speed_mult": 1.8 },
	Type.TANK: { "color": Color(0.5, 0.1, 0.1, 1), "size": 45.0, "speed_mult": 0.5 },
	Type.ZIGZAG: { "color": Color(0.9, 0.2, 0.9, 1), "size": 25.0, "speed_mult": 1.1 }
}

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	apply_type_config()

func apply_type_config() -> void:
	var config = TYPE_CONFIG[type]
	$ColorRect.color = config["color"]
	var half_size = config["size"] / 2.0
	var border_half = half_size + 2.0
	$Border.offset_left = -border_half
	$Border.offset_top = -border_half
	$Border.offset_right = border_half
	$Border.offset_bottom = border_half
	$ColorRect.offset_left = -half_size
	$ColorRect.offset_top = -half_size
	$ColorRect.offset_right = half_size
	$ColorRect.offset_bottom = half_size
	$CollisionShape2D.shape.size = Vector2(config["size"], config["size"])
	speed *= config["speed_mult"]

func _physics_process(delta: float) -> void:
	if not player:
		return

	var target_direction = (player.global_position - global_position).normalized()
	var final_velocity: Vector2

	# Apply movement pattern based on type
	match type:
		Type.CHASER:
			# Direct pursuit - always moves toward player
			final_velocity = target_direction * speed

		Type.SPEEDSTER:
			# Dash behavior - bursts of speed with pauses
			dash_timer += delta
			if is_dashing:
				if dash_timer >= DASH_DURATION:
					dash_timer = 0.0
					is_dashing = false
				final_velocity = target_direction * speed
			else:
				if dash_timer >= PAUSE_DURATION:
					dash_timer = 0.0
					is_dashing = true
				final_velocity = target_direction * speed * 0.2  # Slow down during pause

		Type.TANK:
			# Slow turning - can't change direction quickly
			if current_direction == Vector2.ZERO:
				current_direction = target_direction
			else:
				var angle_diff = current_direction.angle_to(target_direction)
				var max_turn = TANK_TURN_SPEED * delta
				if abs(angle_diff) > max_turn:
					angle_diff = sign(angle_diff) * max_turn
				current_direction = current_direction.rotated(angle_diff).normalized()
			final_velocity = current_direction * speed

		Type.ZIGZAG:
			# Erratic side-to-side movement
			zigzag_timer += delta
			if zigzag_timer >= 0.3:
				zigzag_timer = 0.0
				zigzag_direction *= -1.0
			var perpendicular = Vector2(-target_direction.y, target_direction.x)
			var zigzag_dir = (target_direction + perpendicular * zigzag_direction * 0.7).normalized()
			final_velocity = zigzag_dir * speed

	velocity = final_velocity
	move_and_slide()

	# Check if we hit the player
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider.is_in_group("player"):
			player.on_enemy_collision(self)
			return
