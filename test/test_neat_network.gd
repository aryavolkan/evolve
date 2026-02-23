extends "res://test/test_base.gd"

## Tests for NeatNetwork — forward pass through variable-topology networks.

var config: NeatConfig
var tracker: NeatInnovation


func _setup() -> void:
    config = NeatConfig.new()
    config.input_count = 3
    config.output_count = 2
    config.use_bias = false
    config.allow_recurrent = false
    tracker = NeatInnovation.new()


func _run_tests() -> void:
    _test("network_from_empty_genome", test_empty_genome)
    _test("network_from_basic_genome", test_basic_genome)
    _test("network_input_output_counts", test_io_counts)
    _test("network_forward_output_size", test_output_size)
    _test("network_forward_deterministic", test_deterministic)
    _test("network_outputs_bounded", test_outputs_bounded)
    _test("network_zero_inputs", test_zero_inputs)
    _test("network_with_hidden_node", test_hidden_node)
    _test("network_multiple_hidden_layers", test_multiple_hidden)
    _test("network_disabled_connections_ignored", test_disabled_ignored)
    _test("network_reset_clears_state", test_reset)
    _test("network_different_weights_different_output", test_different_weights)
    _test("network_node_count", test_node_count)
    _test("network_connection_count", test_connection_count)


func test_empty_genome() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    # No connections
    var net := NeatNetwork.from_genome(genome)
    assert_eq(net.get_input_count(), 3)
    assert_eq(net.get_output_count(), 2)
    var outputs := net.forward(PackedFloat32Array([1.0, 2.0, 3.0]))
    assert_eq(outputs.size(), 2)


func test_basic_genome() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    var outputs := net.forward(PackedFloat32Array([1.0, 0.5, -1.0]))
    assert_eq(outputs.size(), 2)
    # With connections, outputs should not all be zero
    var has_nonzero := false
    for o in outputs:
        if absf(o) > 0.001:
            has_nonzero = true
    assert_true(has_nonzero, "Connected network should produce non-zero outputs")


func test_io_counts() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    assert_eq(net.get_input_count(), 3)
    assert_eq(net.get_output_count(), 2)


func test_output_size() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    var outputs := net.forward(PackedFloat32Array([0.0, 0.0, 0.0]))
    assert_eq(outputs.size(), 2)


func test_deterministic() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    var inputs := PackedFloat32Array([1.0, -0.5, 0.3])
    var out1 := net.forward(inputs)
    net.reset()
    var out2 := net.forward(inputs)
    for i in out1.size():
        assert_approx(out1[i], out2[i], 0.0001, "Same inputs should give same outputs")


func test_outputs_bounded() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    # Extreme inputs
    var outputs := net.forward(PackedFloat32Array([100.0, -100.0, 100.0]))
    for o in outputs:
        assert_gte(o, -1.0)
        assert_lte(o, 1.0)


func test_zero_inputs() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    var outputs := net.forward(PackedFloat32Array([0.0, 0.0, 0.0]))
    assert_eq(outputs.size(), 2)
    # With zero inputs, output is tanh(bias) — should be bounded
    for o in outputs:
        assert_gte(o, -1.0)
        assert_lte(o, 1.0)


func test_hidden_node() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    genome.mutate_add_node()
    var net := NeatNetwork.from_genome(genome)
    assert_gt(net.get_node_count(), 5)  # 3 in + 2 out + at least 1 hidden
    var outputs := net.forward(PackedFloat32Array([1.0, 1.0, 1.0]))
    assert_eq(outputs.size(), 2)
    for o in outputs:
        assert_gte(o, -1.0)
        assert_lte(o, 1.0)


func test_multiple_hidden() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    for i in 5:
        genome.mutate_add_node()
        genome.mutate_add_connection()
    var net := NeatNetwork.from_genome(genome)
    assert_gte(net.get_node_count(), 10)  # 5 original + 5 hidden
    var outputs := net.forward(PackedFloat32Array([0.5, -0.5, 0.0]))
    assert_eq(outputs.size(), 2)
    for o in outputs:
        assert_gte(o, -1.0)
        assert_lte(o, 1.0)


func test_disabled_ignored() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()

    # Record output with all connections enabled
    var net1 := NeatNetwork.from_genome(genome)
    var out1 := net1.forward(PackedFloat32Array([1.0, 1.0, 1.0]))

    # Disable all connections
    for conn in genome.connection_genes:
        conn.enabled = false
    var net2 := NeatNetwork.from_genome(genome)
    assert_eq(net2.get_connection_count(), 0)


func test_reset() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    net.forward(PackedFloat32Array([1.0, 1.0, 1.0]))
    net.reset()
    # After reset, all activations should be zero
    var outputs := net.forward(PackedFloat32Array([0.0, 0.0, 0.0]))
    # Output is just tanh(bias) with zero inputs after reset
    assert_eq(outputs.size(), 2)


func test_different_weights() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net1 := NeatNetwork.from_genome(genome)
    var out1 := net1.forward(PackedFloat32Array([1.0, 0.0, 0.0]))

    # Change weights and rebuild
    for conn in genome.connection_genes:
        conn.weight = conn.weight + 5.0
    var net2 := NeatNetwork.from_genome(genome)
    var out2 := net2.forward(PackedFloat32Array([1.0, 0.0, 0.0]))

    var different := false
    for i in out1.size():
        if absf(out1[i] - out2[i]) > 0.001:
            different = true
    assert_true(different, "Different weights should produce different outputs")


func test_node_count() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    assert_eq(net.get_node_count(), 5)  # 3 inputs + 2 outputs


func test_connection_count() -> void:
    _setup()
    var genome := NeatGenome.create(config, tracker)
    genome.create_basic()
    var net := NeatNetwork.from_genome(genome)
    assert_eq(net.get_connection_count(), 6)  # 3 × 2 fully connected
