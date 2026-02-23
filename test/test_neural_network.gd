extends "res://test/test_base.gd"
## Tests for ai/neural_network.gd

const NeuralNetwork = preload("res://ai/neural_network.gd")


func _run_tests() -> void:
    print("\n[NeuralNetwork Tests]")

    _test("initialization_sets_correct_sizes", _test_initialization_sets_correct_sizes)
    _test("initialization_creates_weight_arrays", _test_initialization_creates_weight_arrays)
    _test("get_weight_count_returns_correct_total", _test_get_weight_count_returns_correct_total)
    _test("forward_returns_correct_output_size", _test_forward_returns_correct_output_size)
    _test("forward_outputs_in_tanh_range", _test_forward_outputs_in_tanh_range)
    _test("forward_is_deterministic", _test_forward_is_deterministic)
    _test("clone_creates_independent_copy", _test_clone_creates_independent_copy)
    _test("clone_preserves_weights", _test_clone_preserves_weights)
    _test("set_weights_get_weights_roundtrip", _test_set_weights_get_weights_roundtrip)
    _test("mutate_changes_some_weights", _test_mutate_changes_some_weights)
    _test("mutate_with_zero_rate_changes_nothing", _test_mutate_with_zero_rate_changes_nothing)
    _test("crossover_produces_valid_child", _test_crossover_produces_valid_child)
    _test("crossover_mixes_parent_weights", _test_crossover_mixes_parent_weights)
    _test("save_load_roundtrip", _test_save_load_roundtrip)
    _test("zero_inputs_produce_valid_output", _test_zero_inputs_produce_valid_output)
    _test("extreme_inputs_stay_bounded", _test_extreme_inputs_stay_bounded)


# ============================================================
# Initialization Tests
# ============================================================


func _test_initialization_sets_correct_sizes() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    assert_eq(nn.input_size, 10, "input_size should be 10")
    assert_eq(nn.hidden_size, 5, "hidden_size should be 5")
    assert_eq(nn.output_size, 3, "output_size should be 3")


func _test_initialization_creates_weight_arrays() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    assert_eq(nn.weights_ih.size(), 10 * 5, "weights_ih should be input*hidden")
    assert_eq(nn.bias_h.size(), 5, "bias_h should be hidden_size")
    assert_eq(nn.weights_ho.size(), 5 * 3, "weights_ho should be hidden*output")
    assert_eq(nn.bias_o.size(), 3, "bias_o should be output_size")


func _test_get_weight_count_returns_correct_total() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var expected := 10 * 5 + 5 + 5 * 3 + 3  # weights_ih + bias_h + weights_ho + bias_o
    assert_eq(nn.get_weight_count(), expected)


# ============================================================
# Forward Pass Tests
# ============================================================


func _test_forward_returns_correct_output_size() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var inputs := PackedFloat32Array()
    inputs.resize(10)
    inputs.fill(0.5)

    var outputs := nn.forward(inputs)
    assert_eq(outputs.size(), 3, "Output size should match output_size")


func _test_forward_outputs_in_tanh_range() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var inputs := PackedFloat32Array()
    inputs.resize(10)

    # Test with random inputs
    for i in 10:
        inputs[i] = randf_range(-1.0, 1.0)

    var outputs := nn.forward(inputs)
    for i in outputs.size():
        assert_in_range(outputs[i], -1.0, 1.0, "Output %d should be in [-1, 1]" % i)


func _test_forward_is_deterministic() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var inputs := PackedFloat32Array()
    inputs.resize(10)
    for i in 10:
        inputs[i] = float(i) / 10.0

    var output1 := nn.forward(inputs)
    var output2 := nn.forward(inputs)

    for i in output1.size():
        assert_approx(output1[i], output2[i], 0.0001, "Forward pass should be deterministic")


func _test_zero_inputs_produce_valid_output() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var inputs := PackedFloat32Array()
    inputs.resize(10)
    inputs.fill(0.0)

    var outputs := nn.forward(inputs)
    assert_eq(outputs.size(), 3, "Should produce output even with zero inputs")
    for i in outputs.size():
        assert_in_range(outputs[i], -1.0, 1.0, "Zero-input output should still be bounded")


func _test_extreme_inputs_stay_bounded() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var inputs := PackedFloat32Array()
    inputs.resize(10)

    # Test with very large positive inputs
    inputs.fill(1000.0)
    var outputs := nn.forward(inputs)
    for i in outputs.size():
        assert_in_range(
            outputs[i], -1.0, 1.0, "Large positive inputs should still produce bounded output"
        )

    # Test with very large negative inputs
    inputs.fill(-1000.0)
    outputs = nn.forward(inputs)
    for i in outputs.size():
        assert_in_range(
            outputs[i], -1.0, 1.0, "Large negative inputs should still produce bounded output"
        )


# ============================================================
# Clone Tests
# ============================================================


