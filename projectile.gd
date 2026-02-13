extends Area2D

@export var speed: float = 900.0  # Faster projectiles
@export var max_distance: float = 1200.0  # Longer range
var direction: Vector2 = Vector2.RIGHT
var start_position: Vector2
var is_piercing: bool = false
var owner_player: Node = null  # The player who fired this projectile
var owner_team_id: int = -1  # -1 = no team, 0+ = team index

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	start_position = position

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

	# Remove if traveled too far
	if position.distance_to(start_position) > max_distance:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("obstacle"):
		# Projectile hits obstacle and is destroyed
		queue_free()
		return

	if body.is_in_group("enemy"):
		var enemy_pos = body.global_position
		var points = body.get_point_value() if body.has_method("get_point_value") else 1
		if body.has_method("die"):
			body.die()
		else:
			body.queue_free()
		# Piercing projectiles don't disappear on enemy hit
		if not is_piercing:
			queue_free()
		# Notify owner player of kill for bonus points
		if owner_player:
			owner_player.enemy_killed.emit(enemy_pos, points)
		return

	# Agent PvP detection (team mode)
	if body.is_in_group("agent") and owner_team_id >= 0:
		if body != owner_player and body.get("team_id") != owner_team_id:
			body.take_pvp_hit(owner_player)
			if not is_piercing:
				queue_free()
