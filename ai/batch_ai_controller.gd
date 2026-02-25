class_name BatchAIController
extends RefCounted

## Batch AI controller for processing multiple agents in parallel.
## Uses batch neural network forward pass for better cache utilization.
## ~2-3x faster than individual forward passes on 10+ agents.

# Output indices (same as AIController)
const OUT_MOVE_X := 0
const OUT_MOVE_Y := 1
const OUT_SHOOT_UP := 2
const OUT_SHOOT_DOWN := 3
const OUT_SHOOT_LEFT := 4
const OUT_SHOOT_RIGHT := 5

# Thresholds
const SHOOT_THRESHOLD := 0.0
const MOVE_DEADZONE := 0.05

var nn_factory = preload("res://ai/neural_network_factory.gd")
var sensor_script = preload("res://ai/sensor.gd")

# Batch data
var controllers: Array[Dictionary] = []  # {network, sensor, player}
var batch_size: int = 0
var input_size: int = 0
var output_size: int = 6

# Cached arrays
var _all_inputs: PackedFloat32Array
var _all_outputs: PackedFloat32Array
var _networks_array: Array


func add_controller(network, player: CharacterBody2D) -> int:
    ## Add a controller to the batch. Returns the index.
    var sensor = sensor_script.new()
    sensor.set_player(player)

    if input_size == 0:
        input_size = sensor.TOTAL_INPUTS

    var idx = controllers.size()
    controllers.append({
        "network": network,
        "sensor": sensor,
        "player": player
    })
    batch_size = controllers.size()

    # Resize cached arrays
    _all_inputs.resize(batch_size * input_size)
    _networks_array.resize(batch_size)

    return idx


func clear() -> void:
    ## Clear all controllers.
    controllers.clear()
    batch_size = 0
    _all_inputs.clear()
    _all_outputs.clear()
    _networks_array.clear()


func get_batch_actions() -> Array[Dictionary]:
    ## Get actions for all controllers in a single batch.
    ## Returns array of action dictionaries in same order as controllers.

    if batch_size == 0:
        return []

    # Collect all inputs
    for i in batch_size:
        var ctrl = controllers[i]
        var inputs = ctrl.sensor.get_inputs()
        var start_idx = i * input_size

        # Copy inputs into batch array
        for j in input_size:
            _all_inputs[start_idx + j] = inputs[j]

        # Store network reference
        _networks_array[i] = ctrl.network

    # Batch forward pass
    _all_outputs = nn_factory.batch_forward(_networks_array, _all_inputs)

    # Process outputs into actions
    var actions: Array[Dictionary] = []
    actions.resize(batch_size)

    for i in batch_size:
        var out_start = i * output_size

        # Movement direction
        var move_x: float = _all_outputs[out_start + OUT_MOVE_X]
        var move_y: float = _all_outputs[out_start + OUT_MOVE_Y]
        var move_len_sq: float = move_x * move_x + move_y * move_y

        var move_dir: Vector2
        if move_len_sq < MOVE_DEADZONE * MOVE_DEADZONE:
            move_dir = Vector2.ZERO
        elif move_len_sq > 1.0:
            var inv_len = 1.0 / sqrt(move_len_sq)
            move_dir = Vector2(move_x * inv_len, move_y * inv_len)
        else:
            move_dir = Vector2(move_x, move_y)

        # Shooting direction
        var shoot_dir := Vector2.ZERO
        var best_shoot := SHOOT_THRESHOLD

        var up_val: float = _all_outputs[out_start + OUT_SHOOT_UP]
        if up_val > best_shoot:
            best_shoot = up_val
            shoot_dir = Vector2.UP

        var down_val: float = _all_outputs[out_start + OUT_SHOOT_DOWN]
        if down_val > best_shoot:
            best_shoot = down_val
            shoot_dir = Vector2.DOWN

        var left_val: float = _all_outputs[out_start + OUT_SHOOT_LEFT]
        if left_val > best_shoot:
            best_shoot = left_val
            shoot_dir = Vector2.LEFT

        var right_val: float = _all_outputs[out_start + OUT_SHOOT_RIGHT]
        if right_val > best_shoot:
            shoot_dir = Vector2.RIGHT

        actions[i] = {
            "move_direction": move_dir,
            "shoot_direction": shoot_dir
        }

    return actions


func get_action_at(index: int) -> Dictionary:
    ## Get action for a specific controller (fallback for single queries).
    if index < 0 or index >= batch_size:
        return {"move_direction": Vector2.ZERO, "shoot_direction": Vector2.ZERO}

    var ctrl = controllers[index]
    var inputs = ctrl.sensor.get_inputs()
    var outputs = ctrl.network.forward(inputs)

    # Same processing as AIController
    var move_x: float = outputs[OUT_MOVE_X]
    var move_y: float = outputs[OUT_MOVE_Y]
    var move_len_sq: float = move_x * move_x + move_y * move_y

    var move_dir: Vector2
    if move_len_sq < MOVE_DEADZONE * MOVE_DEADZONE:
        move_dir = Vector2.ZERO
    elif move_len_sq > 1.0:
        var inv_len = 1.0 / sqrt(move_len_sq)
        move_dir = Vector2(move_x * inv_len, move_y * inv_len)
    else:
        move_dir = Vector2(move_x, move_y)

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
        shoot_dir = Vector2.RIGHT

    return {
        "move_direction": move_dir,
        "shoot_direction": shoot_dir
    }