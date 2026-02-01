extends CharacterBody2D

signal hit
signal enemy_killed(pos: Vector2, points: int)

@export var speed: float = 300.0
@export var boosted_speed: float = 500.0
@export var shoot_cooldown: float = 0.3
var is_hit: bool = false
var is_invincible: bool = false
var is_speed_boosted: bool = false
var base_color: Color = Color(0.2, 0.6, 1, 1)
var can_shoot: bool = true

var projectile_scene: PackedScene = preload("res://projectile.tscn")

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

	# Shooting with WASD
	if can_shoot:
		var shoot_dir := Vector2.ZERO
		if Input.is_action_just_pressed("shoot_up"):
			shoot_dir = Vector2.UP
		elif Input.is_action_just_pressed("shoot_down"):
			shoot_dir = Vector2.DOWN
		elif Input.is_action_just_pressed("shoot_left"):
			shoot_dir = Vector2.LEFT
		elif Input.is_action_just_pressed("shoot_right"):
			shoot_dir = Vector2.RIGHT

		if shoot_dir != Vector2.ZERO:
			shoot(shoot_dir)

func shoot(direction: Vector2) -> void:
	var projectile = projectile_scene.instantiate()
	projectile.position = global_position
	projectile.direction = direction
	get_parent().add_child(projectile)

	can_shoot = false
	await get_tree().create_timer(shoot_cooldown).timeout
	can_shoot = true

	# Check collisions after movement
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider.is_in_group("enemy"):
			on_enemy_collision(collider)
			return

func on_enemy_collision(enemy: Node) -> void:
	if is_invincible:
		var enemy_pos = enemy.global_position
		var points = enemy.get_point_value() if enemy.has_method("get_point_value") else 1
		enemy.queue_free()
		enemy_killed.emit(enemy_pos, points)
		return
	_trigger_hit()

func _trigger_hit() -> void:
	if is_hit:
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

func respawn(pos: Vector2, invincibility_duration: float) -> void:
	position = pos
	is_hit = false
	activate_invincibility(invincibility_duration)
