//! Standalone correctness & micro-benchmark tests for the neural network forward pass.
//! These test the pure math (no Godot types) to verify the implementation is correct.
//!
//! Run with: cargo test --test nn_correctness
//! (Won't work for cdylib crate — see standalone binary below)

// Since evolve-native is a cdylib and deeply tied to Godot, we reimplement the
// core forward pass logic here for testing. This ensures the math is correct.

use std::time::Instant;

/// Pure-Rust feedforward neural network (mirrors RustNeuralNetwork logic exactly)
struct NeuralNetwork {
    input_size: usize,
    hidden_size: usize,
    output_size: usize,
    weights_ih: Vec<f32>,
    bias_h: Vec<f32>,
    weights_ho: Vec<f32>,
    bias_o: Vec<f32>,
    hidden: Vec<f32>,
    output: Vec<f32>,
}

impl NeuralNetwork {
    fn new(input_size: usize, hidden_size: usize, output_size: usize) -> Self {
        Self {
            input_size,
            hidden_size,
            output_size,
            weights_ih: vec![0.1; input_size * hidden_size],
            bias_h: vec![0.0; hidden_size],
            weights_ho: vec![0.1; hidden_size * output_size],
            bias_o: vec![0.0; output_size],
            hidden: vec![0.0; hidden_size],
            output: vec![0.0; output_size],
        }
    }

    fn forward(&mut self, inputs: &[f32]) -> &[f32] {
        assert_eq!(inputs.len(), self.input_size);

        // Hidden layer
        for h in 0..self.hidden_size {
            let mut sum = self.bias_h[h];
            let offset = h * self.input_size;
            for i in 0..self.input_size {
                sum += self.weights_ih[offset + i] * inputs[i];
            }
            self.hidden[h] = sum.tanh();
        }

        // Output layer
        for o in 0..self.output_size {
            let mut sum = self.bias_o[o];
            let offset = o * self.hidden_size;
            for h in 0..self.hidden_size {
                sum += self.weights_ho[offset + h] * self.hidden[h];
            }
            self.output[o] = sum.tanh();
        }

        &self.output
    }
}

#[test]
fn test_zero_input_produces_tanh_of_bias() {
    let mut nn = NeuralNetwork::new(4, 3, 2);
    // All weights 0.1, biases 0.0 — zero input should give tanh(0) = 0 for hidden,
    // then tanh(0) = 0 for output
    let out = nn.forward(&[0.0, 0.0, 0.0, 0.0]);
    for &v in out {
        assert!((v - 0.0).abs() < 1e-6, "Expected ~0.0, got {}", v);
    }
}

#[test]
fn test_outputs_bounded() {
    let mut nn = NeuralNetwork::new(86, 80, 6);
    // Large inputs should still produce outputs in [-1, 1] due to tanh
    let inputs = vec![100.0; 86];
    let out = nn.forward(&inputs);
    for &v in out {
        assert!(v >= -1.0 && v <= 1.0, "Output {} out of [-1,1]", v);
    }
}

#[test]
fn test_deterministic() {
    let mut nn = NeuralNetwork::new(86, 80, 6);
    let inputs = vec![0.5; 86];
    let out1: Vec<f32> = nn.forward(&inputs).to_vec();
    let out2: Vec<f32> = nn.forward(&inputs).to_vec();
    assert_eq!(out1, out2, "Forward pass should be deterministic");
}

#[test]
fn test_known_values() {
    // Tiny network: 2 inputs, 2 hidden, 1 output
    // Set specific weights to verify computation
    let mut nn = NeuralNetwork::new(2, 2, 1);
    nn.weights_ih = vec![1.0, 0.0, 0.0, 1.0]; // identity-ish
    nn.bias_h = vec![0.0, 0.0];
    nn.weights_ho = vec![1.0, 1.0];
    nn.bias_o = vec![0.0];

    let out = nn.forward(&[0.5, -0.3]);
    // hidden[0] = tanh(1.0*0.5 + 0.0*(-0.3) + 0) = tanh(0.5)
    // hidden[1] = tanh(0.0*0.5 + 1.0*(-0.3) + 0) = tanh(-0.3)
    // output[0] = tanh(tanh(0.5) + tanh(-0.3))
    let h0 = 0.5_f32.tanh();
    let h1 = (-0.3_f32).tanh();
    let expected = (h0 + h1).tanh();
    assert!(
        (out[0] - expected).abs() < 1e-6,
        "Expected {}, got {}",
        expected,
        out[0]
    );
}

#[test]
fn test_game_config_dimensions() {
    // Actual game config: 86 inputs, 80 hidden, 6 outputs
    let mut nn = NeuralNetwork::new(86, 80, 6);
    let inputs = vec![0.0; 86];
    let out = nn.forward(&inputs);
    assert_eq!(out.len(), 6);
}

#[test]
fn bench_forward_pass_10k() {
    let mut nn = NeuralNetwork::new(86, 80, 6);
    let inputs = vec![0.5; 86];

    // Warmup
    for _ in 0..100 {
        nn.forward(&inputs);
    }

    let n = 10_000;
    let start = Instant::now();
    for _ in 0..n {
        nn.forward(&inputs);
    }
    let elapsed = start.elapsed();
    let per_pass = elapsed / n;
    println!("\n=== Rust Pure Forward Pass Benchmark ===");
    println!("  {} passes in {:.2?}", n, elapsed);
    println!("  {:.2?} per pass", per_pass);
    println!("  {:.0} passes/sec", n as f64 / elapsed.as_secs_f64());
}
