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

# Milestone rewards system
const MilestoneRewardsScript = preload("res://milestone_rewards.gd")
var milestone_rewards = null  # MilestoneRewardsScript instance
var is_training_mode: bool = false

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
	
	# Initialize milestone rewards if not already set
	if not milestone_rewards:
		milestone_rewards = MilestoneRewardsScript.new()
		milestone_rewards.tier_changed.connect(_on_milestone_tier_changed)


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


var _respawn_flash_tween: Tween = null

func respawn(pos: Vector2, invincibility_duration: float) -> void:
	position = pos
	is_hit = false
	activate_invincibility(invincibility_duration)
	_start_respawn_flash(invincibility_duration)

func _start_respawn_flash(duration: float) -> void:
	_stop_respawn_flash()
	_respawn_flash_tween = create_tween()
	_respawn_flash_tween.set_loops(int(duration / 0.2))
	_respawn_flash_tween.tween_property(sprite, "modulate:a", 0.3, 0.1)
	_respawn_flash_tween.tween_property(sprite, "modulate:a", 1.0, 0.1)
	_respawn_flash_tween.finished.connect(_stop_respawn_flash)

func _stop_respawn_flash() -> void:
	if _respawn_flash_tween and _respawn_flash_tween.is_valid():
		_respawn_flash_tween.kill()
	_respawn_flash_tween = null
	if sprite:
		sprite.modulate.a = 1.0

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


# Milestone rewards integration
func get_speed_multiplier() -> float:
	## Override from combat_entity to apply milestone speed bonus.
	if milestone_rewards:
		return milestone_rewards.get_speed_multiplier()
	return 1.0


func after_physics_process(delta: float) -> void:
	## Update milestone visual effects.
	if milestone_rewards and milestone_rewards.current_tier == 4:
		# Legendary tier: animated rainbow effect
		if DisplayServer.get_screen_count() > 0:  # Only if display is available
			update_sprite_color()
			milestone_rewards.rainbow_time += delta * 2.0


func shoot(direction: Vector2) -> void:
	## Override shoot to apply cooldown multiplier.
	var projectile: Node
	if projectile_pool:
		projectile = projectile_pool.acquire()
		projectile.reset(global_position, direction, self, -1, is_piercing)
	else:
		projectile = projectile_scene.instantiate()
		projectile.position = global_position
		projectile.direction = direction
		projectile.is_piercing = is_piercing
		projectile.owner_player = self
		get_parent().add_child(projectile)
	projectile.pool = projectile_pool
	configure_projectile(projectile)
	shot_fired.emit(direction)

	can_shoot = false
	var cooldown = shoot_cooldown * 0.3 if is_rapid_fire else shoot_cooldown
	
	# Apply milestone cooldown multiplier
	if milestone_rewards:
		cooldown *= milestone_rewards.get_cooldown_multiplier()
	
	await get_tree().create_timer(cooldown).timeout
	can_shoot = true


func update_sprite_color() -> void:
	## Override to apply milestone tier colors.
	if not sprite:
		return

	var target_color := get_default_sprite_color()
	
	# Priority: invincible > speed boost > shield > milestone
	if is_invincible:
		target_color = get_invincible_color()
	elif is_speed_boosted:
		target_color = get_speed_boost_color()
	elif has_shield:
		target_color = get_shield_color()
	elif milestone_rewards:
		# Apply milestone tier color
		if milestone_rewards.current_tier == 4:
			# Legendary rainbow effect
			target_color = milestone_rewards.get_tier_color()
		elif milestone_rewards.current_tier > 0:
			# Other tiers: use predefined colors
			target_color = milestone_rewards.get_tier_color()

	sprite.modulate = target_color


func update_fitness_milestone(fitness: float) -> void:
	## Update the milestone rewards based on current fitness.
	if not milestone_rewards:
		milestone_rewards = MilestoneRewardsScript.new()
		milestone_rewards.tier_changed.connect(_on_milestone_tier_changed)
	
	milestone_rewards.update_fitness(fitness)


func _on_milestone_tier_changed(new_tier: int, tier_name: String) -> void:
	## Handle milestone tier changes.
	if not is_training_mode:
		print("Milestone tier changed to: %s (Tier %d)" % [tier_name, new_tier])
	
	# Apply size scaling
	if sprite and DisplayServer.get_screen_count() > 0:
		var scale_mult = milestone_rewards.get_size_scale()
		sprite.scale = Vector2.ONE * scale_mult
		
		# Also scale collision shape if it exists
		var collision = find_child("CollisionShape2D", false)
		if collision:
			collision.scale = Vector2.ONE * scale_mult
	
	# Update visual color
	update_sprite_color()
	
	# TODO: Add particle trail effects for higher tiers
	# This would require checking if GPUParticles2D nodes exist first


func set_training_mode(enabled: bool) -> void:
	## Enable or disable training mode optimizations.
	is_training_mode = enabled
