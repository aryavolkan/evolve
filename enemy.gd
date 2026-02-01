extends CharacterBody2D

enum Type { CHASER, SPEEDSTER, TANK, ZIGZAG }

@export var speed: float = 150.0
@export var type: Type = Type.CHASER

var player: CharacterBody2D
var zigzag_timer: float = 0.0
var zigzag_direction: float = 1.0

const TYPE_CONFIG = {
	Type.CHASER: { "color": Color(0.9, 0.2, 0.2, 1), "size": 30.0, "speed_mult": 1.0 },
	Type.SPEEDSTER: { "color": Color(1.0, 0.5, 0.0, 1), "size": 20.0, "speed_mult": 1.5 },
	Type.TANK: { "color": Color(0.5, 0.1, 0.1, 1), "size": 45.0, "speed_mult": 0.6 },
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

	var direction = (player.global_position - global_position).normalized()

	# Apply movement pattern based on type
	match type:
		Type.ZIGZAG:
			zigzag_timer += delta
			if zigzag_timer >= 0.3:
				zigzag_timer = 0.0
				zigzag_direction *= -1.0
			var perpendicular = Vector2(-direction.y, direction.x)
			direction = (direction + perpendicular * zigzag_direction * 0.5).normalized()

	velocity = direction * speed
	move_and_slide()

	# Check if we hit the player
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider.is_in_group("player"):
			player.on_enemy_collision(self)
			return
