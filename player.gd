extends CharacterBody2D

signal hit
signal enemy_killed(pos: Vector2, points: int)
signal powerup_timer_updated(powerup_type: String, time_left: float)

@export var speed: float = 300.0
@export var boosted_speed: float = 500.0
@export var shoot_cooldown: float = 0.3
var is_hit: bool = false
var is_invincible: bool = false
var is_speed_boosted: bool = false
var can_shoot: bool = true

# Power-up timers
var speed_boost_time: float = 0.0
var invincibility_time: float = 0.0

var projectile_scene: PackedScene = preload("res://projectile.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var speed_particles: CPUParticles2D = $SpeedParticles
@onready var invincibility_particles: CPUParticles2D = $InvincibilityParticles

func _ready() -> void:
	speed_particles.emitting = false
	invincibility_particles.emitting = false

func _physics_process(delta: float) -> void:
	if is_hit:
		return

	# Update power-up timers
	update_powerup_timers(delta)

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

func update_powerup_timers(delta: float) -> void:
	if speed_boost_time > 0:
		speed_boost_time -= delta
		powerup_timer_updated.emit("SPEED", speed_boost_time)
		if speed_boost_time <= 0:
			end_speed_boost()

	if invincibility_time > 0:
		invincibility_time -= delta
		powerup_timer_updated.emit("INVINCIBLE", invincibility_time)
		if invincibility_time <= 0:
			end_invincibility()

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
	speed_boost_time = duration
	sprite.modulate = Color(0.5, 1, 0.8, 1)  # Cyan-green tint
	speed_particles.emitting = true

func end_speed_boost() -> void:
	is_speed_boosted = false
	speed_boost_time = 0.0
	speed_particles.emitting = false
	powerup_timer_updated.emit("SPEED", 0.0)
	if not is_invincible:
		sprite.modulate = Color(1, 1, 1, 1)

func activate_invincibility(duration: float) -> void:
	is_invincible = true
	invincibility_time = duration
	sprite.modulate = Color(1, 0.9, 0.3, 1)  # Gold tint
	invincibility_particles.emitting = true

func end_invincibility() -> void:
	is_invincible = false
	invincibility_time = 0.0
	invincibility_particles.emitting = false
	powerup_timer_updated.emit("INVINCIBLE", 0.0)
	if not is_speed_boosted:
		sprite.modulate = Color(1, 1, 1, 1)

func respawn(pos: Vector2, invincibility_duration: float) -> void:
	position = pos
	is_hit = false
	activate_invincibility(invincibility_duration)

func get_active_powerups() -> Dictionary:
	return {
		"SPEED": speed_boost_time,
		"INVINCIBLE": invincibility_time
	}
