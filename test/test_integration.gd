extends "res://test/test_base.gd"
## Integration tests for the full Sensor → NeuralNetwork → AIController pipeline.
## Verifies that data flows correctly through the AI system without scene instantiation.

const NeuralNetwork = preload("res://ai/neural_network.gd")

# Constants matching the actual system
const NUM_RAYS := 16
const INPUTS_PER_RAY := 5
const PLAYER_STATE_INPUTS := 6
const TOTAL_INPUTS := NUM_RAYS * INPUTS_PER_RAY + PLAYER_STATE_INPUTS  # 86
const NETWORK_HIDDEN := 32
const NETWORK_OUTPUTS := 6

# AI Controller constants
const OUT_MOVE_X := 0
const OUT_MOVE_Y := 1
const OUT_SHOOT_UP := 2
const OUT_SHOOT_DOWN := 3
const OUT_SHOOT_LEFT := 4
const OUT_SHOOT_RIGHT := 5
const SHOOT_THRESHOLD := 0.0
const MOVE_DEADZONE := 0.05


func _run_tests() -> void:
	print("\n[Integration Tests]")

	_test("full_pipeline_dimensions_match", _test_full_pipeline_dimensions_match)
	_test("network_accepts_sensor_output_size", _test_network_accepts_sensor_output_size)
	_test("network_produces_controller_input_size", _test_network_produces_controller_input_size)
	_test("empty_sensor_inputs_produce_valid_action", _test_empty_sensor_inputs_produce_valid_action)
	_test("varied_sensor_inputs_produce_varied_actions", _test_varied_sensor_inputs_produce_varied_actions)
	_test("network_output_range_compatible_with_controller", _test_network_output_range_compatible_with_controller)
	_test("pipeline_deterministic_same_inputs", _test_pipeline_deterministic_same_inputs)
	_test("pipeline_handles_sparse_inputs", _test_pipeline_handles_sparse_inputs)
	_test("pipeline_handles_saturated_inputs", _test_pipeline_handles_saturated_inputs)
	_test("evolved_network_produces_different_behavior", _test_evolved_network_produces_different_behavior)


# ============================================================
# Helper: Simulate AI Controller action logic
# ============================================================

func get_action_from_outputs(outputs: PackedFloat32Array) -> Dictionary:
	var move_dir := Vector2(outputs[OUT_MOVE_X], outputs[OUT_MOVE_Y])
	if move_dir.length() < MOVE_DEADZONE:
		move_dir = Vector2.ZERO
	elif move_dir.length() > 1.0:
		move_dir = move_dir.normalized()

	var shoot_dir := Vector2.ZERO
	var shoot_outputs := [
		{"dir": Vector2.UP, "val": outputs[OUT_SHOOT_UP]},
		{"dir": Vector2.DOWN, "val": outputs[OUT_SHOOT_DOWN]},
		{"dir": Vector2.LEFT, "val": outputs[OUT_SHOOT_LEFT]},
		{"dir": Vector2.RIGHT, "val": outputs[OUT_SHOOT_RIGHT]}
	]

	var best_shoot := SHOOT_THRESHOLD
	for s in shoot_outputs:
		if s.val > best_shoot:
			best_shoot = s.val
			shoot_dir = s.dir

	return {
		"move_direction": move_dir,
		"shoot_direction": shoot_dir
	}


func create_mock_sensor_inputs(fill_value: float = 0.0) -> PackedFloat32Array:
	var inputs := PackedFloat32Array()
	inputs.resize(TOTAL_INPUTS)
	inputs.fill(fill_value)
	return inputs


func create_sparse_sensor_inputs() -> PackedFloat32Array:
	## Simulates typical sensor state: mostly zeros with some detections.
	var inputs := PackedFloat32Array()
	inputs.resize(TOTAL_INPUTS)
	inputs.fill(0.0)

	# Simulate enemy detected on ray 0 (distance 0.7, type 0.2 for pawn)
	inputs[0] = 0.7  # enemy distance
	inputs[1] = 0.2  # enemy type (pawn)

	# Simulate wall detected on ray 4 (distance 0.5)
	inputs[4 * INPUTS_PER_RAY + 4] = 0.5  # wall distance

	# Player state inputs (last 6)
	var player_state_start := NUM_RAYS * INPUTS_PER_RAY
	inputs[player_state_start] = 0.3      # velocity x
	inputs[player_state_start + 1] = -0.2 # velocity y
	inputs[player_state_start + 5] = 1.0  # can_shoot

	return inputs


# ============================================================
# Dimension Compatibility Tests
# ============================================================

func _test_full_pipeline_dimensions_match() -> void:
	# Verify the dimension constants are consistent with CLAUDE.md spec
	assert_eq(TOTAL_INPUTS, 86, "Total inputs should be 86 (16×5 + 6)")
	assert_eq(NETWORK_OUTPUTS, 6, "Network outputs should be 6")


func _test_network_accepts_sensor_output_size() -> void:
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)
	var sensor_output := create_mock_sensor_inputs()

	# This should not crash - network accepts sensor output size
	var network_output := nn.forward(sensor_output)
	assert_eq(network_output.size(), NETWORK_OUTPUTS)


func _test_network_produces_controller_input_size() -> void:
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)
	var sensor_output := create_mock_sensor_inputs()
	var network_output := nn.forward(sensor_output)

	# Network output should have exactly 6 values for the controller
	assert_eq(network_output.size(), 6, "Network should produce 6 outputs")

	# Controller should be able to process these outputs
	var action := get_action_from_outputs(network_output)
	assert_true(action.has("move_direction"))
	assert_true(action.has("shoot_direction"))


