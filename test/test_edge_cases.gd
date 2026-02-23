extends "res://test/test_base.gd"
## Edge case and robustness tests.

const NeuralNetwork = preload("res://ai/neural_network.gd")
const Evolution = preload("res://ai/evolution.gd")


func run_tests() -> void:
    print("\n[Edge Case Tests]")

    _test("network_with_zero_weights", _test_network_with_zero_weights)
    _test("network_with_extreme_weights", _test_network_with_extreme_weights)
    _test("network_with_negative_weights", _test_network_with_negative_weights)
    _test("network_single_neuron_hidden", _test_network_single_neuron_hidden)
    _test("network_large_input_size", _test_network_large_input_size)
    _test("evolution_minimum_population", _test_evolution_minimum_population)
    _test("evolution_elite_equals_population", _test_evolution_elite_equals_population)
    _test("network_load_nonexistent_file", _test_network_load_nonexistent_file)
    _test("mutation_100_percent_rate", _test_mutation_100_percent_rate)
    _test("crossover_identical_parents", _test_crossover_identical_parents)


# ============================================================
# Neural Network Edge Cases
# ============================================================


func _test_network_with_zero_weights() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)

    # Set all weights to zero
    var zero_weights := PackedFloat32Array()
    zero_weights.resize(nn.get_weight_count())
    zero_weights.fill(0.0)
    nn.set_weights(zero_weights)

    # Forward pass should still work (output will be tanh(0) = 0)
    var inputs := PackedFloat32Array()
    inputs.resize(10)
    inputs.fill(1.0)

    var outputs := nn.forward(inputs)
    assert_eq(outputs.size(), 3, "Output size should be correct")
    for i in outputs.size():
        assert_approx(outputs[i], 0.0, 0.001, "Zero weights should produce zero output")


func _test_network_with_extreme_weights() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)

    # Set all weights to very large values
    var extreme_weights := PackedFloat32Array()
    extreme_weights.resize(nn.get_weight_count())
    extreme_weights.fill(1000.0)
    nn.set_weights(extreme_weights)

    var inputs := PackedFloat32Array()
    inputs.resize(10)
    inputs.fill(1.0)

    var outputs := nn.forward(inputs)
    # tanh saturates at ±1, so outputs should be bounded
    for i in outputs.size():
        assert_in_range(
            outputs[i], -1.0, 1.0, "Extreme weights should still produce bounded output"
        )


func _test_network_with_negative_weights() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)

    var negative_weights := PackedFloat32Array()
    negative_weights.resize(nn.get_weight_count())
    negative_weights.fill(-0.5)
    nn.set_weights(negative_weights)

    var inputs := PackedFloat32Array()
    inputs.resize(10)
    inputs.fill(1.0)

    var outputs := nn.forward(inputs)
    assert_eq(outputs.size(), 3, "Should handle negative weights")
    for i in outputs.size():
        assert_in_range(outputs[i], -1.0, 1.0, "Outputs should be bounded")


func _test_network_single_neuron_hidden() -> void:
    # Minimal hidden layer
    var nn = NeuralNetwork.new(5, 1, 2)

    assert_eq(nn.hidden_size, 1)
    assert_eq(nn.weights_ih.size(), 5, "5 input weights for 1 hidden neuron")
    assert_eq(nn.weights_ho.size(), 2, "2 output weights from 1 hidden neuron")

    var inputs := PackedFloat32Array()
    inputs.resize(5)
    inputs.fill(0.5)

    var outputs := nn.forward(inputs)
    assert_eq(outputs.size(), 2, "Should produce correct output size")


func _test_network_large_input_size() -> void:
    # Large network like the actual game uses
    var nn = NeuralNetwork.new(86, 32, 6)

    var inputs := PackedFloat32Array()
    inputs.resize(86)
    for i in 86:
        inputs[i] = randf_range(-1.0, 1.0)

    var outputs := nn.forward(inputs)
    assert_eq(outputs.size(), 6, "Should handle large input size")


# ============================================================
# Evolution Edge Cases
# ============================================================


func _test_evolution_minimum_population() -> void:
    # Population of 2 (minimum viable)
    var evo = Evolution.new(2, 5, 3, 2, 1)  # 1 elite

    assert_eq(evo.population.size(), 2)

    evo.set_fitness(0, 100.0)
    evo.set_fitness(1, 50.0)

    evo.evolve()
    assert_eq(evo.population.size(), 2, "Should maintain population size")
    assert_eq(evo.generation, 1)


func _test_evolution_elite_equals_population() -> void:
    # Edge case: all individuals are elite
    var evo = Evolution.new(5, 5, 3, 2, 5)  # elite_count = population_size

    for i in 5:
        evo.set_fitness(i, float(i) * 10.0)

    evo.evolve()
    assert_eq(evo.population.size(), 5, "Should maintain population size")


# ============================================================
# File Handling Edge Cases
# ============================================================


func _test_network_load_nonexistent_file() -> void:
    var nn = NeuralNetwork.load_from_file("user://nonexistent_network_12345.nn")
    assert_null(nn, "Loading nonexistent file should return null")


# ============================================================
# Mutation/Crossover Edge Cases
# ============================================================


func _test_mutation_100_percent_rate() -> void:
    var nn = NeuralNetwork.new(10, 5, 3)
    var weights_before := nn.get_weights().duplicate()

    # 100% mutation rate with significant strength
    nn.mutate(1.0, 1.0)

    var weights_after := nn.get_weights()
    var changed := 0
    for i in weights_before.size():
        if abs(weights_before[i] - weights_after[i]) > 0.0001:
            changed += 1

    # With 100% rate, essentially all weights should change
    # (statistically, mutation adds Gaussian noise, so nearly all will differ)
    assert_gt(changed, weights_before.size() * 0.9, "100% mutation should change most weights")


func _test_crossover_identical_parents() -> void:
    var parent = NeuralNetwork.new(10, 5, 3)

    # Set specific weights
    var weights := PackedFloat32Array()
    weights.resize(parent.get_weight_count())
    weights.fill(0.5)
    parent.set_weights(weights)

    # Crossover with itself
    var child = parent.crossover_with(parent)
    var child_weights: PackedFloat32Array = child.get_weights()

    # Child should have identical weights (crossover picks from either parent, both same)
    for i in weights.size():
        assert_approx(
            child_weights[i], 0.5, 0.0001, "Crossover with self should produce same weights"
        )
