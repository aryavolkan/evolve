extends CharacterBody2D

## Lightweight AI agent for rtNEAT mode.
## Always AI-controlled. No particles, no timer label, no human input.

signal died(agent: CharacterBody2D)
signal enemy_killed(pos: Vector2, points: int)
signal powerup_collected_by_agent(agent: CharacterBody2D, type: String)
signal shot_fired(direction: Vector2)
signal pvp_hit_by(attacker: Node)

@export var speed: float = 300.0
@export var boosted_speed: float = 500.0
@export var shoot_cooldown: float = 0.3

# Identity
var agent_id: int = 0
var species_color: Color = Color.WHITE
var fitness: float = 0.0
var age: float = 0.0
var team_id: int = -1  # -1 = no team, 0 = team A, 1 = team B

# State
var lives: int = 3
var is_hit: bool = false
var is_invincible: bool = false
var is_speed_boosted: bool = false
var is_rapid_fire: bool = false
var is_piercing: bool = false
var has_shield: bool = false
var is_double_points: bool = false
var is_slow_active: bool = false
var can_shoot: bool = true
var is_dead: bool = false

# AI control (always AI-driven)
var ai_move_direction: Vector2 = Vector2.ZERO
var ai_shoot_direction: Vector2 = Vector2.ZERO

# Power-up timers
var speed_boost_time: float = 0.0
var invincibility_time: float = 0.0
var rapid_fire_time: float = 0.0
var piercing_time: float = 0.0

var projectile_scene: PackedScene = preload("res://projectile.tscn")

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if team_id >= 0:
		add_to_group("agent")
	sprite.modulate = species_color


func _physics_process(delta: float) -> void:
	if is_dead or is_hit:
		return

	update_powerup_timers(delta)

	var direction: Vector2 = ai_move_direction
	var shoot_dir: Vector2 = ai_shoot_direction
	ai_shoot_direction = Vector2.ZERO  # Reset after reading

	if direction != Vector2.ZERO:
		direction = direction.normalized()

	var current_speed = boosted_speed if is_speed_boosted else speed
	velocity = direction * current_speed
	move_and_slide()

	# Clamp to arena bounds
	var main = get_parent()
	if main and main.has_method("get_arena_bounds"):
		var bounds: Rect2 = main.get_arena_bounds()
		position.x = clampf(position.x, bounds.position.x, bounds.end.x)
		position.y = clampf(position.y, bounds.position.y, bounds.end.y)

	# Shooting
	if can_shoot and shoot_dir != Vector2.ZERO:
		shoot(shoot_dir)

	# Collision check from slide
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider and collider.is_in_group("enemy"):
			on_enemy_collision(collider)
			return


func update_powerup_timers(delta: float) -> void:
	if speed_boost_time > 0:
		speed_boost_time -= delta
		if speed_boost_time <= 0:
			end_speed_boost()

	if invincibility_time > 0:
		invincibility_time -= delta
		if invincibility_time <= 0:
			end_invincibility()

	if rapid_fire_time > 0:
		rapid_fire_time -= delta
		if rapid_fire_time <= 0:
			end_rapid_fire()

	if piercing_time > 0:
		piercing_time -= delta
		if piercing_time <= 0:
			end_piercing()


func shoot(direction: Vector2) -> void:
	var projectile = projectile_scene.instantiate()
	projectile.position = global_position
	projectile.direction = direction
	projectile.is_piercing = is_piercing
	projectile.owner_player = self
	if team_id >= 0:
		projectile.owner_team_id = team_id
		projectile.set_collision_mask_value(1, true)
	get_parent().add_child(projectile)
	shot_fired.emit(direction)

	can_shoot = false
	var cooldown = shoot_cooldown * 0.3 if is_rapid_fire else shoot_cooldown
	await get_tree().create_timer(cooldown).timeout
	can_shoot = true


func on_enemy_collision(enemy: Node) -> void:
	if is_invincible:
		var enemy_pos = enemy.global_position
		var points = enemy.get_point_value() if enemy.has_method("get_point_value") else 1
		enemy.queue_free()
		enemy_killed.emit(enemy_pos, points)
		return
	if has_shield:
		has_shield = false
		update_sprite_color()
		return
	_trigger_hit()


