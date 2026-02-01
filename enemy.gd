extends CharacterBody2D

@export var speed: float = 150.0
var player: CharacterBody2D

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if not player:
		return

	var direction = (player.global_position - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

	# Check if we hit the player
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider.is_in_group("player"):
			player.on_enemy_collision(self)
			return
