extends CharacterBody2D

signal hit

@export var speed: float = 300.0
var is_hit: bool = false

func _physics_process(delta: float) -> void:
	if is_hit:
		return

	var direction := Vector2.ZERO

	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1

	if direction != Vector2.ZERO:
		direction = direction.normalized()

	velocity = direction * speed
	move_and_slide()

	# Check collisions after movement
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider.is_in_group("enemy"):
			_trigger_hit()
			return

func _trigger_hit() -> void:
	if is_hit:
		return
	is_hit = true
	hit.emit()
