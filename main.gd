extends Node2D

var score: float = 0.0
var game_over: bool = false
var next_spawn_score: float = 50.0
var enemy_scene: PackedScene = preload("res://enemy.tscn")

@onready var score_label: Label = $CanvasLayer/UI/ScoreLabel
@onready var game_over_label: Label = $CanvasLayer/UI/GameOverLabel
@onready var player: CharacterBody2D = $Player

func _ready() -> void:
	print("Evolve app started!")
	get_tree().paused = false
	player.hit.connect(_on_player_hit)
	game_over_label.visible = false

func _process(delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().reload_current_scene()
		return

	score += delta * 10
	score_label.text = "Score: %d" % int(score)

	if score >= next_spawn_score:
		spawn_enemy()
		next_spawn_score += 50.0

func spawn_enemy() -> void:
	var enemy = enemy_scene.instantiate()

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

func _on_player_hit() -> void:
	game_over = true
	game_over_label.text = "GAME OVER\nFinal Score: %d\nPress SPACE to restart" % int(score)
	game_over_label.visible = true
	get_tree().paused = true
