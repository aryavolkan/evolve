extends Area2D

@export var speed: float = 600.0
@export var max_distance: float = 800.0
var direction: Vector2 = Vector2.RIGHT
var start_position: Vector2

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	start_position = position

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

	# Remove if traveled too far
	if position.distance_to(start_position) > max_distance:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("obstacle"):
		# Projectile hits obstacle and is destroyed
		queue_free()
		return

	if body.is_in_group("enemy"):
		var enemy_pos = body.global_position
		var points = body.get_point_value() if body.has_method("get_point_value") else 1
		body.queue_free()
		queue_free()
		# Notify player of kill for bonus points
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.enemy_killed.emit(enemy_pos, points)
