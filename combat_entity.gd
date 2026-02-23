extends CharacterBody2D

signal enemy_killed(pos: Vector2, points: int)
signal shot_fired(direction: Vector2)

@export var speed: float = 300.0
@export var boosted_speed: float = 500.0
@export var shoot_cooldown: float = 0.3

var is_hit: bool = false
var is_invincible: bool = false
var is_speed_boosted: bool = false
var is_rapid_fire: bool = false
var is_piercing: bool = false
var has_shield: bool = false
var can_shoot: bool = true
var ai_controlled: bool = false

var speed_boost_time: float = 0.0
var invincibility_time: float = 0.0
var rapid_fire_time: float = 0.0
var piercing_time: float = 0.0

var projectile_scene: PackedScene = preload("res://projectile.tscn")
var projectile_pool: RefCounted = null  ## ObjectPool for projectile recycling
var ai_move_direction: Vector2 = Vector2.ZERO
var ai_shoot_direction: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D


func _physics_process(delta: float) -> void:
    if not can_process_physics():
        return

    before_physics_process(delta)
    update_powerup_timers(delta)
    after_powerup_timers_updated(delta)

    var move_dir := get_move_direction()
    var shoot_dir := get_shoot_direction()

    apply_movement(move_dir)
    after_movement(delta)

    if can_shoot and shoot_dir != Vector2.ZERO:
        shoot(shoot_dir)

    after_physics_process(delta)


func can_process_physics() -> bool:
    return not is_hit


func before_physics_process(_delta: float) -> void:
    pass


func after_powerup_timers_updated(_delta: float) -> void:
    pass


func after_movement(_delta: float) -> void:
    pass


func after_physics_process(_delta: float) -> void:
    pass


func get_move_direction() -> Vector2:
    if ai_controlled:
        return _consume_ai_move_direction()
    return Vector2.ZERO


func get_shoot_direction() -> Vector2:
    if ai_controlled:
        return _consume_ai_shoot_direction()
    return Vector2.ZERO


func _consume_ai_move_direction() -> Vector2:
    var direction := ai_move_direction
    ai_move_direction = Vector2.ZERO
    return direction


func _consume_ai_shoot_direction() -> Vector2:
    var direction := ai_shoot_direction
    ai_shoot_direction = Vector2.ZERO
    return direction


func apply_movement(direction: Vector2) -> void:
    var normalized := direction
    if normalized != Vector2.ZERO:
        normalized = normalized.normalized()

    var current_speed := (boosted_speed if is_speed_boosted else speed) * get_speed_multiplier()
    velocity = normalized * current_speed
    move_and_slide()
    clamp_to_arena_bounds()
    check_enemy_collisions()


func get_speed_multiplier() -> float:
    return 1.0


func clamp_to_arena_bounds() -> void:
    var main = get_parent()
    if main and main.has_method("get_arena_bounds"):
        var bounds: Rect2 = main.get_arena_bounds()
        position.x = clampf(position.x, bounds.position.x, bounds.end.x)
        position.y = clampf(position.y, bounds.position.y, bounds.end.y)


func check_enemy_collisions() -> void:
    for i in get_slide_collision_count():
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()
        if collider and collider.is_in_group("enemy"):
            on_enemy_collision(collider)
            return


func shoot(direction: Vector2) -> void:
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
    await get_tree().create_timer(cooldown).timeout
    can_shoot = true


func configure_projectile(_projectile: Node) -> void:
    pass


func on_enemy_collision(enemy: Node) -> void:
    if is_invincible:
        var enemy_pos = enemy.global_position
        var points = enemy.get_point_value() if enemy.has_method("get_point_value") else 1
        if enemy.has_method("die"):
            enemy.die()
        else:
            enemy.queue_free()
        enemy_killed.emit(enemy_pos, points)
        return

    if has_shield:
        has_shield = false
        on_shield_broken()
        update_sprite_color()
        return

    _trigger_hit()


func _trigger_hit() -> void:
    pass


