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
var is_slow_active: bool = false
var is_rapid_fire: bool = false
var is_piercing: bool = false
var has_shield: bool = false  # Absorbs one hit
var is_freeze_active: bool = false
var is_double_points: bool = false
var can_shoot: bool = true

# AI control
var ai_controlled: bool = false
var ai_move_direction: Vector2 = Vector2.ZERO
var ai_shoot_direction: Vector2 = Vector2.ZERO

# Power-up timers
var speed_boost_time: float = 0.0
var invincibility_time: float = 0.0
var slow_time: float = 0.0
var rapid_fire_time: float = 0.0
var piercing_time: float = 0.0
var freeze_time: float = 0.0
var double_points_time: float = 0.0

var projectile_scene: PackedScene = preload("res://projectile.tscn")

@onready var sprite: Sprite2D = $Sprite2D
@onready var speed_particles: CPUParticles2D = $SpeedParticles
@onready var invincibility_particles: CPUParticles2D = $InvincibilityParticles
@onready var slow_particles: CPUParticles2D = $SlowParticles
@onready var timer_label: RichTextLabel = $TimerLabel

func _ready() -> void:
	speed_particles.emitting = false
	invincibility_particles.emitting = false
	slow_particles.emitting = false
	timer_label.visible = false

func _physics_process(delta: float) -> void:
	if is_hit:
		return

	# Update power-up timers
	update_powerup_timers(delta)
	update_timer_display()

	var direction := Vector2.ZERO
	var shoot_dir := Vector2.ZERO

	if ai_controlled:
		# AI control mode
		direction = ai_move_direction
		shoot_dir = ai_shoot_direction
		# Reset AI inputs after reading
		ai_shoot_direction = Vector2.ZERO
	else:
		# Human control mode
		if Input.is_action_pressed("ui_right"):
			direction.x += 1
		if Input.is_action_pressed("ui_left"):
			direction.x -= 1
		if Input.is_action_pressed("ui_down"):
			direction.y += 1
		if Input.is_action_pressed("ui_up"):
			direction.y -= 1

		# Shooting with WASD
		if can_shoot:
			if Input.is_action_just_pressed("shoot_up"):
				shoot_dir = Vector2.UP
			elif Input.is_action_just_pressed("shoot_down"):
				shoot_dir = Vector2.DOWN
			elif Input.is_action_just_pressed("shoot_left"):
				shoot_dir = Vector2.LEFT
			elif Input.is_action_just_pressed("shoot_right"):
				shoot_dir = Vector2.RIGHT

	if direction != Vector2.ZERO:
		direction = direction.normalized()

	var current_speed = boosted_speed if is_speed_boosted else speed
	velocity = direction * current_speed
	move_and_slide()

	# Clamp position to arena bounds (get from main scene)
	var main = get_parent()
	if main and main.has_method("get_arena_bounds"):
		var bounds: Rect2 = main.get_arena_bounds()
		position.x = clampf(position.x, bounds.position.x, bounds.end.x)
		position.y = clampf(position.y, bounds.position.y, bounds.end.y)

	# Handle shooting
	if can_shoot and shoot_dir != Vector2.ZERO:
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

	if slow_time > 0:
		slow_time -= delta
		powerup_timer_updated.emit("SLOW", slow_time)
		if slow_time <= 0:
			end_slow_effect()

	if rapid_fire_time > 0:
		rapid_fire_time -= delta
		powerup_timer_updated.emit("RAPID", rapid_fire_time)
		if rapid_fire_time <= 0:
			end_rapid_fire()

	if piercing_time > 0:
		piercing_time -= delta
		powerup_timer_updated.emit("PIERCING", piercing_time)
		if piercing_time <= 0:
			end_piercing()

	if freeze_time > 0:
		freeze_time -= delta
		powerup_timer_updated.emit("FREEZE", freeze_time)
		if freeze_time <= 0:
			end_freeze_effect()

	if double_points_time > 0:
		double_points_time -= delta
		powerup_timer_updated.emit("DOUBLE", double_points_time)
		if double_points_time <= 0:
			end_double_points()

func update_timer_display() -> void:
	var lines: Array = []

	if speed_boost_time > 0:
		lines.append("[color=cyan]SPEED %.1f[/color]" % speed_boost_time)
	if invincibility_time > 0:
		lines.append("[color=gold]SHIELD %.1f[/color]" % invincibility_time)
	if slow_time > 0:
		lines.append("[color=purple]SLOW %.1f[/color]" % slow_time)
	if rapid_fire_time > 0:
		lines.append("[color=orange]RAPID %.1f[/color]" % rapid_fire_time)
	if piercing_time > 0:
		lines.append("[color=deepskyblue]PIERCE %.1f[/color]" % piercing_time)
	if freeze_time > 0:
		lines.append("[color=lightcyan]FREEZE %.1f[/color]" % freeze_time)
	if double_points_time > 0:
		lines.append("[color=lime]2X POINTS %.1f[/color]" % double_points_time)

	if lines.size() > 0:
		timer_label.text = "\n".join(lines)
		timer_label.visible = true
	else:
		timer_label.visible = false

