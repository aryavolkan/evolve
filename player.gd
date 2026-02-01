extends CharacterBody2D

signal hit

@export var speed: float = 300.0
@export var boosted_speed: float = 500.0
var is_hit: bool = false
var is_invincible: bool = false
var is_speed_boosted: bool = false
var base_color: Color = Color(0.2, 0.6, 1, 1)

@onready var color_rect: ColorRect = $ColorRect

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

	var current_speed = boosted_speed if is_speed_boosted else speed
	velocity = direction * current_speed
	move_and_slide()

	# Check collisions after movement
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider.is_in_group("enemy"):
			_trigger_hit()
			return

func _trigger_hit() -> void:
	if is_hit or is_invincible:
		return
	is_hit = true
	hit.emit()

func activate_speed_boost(duration: float) -> void:
	is_speed_boosted = true
	color_rect.color = Color(0, 1, 0.5, 1)  # Cyan-green
	await get_tree().create_timer(duration).timeout
	is_speed_boosted = false
	if not is_invincible:
		color_rect.color = base_color

func activate_invincibility(duration: float) -> void:
	is_invincible = true
	color_rect.color = Color(1, 0.8, 0, 1)  # Gold
	await get_tree().create_timer(duration).timeout
	is_invincible = false
	if not is_speed_boosted:
		color_rect.color = base_color
