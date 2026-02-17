extends RefCounted

## Controls the player using a neural network.
## Replaces human input with network-driven decisions.

var SensorScript = preload("res://ai/sensor.gd")
var NNFactory = preload("res://ai/neural_network_factory.gd")

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

# Cache outputs array to avoid allocations
var _cached_outputs: PackedFloat32Array


func _init(p_network = null) -> void:
	sensor = SensorScript.new()
	_cached_outputs.resize(6)

	if p_network:
		network = p_network
	else:
		# Use factory to get Rust backend when available (5-15x faster)
		network = NNFactory.create(sensor.TOTAL_INPUTS, 32, 6)


func set_player(p: CharacterBody2D) -> void:
	player = p
	sensor.set_player(p)


func set_network(net) -> void:
	network = net


func get_action() -> Dictionary:
	## Run the network and return the action to take.
	## Returns: {move_direction: Vector2, shoot_direction: Vector2}
	## Optimized to reduce allocations in hot path (runs 600+ times/sec)

	var inputs: PackedFloat32Array = sensor.get_inputs()
	var outputs: PackedFloat32Array = network.forward(inputs)
	return _process_outputs(outputs)


func _process_outputs(outputs: PackedFloat32Array) -> Dictionary:
	## Process network outputs into actions. Exposed for batch processing.
	## Returns: {move_direction: Vector2, shoot_direction: Vector2}
	_cached_outputs = outputs

	# Movement direction (direct mapping from network outputs)
	var move_x: float = _cached_outputs[OUT_MOVE_X]
	var move_y: float = _cached_outputs[OUT_MOVE_Y]
	var move_len_sq: float = move_x * move_x + move_y * move_y
	
	var move_dir: Vector2
	if move_len_sq < MOVE_DEADZONE * MOVE_DEADZONE:
		move_dir = Vector2.ZERO
	elif move_len_sq > 1.0:
		var inv_len = 1.0 / sqrt(move_len_sq)
		move_dir = Vector2(move_x * inv_len, move_y * inv_len)
	else:
		move_dir = Vector2(move_x, move_y)

	# Shooting direction (pick strongest above threshold)
	var shoot_dir := Vector2.ZERO
	var best_shoot := SHOOT_THRESHOLD
	
	# Unroll comparison for performance
	var up_val: float = _cached_outputs[OUT_SHOOT_UP]
	if up_val > best_shoot:
		best_shoot = up_val
		shoot_dir = Vector2.UP
	
	var down_val: float = _cached_outputs[OUT_SHOOT_DOWN]
	if down_val > best_shoot:
		best_shoot = down_val
		shoot_dir = Vector2.DOWN
	
	var left_val: float = _cached_outputs[OUT_SHOOT_LEFT]
	if left_val > best_shoot:
		best_shoot = left_val
		shoot_dir = Vector2.LEFT
	
	var right_val: float = _cached_outputs[OUT_SHOOT_RIGHT]
	if right_val > best_shoot:
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
