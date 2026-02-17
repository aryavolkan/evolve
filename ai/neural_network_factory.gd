extends RefCounted
class_name NeuralNetworkFactory

## Factory for creating neural networks — uses RustNeuralNetwork when available,
## falls back to GDScript NeuralNetwork otherwise. Transparent to callers.
##
## Usage:
##   var net = NeuralNetworkFactory.create(86, 80, 6)
##   var out = net.forward(inputs)  # Same API regardless of backend
##
## The Rust backend provides ~5-15× faster forward passes, which matters
## during training with 20+ parallel arenas.

static var _use_rust: bool = false
static var _checked: bool = false
## Cached GDNativeScript for RustNeuralNetwork (avoids per-call ClassDB lookups)
static var _rust_script: Variant = null

static var GDScriptNN = preload("res://ai/neural_network.gd")


static func _check_rust_available() -> void:
	if _checked:
		return
	_checked = true
	
	# Check if RustNeuralNetwork class is registered (GDExtension loaded)
	_use_rust = ClassDB.class_exists(&"RustNeuralNetwork")
	
	if _use_rust:
		# Verify we can instantiate it
		var test_instance = ClassDB.instantiate(&"RustNeuralNetwork")
		if not test_instance:
			print("[NeuralNetworkFactory] RustNeuralNetwork class exists but cannot instantiate")
			_use_rust = false
		else:
			# Verify the create method exists
			if not test_instance.has_method(&"create"):
				print("[NeuralNetworkFactory] RustNeuralNetwork missing create() method")
				_use_rust = false
			else:
				# Try a test creation
				var test_net = test_instance.call(&"create", 10, 5, 2)
				if not test_net:
					print("[NeuralNetworkFactory] RustNeuralNetwork.create() returned null in test")
					_use_rust = false
	
	if _use_rust:
		print("[NeuralNetworkFactory] ✓ Using Rust backend (RustNeuralNetwork) - expect 5-15x faster forward passes")
	else:
		print("[NeuralNetworkFactory] ⚠ Using GDScript backend (check if evolve.gdextension is properly configured)")


static func is_rust_available() -> bool:
	_check_rust_available()
	return _use_rust


static func create(input_size: int, hidden_size: int, output_size: int) -> Variant:
	## Create a neural network with the best available backend.
	## Returns either a RustNeuralNetwork (Gd object) or a GDScript NeuralNetwork (RefCounted).
	## Both expose: forward(), get_weights(), set_weights(), get_weight_count()
	_check_rust_available()

	if _use_rust:
		# Create instance and call the create method on it
		var instance = ClassDB.instantiate(&"RustNeuralNetwork")
		if instance and instance.has_method(&"create"):
			var net = instance.call(&"create", input_size, hidden_size, output_size)
			if net:
				return net
			else:
				push_warning("RustNeuralNetwork.create() returned null, falling back to GDScript")
		else:
			push_warning("RustNeuralNetwork instance missing create() method, falling back to GDScript")
		
		# Fallback if Rust creation failed
		_use_rust = false
		return GDScriptNN.new(input_size, hidden_size, output_size)
	else:
		return GDScriptNN.new(input_size, hidden_size, output_size)


static func clone_network(network) -> Variant:
	## Clone a neural network (handles API difference: clone() vs clone_network()).
	if network.has_method(&"clone_network"):
		# RustNeuralNetwork uses clone_network()
		return network.clone_network()
	elif network.has_method(&"clone"):
		# GDScript NeuralNetwork uses clone()
		return network.clone()
	else:
		push_error("Cannot clone network: no clone/clone_network method")
		return null


static func enable_memory(network) -> void:
	## Enable Elman memory on a network (same API for both backends).
	if network.has_method(&"enable_memory"):
		network.enable_memory()


static func reset_memory(network) -> void:
	## Reset recurrent memory state (same API for both backends).
	if network.has_method(&"reset_memory"):
		network.reset_memory()


static func mutate_network(network, mutation_rate: float, mutation_strength: float) -> void:
	## Apply mutations (same API for both backends).
	network.mutate(mutation_rate, mutation_strength)


static func crossover(parent_a, parent_b) -> Variant:
	## Create offspring via crossover.
	## RustNeuralNetwork.crossover_with() takes Gd<RustNeuralNetwork>.
	## GDScript NeuralNetwork.crossover_with() takes any NeuralNetwork.
	return parent_a.crossover_with(parent_b)


static func load_from_file(path: String) -> Variant:
	## Load a network from file. Uses GDScript loader which supports all formats.
	## (Rust loader doesn't support JSON NEAT format)
	return GDScriptNN.load_from_file(path)