func _test_clone_creates_independent_copy() -> void:
    var nn1 = NeuralNetwork.new(10, 5, 3)
    var nn2 = nn1.clone()

    # Modify original
    nn1.weights_ih[0] = 999.0

    # Clone should be unaffected
    assert_ne(nn2.weights_ih[0], 999.0, "Clone should be independent of original")


func _test_clone_preserves_weights() -> void:
    var nn1 = NeuralNetwork.new(10, 5, 3)
    var weights_before: PackedFloat32Array = nn1.get_weights().duplicate()
    var nn2 = nn1.clone()
    var weights_after: PackedFloat32Array = nn2.get_weights()

    assert_eq(weights_before.size(), weights_after.size(), "Weight count should match")
    for i in weights_before.size():
        assert_approx(weights_before[i], weights_after[i], 0.0001, "Weight %d should match" % i)


# ============================================================
# Weight Manipulation Tests
# ============================================================


func _test_set_weights_get_weights_roundtrip() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)

    # Create custom weights
    var custom_weights := PackedFloat32Array()
    custom_weights.resize(nn.get_weight_count())
    for i in custom_weights.size():
        custom_weights[i] = float(i) / 100.0

    nn.set_weights(custom_weights)
    var retrieved := nn.get_weights()

    assert_eq(retrieved.size(), custom_weights.size(), "Weight count should match")
    for i in custom_weights.size():
        assert_approx(retrieved[i], custom_weights[i], 0.0001, "Weight %d should roundtrip" % i)


func _test_mutate_changes_some_weights() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var weights_before := nn.get_weights().duplicate()

    nn.mutate(1.0, 0.5)  # 100% mutation rate, large strength

    var weights_after := nn.get_weights()
    var changed_count := 0
    for i in weights_before.size():
        if abs(weights_before[i] - weights_after[i]) > 0.0001:
            changed_count += 1

    assert_gt(changed_count, 0, "Mutation should change some weights")


func _test_mutate_with_zero_rate_changes_nothing() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var weights_before := nn.get_weights().duplicate()

    nn.mutate(0.0, 0.5)  # 0% mutation rate

    var weights_after := nn.get_weights()
    for i in weights_before.size():
        assert_approx(
            weights_before[i], weights_after[i], 0.0001, "Zero mutation rate should change nothing"
        )


# ============================================================
# Crossover Tests
# ============================================================


func _test_crossover_produces_valid_child() -> void:
    var parent1 = NeuralNetwork.new(10, 5, 3)
    var parent2 = NeuralNetwork.new(10, 5, 3)

    var child = parent1.crossover_with(parent2)

    assert_eq(child.input_size, 10)
    assert_eq(child.hidden_size, 5)
    assert_eq(child.output_size, 3)
    assert_eq(child.get_weight_count(), parent1.get_weight_count())


func _test_crossover_mixes_parent_weights() -> void:
    var parent1 = NeuralNetwork.new(10, 5, 3)
    var parent2 = NeuralNetwork.new(10, 5, 3)

    # Set distinct weights for each parent
    var weights1 := PackedFloat32Array()
    var weights2 := PackedFloat32Array()
    weights1.resize(parent1.get_weight_count())
    weights2.resize(parent2.get_weight_count())
    weights1.fill(1.0)
    weights2.fill(-1.0)
    parent1.set_weights(weights1)
    parent2.set_weights(weights2)

    # Crossover multiple times to check mixing
    var from_parent1 := 0
    var from_parent2 := 0

    for _attempt in 10:
        var child = parent1.crossover_with(parent2)
        var child_weights: PackedFloat32Array = child.get_weights()
        for w in child_weights:
            if abs(w - 1.0) < 0.0001:
                from_parent1 += 1
            elif abs(w - (-1.0)) < 0.0001:
                from_parent2 += 1

    assert_gt(from_parent1, 0, "Child should have some weights from parent 1")
    assert_gt(from_parent2, 0, "Child should have some weights from parent 2")


# ============================================================
# Persistence Tests
# ============================================================


func _test_save_load_roundtrip() -> void:
    var nn1 = NeuralNetwork.new(10, 5, 3)
    var test_path := "user://test_network.nn"

    nn1.save_to_file(test_path)
    var nn2 = NeuralNetwork.load_from_file(test_path)

    assert_not_null(nn2, "Loaded network should not be null")
    assert_eq(nn2.input_size, nn1.input_size)
    assert_eq(nn2.hidden_size, nn1.hidden_size)
    assert_eq(nn2.output_size, nn1.output_size)

    var weights1: PackedFloat32Array = nn1.get_weights()
    var weights2: PackedFloat32Array = nn2.get_weights()
    assert_eq(weights1.size(), weights2.size())
    for i in weights1.size():
        assert_approx(weights1[i], weights2[i], 0.0001, "Weight %d should survive save/load" % i)

    # Cleanup
    DirAccess.remove_absolute(test_path)