func take_pvp_hit(attacker: Node) -> void:
	## Handle being hit by an opposing team's projectile.
	if is_invincible:
		return
	if has_shield:
		has_shield = false
		update_sprite_color()
		return
	pvp_hit_by.emit(attacker)
	_trigger_hit()


func _trigger_hit() -> void:
	if is_hit:
		return
	is_hit = true
	lives -= 1
	if lives <= 0:
		is_dead = true
		visible = false
		set_physics_process(false)
		died.emit(self)
	else:
		# Respawn at arena center with invincibility
		var main = get_parent()
		if main and main.has_method("get_arena_bounds"):
			var bounds: Rect2 = main.get_arena_bounds()
			var center = bounds.position + bounds.size / 2.0
			position = center
		is_hit = false
		activate_invincibility(2.0)


func set_ai_action(move_dir: Vector2, shoot_dir: Vector2) -> void:
	ai_move_direction = move_dir
	ai_shoot_direction = shoot_dir


# Power-up activations (simplified, no particles)
func activate_speed_boost(duration: float) -> void:
	is_speed_boosted = true
	speed_boost_time = duration
	update_sprite_color()


func end_speed_boost() -> void:
	is_speed_boosted = false
	speed_boost_time = 0.0
	update_sprite_color()


func activate_invincibility(duration: float) -> void:
	is_invincible = true
	invincibility_time = duration
	update_sprite_color()


func end_invincibility() -> void:
	is_invincible = false
	invincibility_time = 0.0
	update_sprite_color()


func activate_rapid_fire(duration: float) -> void:
	is_rapid_fire = true
	rapid_fire_time = duration


func end_rapid_fire() -> void:
	is_rapid_fire = false
	rapid_fire_time = 0.0


func activate_piercing(duration: float) -> void:
	is_piercing = true
	piercing_time = duration


func end_piercing() -> void:
	is_piercing = false
	piercing_time = 0.0


func activate_shield() -> void:
	has_shield = true
	update_sprite_color()


func activate_double_points(duration: float) -> void:
	is_double_points = true
	# Auto-end after duration
	await get_tree().create_timer(duration).timeout
	is_double_points = false


const TEAM_COLORS: Array = [
	Color(0.3, 0.5, 1.0),  # Team A: Blue
	Color(1.0, 0.3, 0.3),  # Team B: Red
]

func update_sprite_color() -> void:
	## Tint sprite based on active effects, blend with species color.
	if is_invincible:
		sprite.modulate = Color(1, 0.9, 0.3, 1)
	elif is_speed_boosted:
		sprite.modulate = Color(0.5, 1, 0.8, 1)
	elif has_shield:
		sprite.modulate = Color(0.7, 0.7, 1, 1)
	else:
		if team_id >= 0 and team_id < TEAM_COLORS.size():
			sprite.modulate = species_color.lerp(TEAM_COLORS[team_id], 0.4)
		else:
			sprite.modulate = species_color


func reset_for_new_life() -> void:
	## Reset agent state for replacement (new genome).
	lives = 3
	fitness = 0.0
	age = 0.0
	is_hit = false
	is_dead = false
	is_invincible = false
	is_speed_boosted = false
	is_rapid_fire = false
	is_piercing = false
	has_shield = false
	is_double_points = false
	is_slow_active = false
	can_shoot = true
	speed_boost_time = 0.0
	invincibility_time = 0.0
	rapid_fire_time = 0.0
	piercing_time = 0.0
	visible = true
	set_physics_process(true)
	if team_id >= 0 and not is_in_group("agent"):
		add_to_group("agent")
	update_sprite_color()


func get_active_powerups() -> Dictionary:
	return {
		"SPEED": speed_boost_time,
		"INVINCIBLE": invincibility_time,
		"RAPID": rapid_fire_time,
		"PIERCING": piercing_time,
		"SHIELD": 1.0 if has_shield else 0.0,
	}
