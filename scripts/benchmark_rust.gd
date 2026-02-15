extends SceneTree
## Benchmark: GDScript NeuralNetwork vs RustNeuralNetwork forward pass.
##
## Run with:  godot --headless --script scripts/benchmark_rust.gd
##
## Tests 10,000 forward passes with the actual game config (86→80→6).

const N := 10_000
const INPUT_SIZE := 86
const HIDDEN_SIZE := 80
const OUTPUT_SIZE := 6

func _init() -> void:
	print("=== Neural Network Forward Pass Benchmark ===")
	print("Config: %d inputs → %d hidden → %d outputs" % [INPUT_SIZE, HIDDEN_SIZE, OUTPUT_SIZE])
	print("Iterations: %d\n" % N)

	# Build a fixed input vector
	var inputs := PackedFloat32Array()
	inputs.resize(INPUT_SIZE)
	for i in INPUT_SIZE:
		inputs[i] = 0.5

	# --- GDScript NeuralNetwork ---
	var NNScript = load("res://ai/neural_network.gd")
	var gd_nn = NNScript.new(INPUT_SIZE, HIDDEN_SIZE, OUTPUT_SIZE)

	# Warmup
	for i in 100:
		gd_nn.forward(inputs)

	var t0 := Time.get_ticks_usec()
	for i in N:
		gd_nn.forward(inputs)
	var t1 := Time.get_ticks_usec()
	var gd_us := t1 - t0
	var gd_per := float(gd_us) / N

	print("GDScript NeuralNetwork:")
	print("  Total: %.2f ms" % (gd_us / 1000.0))
	print("  Per pass: %.2f µs" % gd_per)
	print("  Throughput: %.0f passes/sec\n" % (N / (gd_us / 1_000_000.0)))

	# --- RustNeuralNetwork ---
	var rust_nn := RustNeuralNetwork.create(INPUT_SIZE, HIDDEN_SIZE, OUTPUT_SIZE)

	# Warmup
	for i in 100:
		rust_nn.forward(inputs)

	var t2 := Time.get_ticks_usec()
	for i in N:
		rust_nn.forward(inputs)
	var t3 := Time.get_ticks_usec()
	var rust_us := t3 - t2
	var rust_per := float(rust_us) / N

	print("RustNeuralNetwork:")
	print("  Total: %.2f ms" % (rust_us / 1000.0))
	print("  Per pass: %.2f µs" % rust_per)
	print("  Throughput: %.0f passes/sec\n" % (N / (rust_us / 1_000_000.0)))

	# --- Comparison ---
	var speedup := gd_per / rust_per
	print("🚀 Speedup: %.1fx faster (Rust vs GDScript)" % speedup)
	print("")

	# --- Correctness check: same weights → same output ---
	print("=== Correctness Check ===")
	var gd_check = NNScript.new(INPUT_SIZE, HIDDEN_SIZE, OUTPUT_SIZE)
	var rust_check := RustNeuralNetwork.create(INPUT_SIZE, HIDDEN_SIZE, OUTPUT_SIZE)

	# Copy GDScript weights to Rust
	var weights: PackedFloat32Array = gd_check.get_weights()
	rust_check.set_weights(weights)

	var gd_out: PackedFloat32Array = gd_check.forward(inputs)
	var rust_out: PackedFloat32Array = rust_check.forward(inputs)

	var max_diff := 0.0
	for i in OUTPUT_SIZE:
		var diff := absf(gd_out[i] - rust_out[i])
		if diff > max_diff:
			max_diff = diff

	print("Max output difference: %.10f" % max_diff)
	if max_diff < 0.001:
		print("✅ Outputs match (within float32 tolerance)")
	else:
		print("❌ Outputs diverge! Check implementation.")
		for i in OUTPUT_SIZE:
			print("  [%d] GD=%.8f  Rust=%.8f  diff=%.8f" % [i, gd_out[i], rust_out[i], absf(gd_out[i] - rust_out[i])])

	quit()
