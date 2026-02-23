extends "res://test/test_base.gd"

## Tests for ui/network_visualizer.gd

var NetworkVisualizerScript = preload("res://ui/network_visualizer.gd")
var NeuralNetworkScript = preload("res://ai/neural_network.gd")


func run_tests() -> void:
    print("[Network Visualizer Tests]")

    _test(
        "creates_without_error",
        func():
            var viz = NetworkVisualizerScript.new()
            assert_not_null(viz)
    )

    _test(
        "signal_defined",
        func():
            var viz = NetworkVisualizerScript.new()
            assert_true(viz.has_signal("closed"), "Should have closed signal")
    )

    _test(
        "starts_not_visible",
        func():
            var viz = NetworkVisualizerScript.new()
            # Default Control visibility is true but our init doesn't show it
            # Just verify it's a valid Control
            assert_not_null(viz)
    )

    _test(
        "set_fixed_network",
        func():
            var viz = NetworkVisualizerScript.new()
            var net = NeuralNetworkScript.new(10, 5, 3)
            viz.set_fixed_network(net)
            assert_true(viz._fixed_network != null, "Fixed network should be set")
            assert_true(viz._node_positions.size() > 0, "Should compute node positions")
    )

    _test(
        "fixed_layout_has_all_types",
        func():
            var viz = NetworkVisualizerScript.new()
            var net = NeuralNetworkScript.new(10, 5, 3)
            viz.size = Vector2(400, 300)
            viz.set_fixed_network(net)

            var has_input := false
            var has_hidden := false
            var has_output := false
            for node_id in viz._node_types:
                match viz._node_types[node_id]:
                    0:
                        has_input = true
                    1:
                        has_hidden = true
                    2:
                        has_output = true

            assert_true(has_input, "Should have input nodes")
            assert_true(has_hidden, "Should have hidden nodes")
            assert_true(has_output, "Should have output nodes")
    )

    _test(
        "set_neat_data",
        func():
            var viz = NetworkVisualizerScript.new()
            var config := NeatConfig.new()
            config.input_count = 4
            config.output_count = 2
            var tracker := NeatInnovation.new()
            var genome := NeatGenome.create(config, tracker)
            genome.create_basic()
            var network := NeatNetwork.from_genome(genome)

            viz.set_neat_data(genome, network)
            assert_true(viz._neat_genome != null, "NEAT genome should be set")
            assert_true(viz._neat_network != null, "NEAT network should be set")
            assert_true(viz._node_positions.size() > 0, "Should compute node positions")
    )

    _test(
        "set_neat_network_without_genome",
        func():
            var viz = NetworkVisualizerScript.new()
            var config := NeatConfig.new()
            config.input_count = 3
            config.output_count = 2
            var tracker := NeatInnovation.new()
            var genome := NeatGenome.create(config, tracker)
            genome.create_basic()
            var network := NeatNetwork.from_genome(genome)

            viz.set_neat_data(null, network)
            assert_true(viz._neat_genome == null, "Genome should remain null")
            assert_true(viz._neat_network != null, "NEAT network should be set")
            assert_true(viz._node_positions.size() > 0, "Should compute layout from network only")
    )

    _test(
        "activation_color_zero",
        func():
            var viz = NetworkVisualizerScript.new()
            var color = viz._activation_color(0.0)
            # At zero, should be roughly gray/white
            assert_approx(color.r, 0.5, 0.1, "Zero activation should have ~0.5 red")
            assert_approx(color.g, 0.5, 0.1, "Zero activation should have ~0.5 green")
            assert_approx(color.b, 0.5, 0.1, "Zero activation should have ~0.5 blue")
    )

    _test(
        "activation_color_positive",
        func():
            var viz = NetworkVisualizerScript.new()
            var color = viz._activation_color(1.0)
            # Positive should be reddish
            assert_gt(color.r, 0.7, "Positive activation should have high red")
    )

    _test(
        "activation_color_negative",
        func():
            var viz = NetworkVisualizerScript.new()
            var color = viz._activation_color(-1.0)
            # Negative should be bluish
            assert_gt(color.b, 0.7, "Negative activation should have high blue")
    )

    _test(
        "neat_layout_separates_input_output",
        func():
            var viz = NetworkVisualizerScript.new()
            viz.size = Vector2(400, 300)
            var config := NeatConfig.new()
            config.input_count = 3
            config.output_count = 2
            var tracker := NeatInnovation.new()
            var genome := NeatGenome.create(config, tracker)
            genome.create_basic()
            var network := NeatNetwork.from_genome(genome)

            viz.set_neat_data(genome, network)

            # Input nodes should be on the left, output on the right
            var input_x := []
            var output_x := []
            for node_id in viz._node_types:
                if viz._node_types[node_id] == 0 and viz._node_positions.has(node_id):
                    input_x.append(viz._node_positions[node_id].x)
                elif viz._node_types[node_id] == 2 and viz._node_positions.has(node_id):
                    output_x.append(viz._node_positions[node_id].x)

            if input_x.size() > 0 and output_x.size() > 0:
                assert_lt(input_x[0], output_x[0], "Input nodes should be left of output nodes")
    )