func shoot(direction: Vector2) -> void:
	var projectile = projectile_scene.instantiate()
	projectile.position = global_position
	projectile.direction = direction
	projectile.is_piercing = is_piercing
	get_parent().add_child(projectile)

	can_shoot = false
	var cooldown = shoot_cooldown * 0.3 if is_rapid_fire else shoot_cooldown  # 70% faster when rapid fire
	await get_tree().create_timer(cooldown).timeout
	can_shoot = true

	# Check collisions after movement
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider and collider.is_in_group("enemy"):
			on_enemy_collision(collider)
			return

func on_enemy_collision(enemy: Node) -> void:
	if is_invincible:
		var enemy_pos = enemy.global_position
		var points = enemy.get_point_value() if enemy.has_method("get_point_value") else 1
		enemy.queue_free()
		enemy_killed.emit(enemy_pos, points)
		return
	if has_shield:
		# Shield absorbs the hit
		has_shield = false
		update_sprite_color()
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
	update_sprite_color()

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
	update_sprite_color()

func activate_slow_effect(duration: float) -> void:
	is_slow_active = true
	slow_time = duration
	slow_particles.emitting = true

func end_slow_effect() -> void:
	is_slow_active = false
	slow_time = 0.0
	slow_particles.emitting = false
	powerup_timer_updated.emit("SLOW", 0.0)

func activate_rapid_fire(duration: float) -> void:
	is_rapid_fire = true
	rapid_fire_time = duration

func end_rapid_fire() -> void:
	is_rapid_fire = false
	rapid_fire_time = 0.0
	powerup_timer_updated.emit("RAPID", 0.0)

func activate_piercing(duration: float) -> void:
	is_piercing = true
	piercing_time = duration

func end_piercing() -> void:
	is_piercing = false
	piercing_time = 0.0
	powerup_timer_updated.emit("PIERCING", 0.0)

func activate_shield() -> void:
	has_shield = true
	# Brief visual feedback
	sprite.modulate = Color(0.7, 0.7, 1, 1)  # Light blue tint
	await get_tree().create_timer(0.3).timeout
	update_sprite_color()

func activate_freeze_effect(duration: float) -> void:
	is_freeze_active = true
	freeze_time = duration

func end_freeze_effect() -> void:
	is_freeze_active = false
	freeze_time = 0.0
	powerup_timer_updated.emit("FREEZE", 0.0)

func activate_double_points(duration: float) -> void:
	is_double_points = true
	double_points_time = duration

func end_double_points() -> void:
	is_double_points = false
	double_points_time = 0.0
	powerup_timer_updated.emit("DOUBLE", 0.0)

func update_sprite_color() -> void:
	if is_invincible:
		sprite.modulate = Color(1, 0.9, 0.3, 1)
	elif is_speed_boosted:
		sprite.modulate = Color(0.5, 1, 0.8, 1)
	else:
		sprite.modulate = Color(1, 1, 1, 1)

func respawn(pos: Vector2, invincibility_duration: float) -> void:
	position = pos
	is_hit = false
	activate_invincibility(invincibility_duration)

func trigger_screen_clear_effect() -> void:
	# Brief burst effect for screen clear
	$ScreenClearParticles.restart()
	$ScreenClearParticles.emitting = true

func get_active_powerups() -> Dictionary:
	return {
		"SPEED": speed_boost_time,
		"INVINCIBLE": invincibility_time,
		"SLOW": slow_time,
		"RAPID": rapid_fire_time,
		"PIERCING": piercing_time,
		"FREEZE": freeze_time,
		"DOUBLE": double_points_time,
		"SHIELD": 1.0 if has_shield else 0.0
	}


func set_ai_action(move_dir: Vector2, shoot_dir: Vector2) -> void:
	## Set the AI's desired action for this frame.
	ai_move_direction = move_dir
	ai_shoot_direction = shoot_dir


func enable_ai_control(enabled: bool) -> void:
	## Enable or disable AI control mode.
	ai_controlled = enabled
	if not enabled:
		ai_move_direction = Vector2.ZERO
		ai_shoot_direction = Vector2.ZERO
