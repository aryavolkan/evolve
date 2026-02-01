extends Area2D

signal collected(type: String)

enum Type { SPEED_BOOST, INVINCIBILITY, SLOW_ENEMIES, SCREEN_CLEAR }

@export var type: Type = Type.SPEED_BOOST
var colors: Dictionary = {
	Type.SPEED_BOOST: Color(0, 1, 0.5, 1),      # Cyan-green
	Type.INVINCIBILITY: Color(1, 0.8, 0, 1),    # Gold
	Type.SLOW_ENEMIES: Color(0.6, 0.2, 1, 1),   # Purple
	Type.SCREEN_CLEAR: Color(1, 0.3, 0.3, 1)    # Red-orange
}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	$ColorRect.color = colors[type]

func set_type(new_type: Type) -> void:
	type = new_type
	if has_node("ColorRect"):
		$ColorRect.color = colors[type]

func get_type_name() -> String:
	match type:
		Type.SPEED_BOOST: return "SPEED BOOST"
		Type.INVINCIBILITY: return "INVINCIBILITY"
		Type.SLOW_ENEMIES: return "SLOW ENEMIES"
		Type.SCREEN_CLEAR: return "SCREEN CLEAR"
	return ""

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		collected.emit(get_type_name())
		queue_free()
