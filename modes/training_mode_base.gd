extends RefCounted
class_name TrainingModeBase

## Base class for training manager modes.
## Each mode implements enter/exit/process/handle_input.
## ctx is a reference to the training_manager node.

var ctx  # training_manager reference


func enter(context) -> void:
	ctx = context


func exit() -> void:
	pass


func process(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass


func get_eval_states() -> Array:
	return []
