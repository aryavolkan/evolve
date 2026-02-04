extends RefCounted

## A simple feedforward neural network with evolvable weights.
## Architecture: inputs -> hidden (tanh) -> outputs (tanh)

var input_size: int
var hidden_size: int
var output_size: int

# Weight matrices (stored as flat arrays for easy mutation)
var weights_ih: PackedFloat32Array  # Input to hidden
var bias_h: PackedFloat32Array      # Hidden bias
var weights_ho: PackedFloat32Array  # Hidden to output
var bias_o: PackedFloat32Array      # Output bias

# Cached arrays for forward pass (avoid allocations)
var _hidden: PackedFloat32Array
var _output: PackedFloat32Array


func _init(p_input_size: int = 64, p_hidden_size: int = 32, p_output_size: int = 8) -> void:
	input_size = p_input_size
	hidden_size = p_hidden_size
	output_size = p_output_size

	# Initialize weight arrays
	weights_ih.resize(input_size * hidden_size)
	bias_h.resize(hidden_size)
	weights_ho.resize(hidden_size * output_size)
	bias_o.resize(output_size)

	# Cache arrays
	_hidden.resize(hidden_size)
	_output.resize(output_size)

	# Random initialization (Xavier-like)
	randomize_weights()


func randomize_weights() -> void:
	# Larger weights to produce meaningful outputs with sparse inputs
	# (only ~25% of sensor inputs are typically non-zero)
	var ih_scale := sqrt(8.0 / input_size)  # 4x larger than standard Xavier
	var ho_scale := sqrt(8.0 / hidden_size)

	for i in weights_ih.size():
		weights_ih[i] = randf_range(-ih_scale, ih_scale)

	for i in bias_h.size():
		bias_h[i] = randf_range(-0.5, 0.5)  # Non-zero bias for variety

	for i in weights_ho.size():
		weights_ho[i] = randf_range(-ho_scale, ho_scale)

	for i in bias_o.size():
		bias_o[i] = randf_range(-0.5, 0.5)  # Non-zero bias for variety


func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
	## Run forward pass through the network.
	## Returns output array with values in [-1, 1] (tanh activation).

	assert(inputs.size() == input_size, "Input size mismatch")

	# Hidden layer: h = tanh(W_ih @ inputs + b_h)
	for h in hidden_size:
		var sum := bias_h[h]
		var weight_offset := h * input_size
		for i in input_size:
			sum += weights_ih[weight_offset + i] * inputs[i]
		_hidden[h] = tanh(sum)

	# Output layer: o = tanh(W_ho @ hidden + b_o)
	for o in output_size:
		var sum := bias_o[o]
		var weight_offset := o * hidden_size
		for h in hidden_size:
			sum += weights_ho[weight_offset + h] * _hidden[h]
		_output[o] = tanh(sum)

	return _output


func get_weights() -> PackedFloat32Array:
	## Return all weights as a flat array for evolution.
	var all_weights := PackedFloat32Array()
	all_weights.append_array(weights_ih)
	all_weights.append_array(bias_h)
	all_weights.append_array(weights_ho)
	all_weights.append_array(bias_o)
	return all_weights


func set_weights(weights: PackedFloat32Array) -> void:
	## Set all weights from a flat array.
	var idx := 0

	for i in weights_ih.size():
		weights_ih[i] = weights[idx]
		idx += 1

	for i in bias_h.size():
		bias_h[i] = weights[idx]
		idx += 1

	for i in weights_ho.size():
		weights_ho[i] = weights[idx]
		idx += 1

	for i in bias_o.size():
		bias_o[i] = weights[idx]
		idx += 1


func get_weight_count() -> int:
	## Total number of trainable parameters.
	return weights_ih.size() + bias_h.size() + weights_ho.size() + bias_o.size()


func clone():
	## Create a deep copy of this network.
	var script = get_script()
	var copy = script.new(input_size, hidden_size, output_size)
	copy.set_weights(get_weights())
	return copy


func mutate(mutation_rate: float = 0.1, mutation_strength: float = 0.3) -> void:
	## Apply Gaussian mutations to weights.
	## mutation_rate: probability of mutating each weight
	## mutation_strength: standard deviation of mutation noise

	for i in weights_ih.size():
		if randf() < mutation_rate:
			weights_ih[i] += randfn(0.0, mutation_strength)

	for i in bias_h.size():
		if randf() < mutation_rate:
			bias_h[i] += randfn(0.0, mutation_strength)

	for i in weights_ho.size():
		if randf() < mutation_rate:
			weights_ho[i] += randfn(0.0, mutation_strength)

	for i in bias_o.size():
		if randf() < mutation_rate:
			bias_o[i] += randfn(0.0, mutation_strength)


func crossover_with(other):
	## Create a child network by combining weights from two parents.
	## Uses two-point crossover to preserve weight patterns from each parent.
	var script = get_script()
	var child = script.new(input_size, hidden_size, output_size)
	var weights_a: PackedFloat32Array = get_weights()
	var weights_b: PackedFloat32Array = other.get_weights()
	var child_weights = PackedFloat32Array()
	child_weights.resize(weights_a.size())

	# Two-point crossover: pick two random points and swap the middle segment
	var point1 := randi() % weights_a.size()
	var point2 := randi() % weights_a.size()
	if point1 > point2:
		var tmp := point1
		point1 = point2
		point2 = tmp

	for i in weights_a.size():
		if i >= point1 and i < point2:
			child_weights[i] = weights_b[i]
		else:
			child_weights[i] = weights_a[i]

	child.set_weights(child_weights)
	return child


func save_to_file(path: String) -> void:
	## Save network to a file.
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_32(input_size)
		file.store_32(hidden_size)
		file.store_32(output_size)
		var weights := get_weights()
		file.store_32(weights.size())
		for w in weights:
			file.store_float(w)
		file.close()


static func load_from_file(path: String):
	## Load network from a file.
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null

	var in_size := file.get_32()
	var hid_size := file.get_32()
	var out_size := file.get_32()
	var weight_count := file.get_32()

	var weights := PackedFloat32Array()
	weights.resize(weight_count)
	for i in weight_count:
		weights[i] = file.get_float()

	file.close()

	var script = load("res://ai/neural_network.gd")
	var network = script.new(in_size, hid_size, out_size)
	network.set_weights(weights)
	return network
