extends "res://test/test_base.gd"
## Tests for Elman recurrent memory in ai/neural_network.gd

const NeuralNetwork = preload("res://ai/neural_network.gd")


func _make_memory_nn(in_s: int, hid_s: int, out_s: int):
	var nn = NeuralNetwork.new(in_s, hid_s, out_s)
	nn.enable_memory()
	return nn


func _run_tests() -> void:
	print("\n[Elman Memory Tests]")

	# Backward compatibility
	_test("default_use_memory_is_false", _test_default_use_memory_is_false)
	_test("feedforward_unchanged_without_memory", _test_feedforward_unchanged_without_memory)
	_test("weight_count_unchanged_without_memory", _test_weight_count_unchanged_without_memory)

	# Memory initialization
	_test("memory_network_initializes", _test_memory_network_initializes)
	_test("memory_adds_hh_weights", _test_memory_adds_hh_weights)
	_test("memory_weight_count_includes_hh", _test_memory_weight_count_includes_hh)
	_test("prev_hidden_starts_zeroed", _test_prev_hidden_starts_zeroed)

	# Forward pass with memory
	_test("memory_forward_returns_correct_size", _test_memory_forward_returns_correct_size)
	_test("memory_forward_outputs_bounded", _test_memory_forward_outputs_bounded)
	_test("memory_makes_forward_history_dependent", _test_memory_makes_forward_history_dependent)
	_test("memory_deterministic_sequence", _test_memory_deterministic_sequence)

	# Reset
	_test("memory_reset_clears_state", _test_memory_reset_clears_state)
	_test("reset_restores_initial_behavior", _test_reset_restores_initial_behavior)
	_test("reset_on_non_memory_network_is_safe", _test_reset_on_non_memory_network_is_safe)

	# Clone
	_test("clone_preserves_memory_flag", _test_clone_preserves_memory_flag)
	_test("clone_preserves_weights_with_memory", _test_clone_preserves_weights_with_memory)

	# Crossover
	_test("crossover_with_memory_produces_valid_child", _test_crossover_with_memory_produces_valid_child)

	# Mutation
	_test("mutate_changes_hh_weights", _test_mutate_changes_hh_weights)

	# Weight get/set
	_test("get_set_weights_roundtrip_with_memory", _test_get_set_weights_roundtrip_with_memory)

	# Persistence
	_test("save_load_roundtrip_with_memory", _test_save_load_roundtrip_with_memory)
	_test("save_load_roundtrip_without_memory", _test_save_load_roundtrip_without_memory)

	# Edge cases
	_test("enable_memory_idempotent", _test_enable_memory_idempotent)
	_test("extreme_inputs_bounded_with_memory", _test_extreme_inputs_bounded_with_memory)
	_test("many_forward_passes_stay_bounded", _test_many_forward_passes_stay_bounded)
	_test("different_sequences_different_results", _test_different_sequences_different_results)


# ============================================================
# Backward Compatibility
# ============================================================

func _test_default_use_memory_is_false() -> void:
	var nn = NeuralNetwork.new(10, 5, 3)
	assert_false(nn.use_memory, "Default should be non-memory")
	assert_eq(nn.weights_hh.size(), 0, "No context weights without memory")


