extends "res://combat_entity.gd"

## Lightweight AI agent for rtNEAT mode.
## Always AI-controlled. No particles, no timer label, no human input.

signal died(agent: CharacterBody2D)
signal powerup_collected_by_agent(agent: CharacterBody2D, type: String)
signal pvp_hit_by(attacker: Node)

var agent_id: int = 0
var species_color: Color = Color.WHITE
var fitness: float = 0.0
var age: float = 0.0
var team_id: int = -1  # -1 = no team, 0 = team A, 1 = team B

var lives: int = 3
var is_double_points: bool = false
var is_slow_active: bool = false
var is_dead: bool = false

var death_effect_scene: PackedScene = preload("res://death_effect.tscn")

const TEAM_COLORS: Array = [
    Color(0.3, 0.5, 1.0),  # Team A: Blue
    Color(1.0, 0.3, 0.3),  # Team B: Red
]


func _ready() -> void:
    ai_controlled = true
    if team_id >= 0:
        add_to_group("agent")
    sprite.modulate = species_color


func can_process_physics() -> bool:
    return not is_hit and not is_dead


func configure_projectile(projectile: Node) -> void:
    if team_id < 0:
        return
    projectile.owner_team_id = team_id
    if projectile.has_method("set_collision_mask_value"):
        projectile.set_collision_mask_value(1, true)


func get_default_sprite_color() -> Color:
    if team_id >= 0 and team_id < TEAM_COLORS.size():
        return species_color.lerp(TEAM_COLORS[team_id], 0.4)
    return species_color


func take_pvp_hit(attacker: Node) -> void:
    if is_invincible:
        return
    if has_shield:
        has_shield = false
        on_shield_broken()
        update_sprite_color()
        return
    pvp_hit_by.emit(attacker)
    _trigger_hit()


func _trigger_hit() -> void:
    if is_hit:
        return
    is_hit = true
    if is_inside_tree():
        var effect = death_effect_scene.instantiate()
        effect.setup(global_position, 20.0, Color(1, 0.3, 0.3, 0.6))
        get_parent().add_child(effect)
    lives -= 1
    if lives <= 0:
        is_dead = true
        visible = false
        set_physics_process(false)
        died.emit(self)
    else:
        var main = get_parent()
        if main and main.has_method("get_arena_bounds"):
            var bounds: Rect2 = main.get_arena_bounds()
            var center = bounds.position + bounds.size / 2.0
            position = center
        is_hit = false
        activate_invincibility(2.0)


func activate_double_points(duration: float) -> void:
    is_double_points = true
    await get_tree().create_timer(duration).timeout
    is_double_points = false


func reset_for_new_life() -> void:
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