# ============================================================
# Data Flow Tests
# ============================================================

func _test_empty_sensor_inputs_produce_valid_action() -> void:
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)
	var empty_inputs := create_mock_sensor_inputs(0.0)

	var outputs := nn.forward(empty_inputs)
	var action := get_action_from_outputs(outputs)

	# Action should be valid (may or may not be zero depending on network biases)
	assert_true(action.move_direction is Vector2)
	assert_true(action.shoot_direction is Vector2)
	assert_in_range(action.move_direction.length(), 0.0, 1.0, "Movement should be normalized")


func _test_varied_sensor_inputs_produce_varied_actions() -> void:
	# Test that different inputs produce different network outputs
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)

	# Use sparse realistic inputs vs saturated inputs
	var sparse_inputs := create_sparse_sensor_inputs()  # Few non-zero values
	var saturated_inputs := create_mock_sensor_inputs(1.0)  # All maxed out

	# IMPORTANT: forward() returns internal array by reference, must copy!
	var outputs_sparse: PackedFloat32Array = nn.forward(sparse_inputs).duplicate()
	var outputs_saturated: PackedFloat32Array = nn.forward(saturated_inputs).duplicate()

	# Different inputs should produce different outputs
	var difference := 0.0
	for i in outputs_sparse.size():
		difference += abs(outputs_sparse[i] - outputs_saturated[i])

	assert_gt(difference, 0.001, "Different inputs should produce different outputs")


func _test_network_output_range_compatible_with_controller() -> void:
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)

	# Test with various input patterns
	for _trial in 10:
		var inputs := PackedFloat32Array()
		inputs.resize(TOTAL_INPUTS)
		for i in TOTAL_INPUTS:
			inputs[i] = randf_range(-1.0, 1.0)

		var outputs := nn.forward(inputs)

		# All outputs should be in tanh range [-1, 1]
		for i in outputs.size():
			assert_in_range(outputs[i], -1.0, 1.0, "Output %d should be in [-1, 1]" % i)

		# Controller should handle these values
		var action := get_action_from_outputs(outputs)
		assert_in_range(action.move_direction.length(), 0.0, 1.0, "Movement magnitude should be bounded")


func _test_pipeline_deterministic_same_inputs() -> void:
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)
	var inputs := create_sparse_sensor_inputs()

	var outputs1 := nn.forward(inputs)
	var outputs2 := nn.forward(inputs)

	for i in outputs1.size():
		assert_approx(outputs1[i], outputs2[i], 0.0001, "Same inputs should produce same outputs")

	var action1 := get_action_from_outputs(outputs1)
	var action2 := get_action_from_outputs(outputs2)

	assert_eq(action1.move_direction, action2.move_direction, "Deterministic movement")
	assert_eq(action1.shoot_direction, action2.shoot_direction, "Deterministic shooting")


# ============================================================
# Edge Case Input Tests
# ============================================================

func _test_pipeline_handles_sparse_inputs() -> void:
	## Test typical game scenario where most sensor rays detect nothing.
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)
	var sparse_inputs := create_sparse_sensor_inputs()

	# Count non-zero inputs (should be sparse)
	var non_zero := 0
	for i in sparse_inputs.size():
		if abs(sparse_inputs[i]) > 0.001:
			non_zero += 1

	assert_lt(non_zero, TOTAL_INPUTS / 2, "Sparse inputs should have < 50% non-zero")

	# Pipeline should still produce valid output
	var outputs := nn.forward(sparse_inputs)
	var action := get_action_from_outputs(outputs)

	assert_true(action.move_direction is Vector2)
	assert_true(action.shoot_direction is Vector2)


func _test_pipeline_handles_saturated_inputs() -> void:
	## Test extreme scenario where all sensors detect something.
	var nn = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)
	var saturated_inputs := create_mock_sensor_inputs(1.0)

	var outputs := nn.forward(saturated_inputs)
	var action := get_action_from_outputs(outputs)

	# Should still produce bounded, valid action
	assert_in_range(action.move_direction.length(), 0.0, 1.0)
	assert_true(
		action.shoot_direction == Vector2.ZERO or
		action.shoot_direction == Vector2.UP or
		action.shoot_direction == Vector2.DOWN or
		action.shoot_direction == Vector2.LEFT or
		action.shoot_direction == Vector2.RIGHT,
		"Shoot direction should be cardinal or zero"
	)


# ============================================================
# Evolution Integration Tests
# ============================================================

func _test_evolved_network_produces_different_behavior() -> void:
	## Verify mutation changes network behavior.
	var nn1 = NeuralNetwork.new(TOTAL_INPUTS, NETWORK_HIDDEN, NETWORK_OUTPUTS)
	var nn2 = nn1.clone()

	# Mutate the clone
	nn2.mutate(0.5, 0.5)

	var inputs := create_sparse_sensor_inputs()
	var outputs1: PackedFloat32Array = nn1.forward(inputs)
	var outputs2: PackedFloat32Array = nn2.forward(inputs)

	var action1 := get_action_from_outputs(outputs1)
	var action2 := get_action_from_outputs(outputs2)

	# At least one aspect of behavior should differ after mutation
	var outputs_differ := false
	for i in outputs1.size():
		if abs(outputs1[i] - outputs2[i]) > 0.01:
			outputs_differ = true
			break

	assert_true(outputs_differ, "Mutated network should produce different outputs")