func update_powerup_timers(delta: float) -> void:
    if speed_boost_time > 0.0:
        speed_boost_time -= delta
        on_powerup_timer_changed("SPEED", speed_boost_time)
        if speed_boost_time <= 0.0:
            end_speed_boost()

    if invincibility_time > 0.0:
        invincibility_time -= delta
        on_powerup_timer_changed("INVINCIBLE", invincibility_time)
        if invincibility_time <= 0.0:
            end_invincibility()

    if rapid_fire_time > 0.0:
        rapid_fire_time -= delta
        on_powerup_timer_changed("RAPID", rapid_fire_time)
        if rapid_fire_time <= 0.0:
            end_rapid_fire()

    if piercing_time > 0.0:
        piercing_time -= delta
        on_powerup_timer_changed("PIERCING", piercing_time)
        if piercing_time <= 0.0:
            end_piercing()

    process_additional_powerup_timers(delta)


func process_additional_powerup_timers(_delta: float) -> void:
    pass


func on_powerup_timer_changed(_powerup_type: String, _time_left: float) -> void:
    pass


func activate_speed_boost(duration: float) -> void:
    is_speed_boosted = true
    speed_boost_time = duration
    on_speed_boost_started(duration)
    update_sprite_color()


func end_speed_boost() -> void:
    is_speed_boosted = false
    speed_boost_time = 0.0
    on_speed_boost_ended()
    on_powerup_timer_changed("SPEED", 0.0)
    update_sprite_color()


func activate_invincibility(duration: float) -> void:
    is_invincible = true
    invincibility_time = duration
    on_invincibility_started(duration)
    update_sprite_color()


func end_invincibility() -> void:
    is_invincible = false
    invincibility_time = 0.0
    on_invincibility_ended()
    on_powerup_timer_changed("INVINCIBLE", 0.0)
    update_sprite_color()


func activate_rapid_fire(duration: float) -> void:
    is_rapid_fire = true
    rapid_fire_time = duration
    on_rapid_fire_started(duration)


func end_rapid_fire() -> void:
    is_rapid_fire = false
    rapid_fire_time = 0.0
    on_rapid_fire_ended()
    on_powerup_timer_changed("RAPID", 0.0)


func activate_piercing(duration: float) -> void:
    is_piercing = true
    piercing_time = duration
    on_piercing_started(duration)


func end_piercing() -> void:
    is_piercing = false
    piercing_time = 0.0
    on_piercing_ended()
    on_powerup_timer_changed("PIERCING", 0.0)


func activate_shield() -> void:
    has_shield = true
    on_shield_activated()
    update_sprite_color()


func update_sprite_color() -> void:
    if not sprite:
        return

    var target_color := get_default_sprite_color()
    if is_invincible:
        target_color = get_invincible_color()
    elif is_speed_boosted:
        target_color = get_speed_boost_color()
    elif has_shield:
        target_color = get_shield_color()

    sprite.modulate = target_color


func get_default_sprite_color() -> Color:
    return Color(1, 1, 1, 1)


func get_invincible_color() -> Color:
    return Color(1, 0.9, 0.3, 1)


func get_speed_boost_color() -> Color:
    return Color(0.5, 1, 0.8, 1)


func get_shield_color() -> Color:
    return Color(0.7, 0.7, 1, 1)


func on_speed_boost_started(_duration: float) -> void:
    pass


func on_speed_boost_ended() -> void:
    pass


func on_invincibility_started(_duration: float) -> void:
    pass


func on_invincibility_ended() -> void:
    pass


func on_rapid_fire_started(_duration: float) -> void:
    pass


func on_rapid_fire_ended() -> void:
    pass


func on_piercing_started(_duration: float) -> void:
    pass


func on_piercing_ended() -> void:
    pass


func on_shield_activated() -> void:
    pass


func on_shield_broken() -> void:
    pass


func get_active_powerups() -> Dictionary:
    var actives: Dictionary = {
        "SPEED": speed_boost_time,
        "INVINCIBLE": invincibility_time,
        "RAPID": rapid_fire_time,
        "PIERCING": piercing_time,
        "SHIELD": 1.0 if has_shield else 0.0,
    }
    actives.merge(get_additional_active_powerups())
    return actives


func get_additional_active_powerups() -> Dictionary:
    return {}


func set_ai_action(move_dir: Vector2, shoot_dir: Vector2) -> void:
    ai_move_direction = move_dir
    ai_shoot_direction = shoot_dir


func enable_ai_control(enabled: bool) -> void:
    ai_controlled = enabled
    if not enabled:
        ai_move_direction = Vector2.ZERO
        ai_shoot_direction = Vector2.ZERO