func _test_feedforward_unchanged_without_memory() -> void:
	var nn = NeuralNetwork.new(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(0.5)
	var out1 := PackedFloat32Array(nn.forward(inputs))
	var out2 := PackedFloat32Array(nn.forward(inputs))
	for i in out1.size():
		assert_approx(out1[i], out2[i], 0.0001, "Feedforward should be stateless")


func _test_weight_count_unchanged_without_memory() -> void:
	var nn = NeuralNetwork.new(10, 5, 3)
	var expected := 10*5 + 5 + 5*3 + 3
	assert_eq(nn.get_weight_count(), expected, "Non-memory weight count unchanged")


# ============================================================
# Memory Initialization
# ============================================================

func _test_memory_network_initializes() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	assert_true(nn.use_memory, "Memory should be enabled")


func _test_memory_adds_hh_weights() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	assert_eq(nn.weights_hh.size(), 5 * 5, "Context weights should be hidden_size^2")


func _test_memory_weight_count_includes_hh() -> void:
	var nn = _make_memory_nn(86, 32, 6)
	# base: 86*32 + 32 + 32*6 + 6 = 2950, memory: 32*32 = 1024, total: 3974
	var expected := 86*32 + 32 + 32*6 + 6 + 32*32
	assert_eq(nn.get_weight_count(), expected, "Memory weight count = base + hh")


func _test_prev_hidden_starts_zeroed() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	for i in nn._prev_hidden.size():
		assert_approx(nn._prev_hidden[i], 0.0, 0.0001, "prev_hidden should start at zero")


# ============================================================
# Forward Pass with Memory
# ============================================================

func _test_memory_forward_returns_correct_size() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(0.5)
	var out := nn.forward(inputs)
	assert_eq(out.size(), 3, "Output size should match output_size")


func _test_memory_forward_outputs_bounded() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	for i in 10:
		inputs[i] = randf_range(-1.0, 1.0)
	for _step in 5:
		var out := nn.forward(inputs)
		for i in out.size():
			assert_in_range(out[i], -1.0, 1.0, "Output should be in [-1, 1]")


func _test_memory_makes_forward_history_dependent() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(0.5)

	var out1 := PackedFloat32Array(nn.forward(inputs))
	var out2 := PackedFloat32Array(nn.forward(inputs))

	var any_different := false
	for i in out1.size():
		if abs(out1[i] - out2[i]) > 0.0001:
			any_different = true
			break
	assert_true(any_different, "Memory should cause different outputs for repeated same input")


func _test_memory_deterministic_sequence() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	for i in 10:
		inputs[i] = float(i) / 10.0

	# Run sequence once
	nn.reset_memory()
	var seq1: Array = []
	for _step in 5:
		seq1.append(PackedFloat32Array(nn.forward(inputs)))

	# Reset and run again
	nn.reset_memory()
	var seq2: Array = []
	for _step in 5:
		seq2.append(PackedFloat32Array(nn.forward(inputs)))

	for step in 5:
		for i in seq1[step].size():
			assert_approx(seq1[step][i], seq2[step][i], 0.0001,
				"Deterministic: step %d output %d should match" % [step, i])


# ============================================================
# Reset
# ============================================================

func _test_memory_reset_clears_state() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(0.5)
	nn.forward(inputs)
	nn.reset_memory()
	for i in nn._prev_hidden.size():
		assert_approx(nn._prev_hidden[i], 0.0, 0.0001, "Memory should be zero after reset")


func _test_reset_restores_initial_behavior() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(0.5)

	var out_fresh := PackedFloat32Array(nn.forward(inputs))
	for _step in 10:
		nn.forward(inputs)
	nn.reset_memory()
	var out_reset := PackedFloat32Array(nn.forward(inputs))

	for i in out_fresh.size():
		assert_approx(out_fresh[i], out_reset[i], 0.0001,
			"After reset, first forward should match initial")


func _test_reset_on_non_memory_network_is_safe() -> void:
	var nn = NeuralNetwork.new(10, 5, 3)
	nn.reset_memory()  # Should not crash
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(0.5)
	var out := nn.forward(inputs)
	assert_eq(out.size(), 3, "Non-memory network should work after reset call")


# ============================================================
# Clone
# ============================================================

func _test_clone_preserves_memory_flag() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var copy = nn.clone()
	assert_true(copy.use_memory, "Clone should preserve use_memory")
	assert_eq(copy.weights_hh.size(), 5 * 5, "Clone should have context weights")


func _test_clone_preserves_weights_with_memory() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var copy = nn.clone()
	var w1 = nn.get_weights()
	var w2 = copy.get_weights()
	assert_eq(w1.size(), w2.size(), "Weight counts should match")
	for i in w1.size():
		assert_approx(w1[i], w2[i], 0.0001, "Weight %d should match in clone" % i)


# ============================================================
# Crossover
# ============================================================

func _test_crossover_with_memory_produces_valid_child() -> void:
	var p1 = _make_memory_nn(10, 5, 3)
	var p2 = _make_memory_nn(10, 5, 3)
	var child = p1.crossover_with(p2)
	assert_true(child.use_memory, "Child should have memory")
	assert_eq(child.get_weight_count(), p1.get_weight_count(), "Child weight count should match parents")


# ============================================================
# Mutation
# ============================================================

func _test_mutate_changes_hh_weights() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var hh_before := PackedFloat32Array(nn.weights_hh)
	nn.mutate(1.0, 0.5)
	var changed := 0
	for i in hh_before.size():
		if abs(hh_before[i] - nn.weights_hh[i]) > 0.0001:
			changed += 1
	assert_gt(changed, 0, "Mutation should change context weights")


# ============================================================
# Weight get/set
# ============================================================

func _test_get_set_weights_roundtrip_with_memory() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var weights := nn.get_weights()
	var nn2 = _make_memory_nn(10, 5, 3)
	nn2.set_weights(weights)
	var w2 = nn2.get_weights()
	assert_eq(weights.size(), w2.size())
	for i in weights.size():
		assert_approx(weights[i], w2[i], 0.0001, "Weight %d should roundtrip" % i)


# ============================================================
# Persistence
# ============================================================

func _test_save_load_roundtrip_with_memory() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var test_path := "user://test_elman_memory.nn"
	nn.save_to_file(test_path)
	var loaded = NeuralNetwork.load_from_file(test_path)

	assert_not_null(loaded, "Loaded network should not be null")
	assert_eq(loaded.input_size, 10)
	assert_eq(loaded.hidden_size, 5)
	assert_eq(loaded.output_size, 3)
	assert_true(loaded.use_memory, "Memory flag should survive save/load")

	var w1 = nn.get_weights()
	var w2 = loaded.get_weights()
	assert_eq(w1.size(), w2.size())
	for i in w1.size():
		assert_approx(w1[i], w2[i], 0.0001, "Weight %d should survive save/load" % i)

	DirAccess.remove_absolute(test_path)


func _test_save_load_roundtrip_without_memory() -> void:
	var nn = NeuralNetwork.new(10, 5, 3)
	var test_path := "user://test_elman_nomem.nn"
	nn.save_to_file(test_path)
	var loaded = NeuralNetwork.load_from_file(test_path)

	assert_not_null(loaded)
	assert_false(loaded.use_memory, "Non-memory flag should survive save/load")

	var w1 = nn.get_weights()
	var w2 = loaded.get_weights()
	assert_eq(w1.size(), w2.size())
	for i in w1.size():
		assert_approx(w1[i], w2[i], 0.0001, "Weight %d should survive save/load" % i)

	DirAccess.remove_absolute(test_path)


# ============================================================
# Edge Cases
# ============================================================

func _test_enable_memory_idempotent() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var wc_before := nn.get_weight_count()
	nn.enable_memory()  # Call again — should be no-op
	assert_eq(nn.get_weight_count(), wc_before, "enable_memory should be idempotent")


func _test_extreme_inputs_bounded_with_memory() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(1000.0)
	for _step in 5:
		var out := nn.forward(inputs)
		for i in out.size():
			assert_in_range(out[i], -1.0, 1.0, "Extreme inputs should produce bounded output")


func _test_many_forward_passes_stay_bounded() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var inputs := PackedFloat32Array()
	inputs.resize(10)
	inputs.fill(0.8)
	for _step in 100:
		var out := nn.forward(inputs)
		for i in out.size():
			assert_in_range(out[i], -1.0, 1.0, "Output must stay bounded after many steps")
	for i in nn._prev_hidden.size():
		assert_in_range(nn._prev_hidden[i], -1.0, 1.0, "Hidden state must stay bounded")


func _test_different_sequences_different_results() -> void:
	var nn = _make_memory_nn(10, 5, 3)
	var input_a := PackedFloat32Array()
	input_a.resize(10)
	input_a.fill(0.5)
	var input_b := PackedFloat32Array()
	input_b.resize(10)
	input_b.fill(-0.5)

	# Sequence: A, A, A
	nn.reset_memory()
	nn.forward(input_a)
	nn.forward(input_a)
	var out_aaa := PackedFloat32Array(nn.forward(input_a))

	# Sequence: B, A, A (different history)
	nn.reset_memory()
	nn.forward(input_b)
	nn.forward(input_a)
	var out_baa := PackedFloat32Array(nn.forward(input_a))

	var any_different := false
	for i in out_aaa.size():
		if abs(out_aaa[i] - out_baa[i]) > 0.0001:
			any_different = true
			break
	assert_true(any_different, "Different input histories should produce different outputs")
