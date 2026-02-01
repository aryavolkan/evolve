extends Node2D

var score: float = 0.0
var game_over: bool = false
var next_spawn_score: float = 50.0
var next_powerup_score: float = 30.0
var enemy_scene: PackedScene = preload("res://enemy.tscn")
var powerup_scene: PackedScene = preload("res://powerup.tscn")

const POWERUP_DURATION: float = 5.0
const SLOW_MULTIPLIER: float = 0.5

# Difficulty scaling
const BASE_ENEMY_SPEED: float = 150.0
const MAX_ENEMY_SPEED: float = 300.0
const BASE_SPAWN_INTERVAL: float = 50.0
const MIN_SPAWN_INTERVAL: float = 20.0
const DIFFICULTY_SCALE_SCORE: float = 500.0  # Score at which difficulty is maxed

@onready var score_label: Label = $CanvasLayer/UI/ScoreLabel
@onready var game_over_label: Label = $CanvasLayer/UI/GameOverLabel
@onready var powerup_label: Label = $CanvasLayer/UI/PowerUpLabel
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	print("Evolve app started!")
	get_tree().paused = false
	player.hit.connect(_on_player_hit)
	game_over_label.visible = false
	powerup_label.visible = false

func _process(delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().reload_current_scene()
		return

	score += delta * 10
	score_label.text = "Score: %d" % int(score)

	if score >= next_spawn_score:
		spawn_enemy()
		var spawn_interval = get_scaled_spawn_interval()
		next_spawn_score += spawn_interval

	if score >= next_powerup_score:
		spawn_powerup()
		next_powerup_score += 40.0

func get_difficulty_factor() -> float:
	return clampf(score / DIFFICULTY_SCALE_SCORE, 0.0, 1.0)

func get_scaled_enemy_speed() -> float:
	var factor = get_difficulty_factor()
	return lerpf(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, factor)

func get_scaled_spawn_interval() -> float:
	var factor = get_difficulty_factor()
	return lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, factor)

func spawn_enemy() -> void:
	var enemy = enemy_scene.instantiate()
	enemy.speed = get_scaled_enemy_speed()

	# Spawn at random edge position
	var side = randi() % 4
	var pos: Vector2
	match side:
		0: pos = Vector2(randf_range(0, 1280), 0)        # Top
		1: pos = Vector2(randf_range(0, 1280), 720)      # Bottom
		2: pos = Vector2(0, randf_range(0, 720))         # Left
		3: pos = Vector2(1280, randf_range(0, 720))      # Right

	enemy.position = pos
	add_child(enemy)

func spawn_powerup() -> void:
	var powerup = powerup_scene.instantiate()

	# Random position away from edges
	powerup.position = Vector2(
		randf_range(100, 1180),
		randf_range(100, 620)
	)

	# Random power-up type
	var type_index = randi() % 4
	powerup.set_type(type_index)
	powerup.collected.connect(_on_powerup_collected)
	add_child(powerup)

func _on_powerup_collected(type: String) -> void:
	show_powerup_message(type)

	match type:
		"SPEED BOOST":
			player.activate_speed_boost(POWERUP_DURATION)
		"INVINCIBILITY":
			player.activate_invincibility(POWERUP_DURATION)
		"SLOW ENEMIES":
			activate_slow_enemies()
		"SCREEN CLEAR":
			clear_all_enemies()

func show_powerup_message(type: String) -> void:
	powerup_label.text = type + "!"
	powerup_label.visible = true
	await get_tree().create_timer(2.0).timeout
	powerup_label.visible = false

func activate_slow_enemies() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		enemy.speed *= SLOW_MULTIPLIER

	await get_tree().create_timer(POWERUP_DURATION).timeout

	# Restore enemy speeds
	enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		enemy.speed /= SLOW_MULTIPLIER

func clear_all_enemies() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		enemy.queue_free()
	# Bonus points for screen clear
	score += 25

func _on_player_hit() -> void:
	game_over = true
	game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
	game_over_label.visible = true
	get_tree().paused = true
