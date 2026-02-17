extends Node

## Debug script to test RustNeuralNetwork availability
func _ready():
	print("=== Testing RustNeuralNetwork ===")
	print("ClassDB.class_exists('RustNeuralNetwork'): ", ClassDB.class_exists(&"RustNeuralNetwork"))
	
	if ClassDB.class_exists(&"RustNeuralNetwork"):
		var instance = ClassDB.instantiate(&"RustNeuralNetwork")
		print("Instance created: ", instance)
		if instance:
			var net = instance.call(&"create", 10, 5, 2)
			print("Network created: ", net)
			if net:
				var inputs = PackedFloat32Array()
				inputs.resize(10)
				inputs.fill(0.5)
				var outputs = net.call(&"forward", inputs)
				print("Forward pass output: ", outputs)
	
	print("=== Test complete ===")
	queue_free()