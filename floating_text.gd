extends Node2D

var velocity: Vector2 = Vector2(0, -50)
var lifetime: float = 1.0

func _ready() -> void:
	# Start fade out
	var tween = create_tween()
	tween.tween_property($Label, "modulate:a", 0.0, lifetime)
	tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	position += velocity * delta

func setup(text: String, color: Color, pos: Vector2) -> void:
	$Label.text = text
	$Label.modulate = color
	global_position = pos
