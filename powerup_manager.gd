## Manages all powerup effects and state
extends RefCounted
class_name PowerupManager

# Constants
const POWERUP_DURATION: float = 5.0
const SLOW_MULTIPLIER: float = 0.5
const BOMB_RADIUS: float = 600.0  # Radius of bomb explosion

# State tracking
var slow_active: bool = false
var freeze_active: bool = false
var double_points_active: bool = false

# References to main game systems
var main_game: Node2D
var player: Node2D
var score_mgr
var spawn_mgr

func setup(p_main_game: Node2D, p_player: Node2D, p_score_mgr, p_spawn_mgr) -> void:
	"""Initialize the powerup manager with references to game systems."""
	main_game = p_main_game
	player = p_player
	score_mgr = p_score_mgr
	spawn_mgr = p_spawn_mgr

func handle_powerup_collected(type: String, collector: Node2D = null) -> void:
	"""Handle powerup collection and apply effects."""
	# Route to the collector; fallback to main player for backward compat
	var target = collector if collector else player
	main_game.powerups_collected += 1
	show_powerup_message(type)

	# Bonus for collecting powerup
	var multiplier = 2 if double_points_active else 1
	var bonus = score_mgr.POWERUP_COLLECT_BONUS * multiplier
	main_game.score += bonus
	main_game.score_from_powerups += bonus
	var bonus_text = "+%d" % bonus
	main_game.spawn_floating_text(bonus_text, Color(0, 1, 0.5, 1), target.position)

	# Notify agent of powerup collection (for rtNEAT fitness tracking)
	if collector and collector != player and collector.has_signal("powerup_collected_by_agent"):
		collector.powerup_collected_by_agent.emit(collector, type)

	match type:
		"SPEED BOOST":
			target.activate_speed_boost(POWERUP_DURATION)
		"INVINCIBILITY":
			target.activate_invincibility(POWERUP_DURATION)
		"SLOW ENEMIES":
			activate_slow_enemies()
		"SCREEN CLEAR":
			clear_all_enemies()
		"RAPID FIRE":
			target.activate_rapid_fire(POWERUP_DURATION)
		"PIERCING":
			target.activate_piercing(POWERUP_DURATION)
		"SHIELD":
			target.activate_shield()
		"FREEZE":
			activate_freeze_enemies()
		"DOUBLE POINTS":
			activate_double_points()
		"BOMB":
			explode_nearby_enemies(target.position)

func activate_slow_enemies() -> void:
	"""Slow all current enemies."""
	# Apply slow to all current enemies if not already active
	if not slow_active:
		for enemy in get_local_enemies():
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.apply_slow(SLOW_MULTIPLIER)
	slow_active = true
	if player.is_physics_processing():
		player.activate_slow_effect(POWERUP_DURATION)
	else:
		# rtNEAT mode: player physics disabled, use standalone timer
		main_game.get_tree().create_timer(POWERUP_DURATION).timeout.connect(end_slow_enemies)

func end_slow_enemies() -> void:
	"""End slow effect on all enemies."""
	if slow_active:
		slow_active = false
		for enemy in get_local_enemies():
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.remove_slow(SLOW_MULTIPLIER)

func activate_freeze_enemies() -> void:
	"""Freeze all current enemies completely."""
	# Freeze completely stops enemies (unlike slow which is 50%)
	if not freeze_active:
		for enemy in get_local_enemies():
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.apply_freeze()
	freeze_active = true
	if player.is_physics_processing():
		player.activate_freeze_effect(POWERUP_DURATION)
	else:
		# rtNEAT mode: player physics disabled, use standalone timer
		main_game.get_tree().create_timer(POWERUP_DURATION).timeout.connect(end_freeze_enemies)

func end_freeze_enemies() -> void:
	"""End freeze effect on all enemies."""
	if freeze_active:
		freeze_active = false
		for enemy in get_local_enemies():
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.remove_freeze()

func activate_double_points() -> void:
	"""Activate double points scoring."""
	double_points_active = true
	if player.is_physics_processing():
		player.activate_double_points(POWERUP_DURATION)
	else:
		# rtNEAT mode: player physics disabled, use standalone timer
		main_game.get_tree().create_timer(POWERUP_DURATION).timeout.connect(end_double_points)

func end_double_points() -> void:
	"""End double points scoring."""
	double_points_active = false

func clear_all_enemies() -> void:
	"""Clear all enemies from the screen and award points."""
	if player.is_physics_processing():
		player.trigger_screen_clear_effect()
	var local_enemies = get_local_enemies()
	var total_points = 0
	for enemy in local_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			if enemy.has_method("get_point_value"):
				total_points += enemy.get_point_value() * score_mgr.KILL_MULTIPLIER
			else:
				total_points += score_mgr.KILL_MULTIPLIER
			enemy.die()

	# Bonus points for screen clear (scaled piece values + flat bonus)
	if total_points > 0:
		total_points += score_mgr.SCREEN_CLEAR_BONUS
		main_game.score += total_points
		main_game.spawn_floating_text("+%d CLEAR!" % total_points, Color(1, 0.3, 0.3, 1), player.position + Vector2(0, -50))

	# Prevent immediate respawning - set cooldown and advance spawn threshold
	main_game.screen_clear_cooldown = main_game.SCREEN_CLEAR_SPAWN_DELAY
	main_game.next_spawn_score = main_game.score + main_game.get_scaled_spawn_interval()

func explode_nearby_enemies(center_pos: Vector2 = Vector2.ZERO) -> void:
	"""Kill all enemies within BOMB_RADIUS of center_pos (defaults to player)."""
	if center_pos == Vector2.ZERO:
		center_pos = player.position
	var local_enemies = get_local_enemies()
	var total_points = 0
	var killed_count = 0

	for enemy in local_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			var distance = center_pos.distance_to(enemy.position)
			if distance <= BOMB_RADIUS:
				if enemy.has_method("get_point_value"):
					total_points += enemy.get_point_value() * score_mgr.KILL_MULTIPLIER
				else:
					total_points += score_mgr.KILL_MULTIPLIER
				killed_count += 1
				enemy.die()

	# Award points and show feedback
	if total_points > 0:
		var multiplier = 2 if double_points_active else 1
		total_points *= multiplier
		main_game.score += total_points
		main_game.score_from_kills += total_points
		main_game.spawn_floating_text("+%d BOMB!" % total_points, Color(1, 0.5, 0, 1), center_pos + Vector2(0, -50))

func handle_powerup_timer_updated(powerup_type: String, time_left: float) -> void:
	"""Handle powerup timer updates and end effects when expired."""
	# Handle slow enemies ending
	if powerup_type == "SLOW" and time_left <= 0:
		end_slow_enemies()
	# Handle freeze enemies ending
	if powerup_type == "FREEZE" and time_left <= 0:
		end_freeze_enemies()
	# Handle double points ending
	if powerup_type == "DOUBLE" and time_left <= 0:
		end_double_points()

func show_powerup_message(type: String) -> void:
	"""Display powerup collection message."""
	main_game.powerup_label.text = type + "!"
	main_game.powerup_label.visible = true
	await main_game.get_tree().create_timer(2.0).timeout
	main_game.powerup_label.visible = false

func is_double_points_active() -> bool:
	"""Check if double points is currently active."""
	return double_points_active

func get_score_multiplier() -> float:
	"""Get current score multiplier based on active powerups."""
	return 2.0 if double_points_active else 1.0

func get_local_enemies() -> Array:
	"""Get array of local enemies from spawn manager."""
	return spawn_mgr.get_local_enemies()