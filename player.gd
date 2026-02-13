extends "res://combat_entity.gd"

signal hit
signal powerup_timer_updated(powerup_type: String, time_left: float)

var is_slow_active: bool = false
var is_freeze_active: bool = false
var is_double_points: bool = false

var slow_time: float = 0.0
var freeze_time: float = 0.0
var double_points_time: float = 0.0

var death_effect_scene: PackedScene = preload("res://death_effect.tscn")

@onready var speed_particles: CPUParticles2D = $SpeedParticles
@onready var invincibility_particles: CPUParticles2D = $InvincibilityParticles
@onready var slow_particles: CPUParticles2D = $SlowParticles
@onready var timer_label: RichTextLabel = $TimerLabel


func _ready() -> void:
	speed_particles.emitting = false
	invincibility_particles.emitting = false
	slow_particles.emitting = false
	timer_label.visible = false
	ai_controlled = false


func get_move_direction() -> Vector2:
	if ai_controlled:
		return _consume_ai_move_direction()

	var direction := Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1

	return direction


func get_shoot_direction() -> Vector2:
	if ai_controlled:
		return _consume_ai_shoot_direction()

	if not can_shoot:
		return Vector2.ZERO

	if Input.is_action_just_pressed("shoot_up"):
		return Vector2.UP
	elif Input.is_action_just_pressed("shoot_down"):
		return Vector2.DOWN
	elif Input.is_action_just_pressed("shoot_left"):
		return Vector2.LEFT
	elif Input.is_action_just_pressed("shoot_right"):
		return Vector2.RIGHT

	return Vector2.ZERO


func after_powerup_timers_updated(_delta: float) -> void:
	update_timer_display()


func on_powerup_timer_changed(powerup_type: String, time_left: float) -> void:
	powerup_timer_updated.emit(powerup_type, max(time_left, 0.0))


func process_additional_powerup_timers(delta: float) -> void:
	if slow_time > 0.0:
		slow_time -= delta
		powerup_timer_updated.emit("SLOW", slow_time)
		if slow_time <= 0.0:
			end_slow_effect()

	if freeze_time > 0.0:
		freeze_time -= delta
		powerup_timer_updated.emit("FREEZE", freeze_time)
		if freeze_time <= 0.0:
			end_freeze_effect()

	if double_points_time > 0.0:
		double_points_time -= delta
		powerup_timer_updated.emit("DOUBLE", double_points_time)
		if double_points_time <= 0.0:
			end_double_points()


func on_speed_boost_started(_duration: float) -> void:
	speed_particles.emitting = true


func on_speed_boost_ended() -> void:
	speed_particles.emitting = false


func on_invincibility_started(_duration: float) -> void:
	invincibility_particles.emitting = true


func on_invincibility_ended() -> void:
	invincibility_particles.emitting = false


func on_shield_activated() -> void:
	sprite.modulate = get_shield_color()
	_flash_shield_color()


func _flash_shield_color() -> void:
	await get_tree().create_timer(0.3).timeout
	update_sprite_color()


func get_additional_active_powerups() -> Dictionary:
	return {
		"SLOW": slow_time,
		"FREEZE": freeze_time,
		"DOUBLE": double_points_time,
	}


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


func activate_slow_effect(duration: float) -> void:
	is_slow_active = true
	slow_time = duration
	slow_particles.emitting = true


func end_slow_effect() -> void:
	is_slow_active = false
	slow_time = 0.0
	slow_particles.emitting = false
	powerup_timer_updated.emit("SLOW", 0.0)


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


func respawn(pos: Vector2, invincibility_duration: float) -> void:
	position = pos
	is_hit = false
	activate_invincibility(invincibility_duration)


func trigger_screen_clear_effect() -> void:
	$ScreenClearParticles.restart()
	$ScreenClearParticles.emitting = true


func _trigger_hit() -> void:
	if is_hit:
		return
	is_hit = true
	if is_inside_tree():
		var effect = death_effect_scene.instantiate()
		effect.setup(global_position, 40.0, Color(1, 0.3, 0.3, 0.8))
		get_parent().add_child(effect)
	hit.emit()
