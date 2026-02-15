extends RefCounted

## Controls the player using a neural network.
## Replaces human input with network-driven decisions.

var NeuralNetworkScript = preload("res://ai/neural_network.gd")
var SensorScript = preload("res://ai/sensor.gd")

var network = null
var sensor = null
var player: CharacterBody2D

# Output indices
const OUT_MOVE_X := 0
const OUT_MOVE_Y := 1
const OUT_SHOOT_UP := 2
const OUT_SHOOT_DOWN := 3
const OUT_SHOOT_LEFT := 4
const OUT_SHOOT_RIGHT := 5

# Thresholds
const SHOOT_THRESHOLD := 0.0  # Let networks learn shooting from generation 1
const MOVE_DEADZONE := 0.05   # Small deadzone to filter noise


func _init(p_network = null) -> void:
	sensor = SensorScript.new()

	if p_network:
		network = p_network
	else:
		# Create default network matching sensor input size
		network = NeuralNetworkScript.new(sensor.TOTAL_INPUTS, 32, 6)


func set_player(p: CharacterBody2D) -> void:
	player = p
	sensor.set_player(p)


func set_network(net) -> void:
	network = net


func get_action() -> Dictionary:
	## Run the network and return the action to take.
	## Returns: {move_direction: Vector2, shoot_direction: Vector2}

	var inputs: PackedFloat32Array = sensor.get_inputs()
	var outputs: PackedFloat32Array = network.forward(inputs)

	# Movement direction (direct mapping from network outputs)
	var move_dir := Vector2(outputs[OUT_MOVE_X], outputs[OUT_MOVE_Y])
	if move_dir.length() < MOVE_DEADZONE:
		move_dir = Vector2.ZERO
	elif move_dir.length() > 1.0:
		move_dir = move_dir.normalized()

	# Shooting direction (pick strongest above threshold — no allocation)
	var shoot_dir := Vector2.ZERO
	var best_shoot := SHOOT_THRESHOLD
	if outputs[OUT_SHOOT_UP] > best_shoot:
		best_shoot = outputs[OUT_SHOOT_UP]
		shoot_dir = Vector2.UP
	if outputs[OUT_SHOOT_DOWN] > best_shoot:
		best_shoot = outputs[OUT_SHOOT_DOWN]
		shoot_dir = Vector2.DOWN
	if outputs[OUT_SHOOT_LEFT] > best_shoot:
		best_shoot = outputs[OUT_SHOOT_LEFT]
		shoot_dir = Vector2.LEFT
	if outputs[OUT_SHOOT_RIGHT] > best_shoot:
		best_shoot = outputs[OUT_SHOOT_RIGHT]
		shoot_dir = Vector2.RIGHT

	return {
		"move_direction": move_dir,
		"shoot_direction": shoot_dir
	}


func get_inputs() -> PackedFloat32Array:
	## Expose sensor inputs for debugging.
	return sensor.get_inputs()


func get_outputs() -> PackedFloat32Array:
	## Get the last network outputs for debugging.
	var inputs: PackedFloat32Array = sensor.get_inputs()
	return network.forward(inputs)
