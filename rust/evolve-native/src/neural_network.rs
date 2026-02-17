use godot::prelude::*;
use godot::classes::file_access::ModeFlags;
use godot::classes::FileAccess;
use rand::Rng;
use rand_distr::{Distribution, Normal};

/// A feedforward neural network with optional Elman recurrent memory.
///
/// Architecture: inputs -> hidden (tanh) -> outputs (tanh)
/// When use_memory is true, previous hidden state feeds back into hidden layer
/// via context weights, enabling temporal sequence learning (Elman network).
///
/// This is a Rust port of `ai/neural_network.gd` — same API surface, ~5-10x faster forward pass.
/// Class is named `RustNeuralNetwork` to coexist with the GDScript version during migration.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RustNeuralNetwork {
    base: Base<RefCounted>,

    #[var]
    input_size: i32,
    #[var]
    hidden_size: i32,
    #[var]
    output_size: i32,
    #[var]
    use_memory: bool,

    // Weight matrices (flat arrays, row-major)
    weights_ih: Vec<f32>, // input_size * hidden_size
    bias_h: Vec<f32>,     // hidden_size
    weights_ho: Vec<f32>, // hidden_size * output_size
    bias_o: Vec<f32>,     // output_size
    weights_hh: Vec<f32>, // hidden_size * hidden_size (Elman context)

    // Recurrent state
    prev_hidden: Vec<f32>,

    // Cached buffers (avoid allocation in forward pass)
    hidden: Vec<f32>,
    output: Vec<f32>,
}

#[godot_api]
impl RustNeuralNetwork {
    /// Create a new neural network with the given architecture.
    /// Weights are randomly initialized (Xavier-like, 4x scale for sparse inputs).
    #[func]
    fn create(input_size: i32, hidden_size: i32, output_size: i32) -> Gd<Self> {
        let i = input_size as usize;
        let h = hidden_size as usize;
        let o = output_size as usize;

        let mut nn = Gd::from_init_fn(|base| Self {
            base,
            input_size,
            hidden_size,
            output_size,
            use_memory: false,
            weights_ih: vec![0.0; i * h],
            bias_h: vec![0.0; h],
            weights_ho: vec![0.0; h * o],
            bias_o: vec![0.0; o],
            weights_hh: Vec::new(),
            prev_hidden: Vec::new(),
            hidden: vec![0.0; h],
            output: vec![0.0; o],
        });
        nn.bind_mut().randomize_weights();
        nn
    }

    /// Enable Elman recurrent memory. Call after construction.
    /// Allocates context weights (hidden_size x hidden_size) and hidden state buffer.
    #[func]
    fn enable_memory(&mut self) {
        if self.use_memory {
            return;
        }
        self.use_memory = true;
        let h = self.hidden_size as usize;
        self.prev_hidden = vec![0.0; h];
        self.weights_hh = vec![0.0; h * h];

        // Initialize context weights with smaller scale to avoid instability
        let hh_scale = (2.0_f32 / h as f32).sqrt();
        let mut rng = rand::thread_rng();
        for w in self.weights_hh.iter_mut() {
            *w = rng.gen_range(-hh_scale..hh_scale);
        }
    }

    /// Reset recurrent state to zeros. Call between episodes/evaluations.
    #[func]
    fn reset_memory(&mut self) {
        if self.use_memory {
            self.prev_hidden.fill(0.0);
        }
    }

    /// Randomize all weights (Xavier-like, 4x scale for sparse inputs).
    #[func]
    fn randomize_weights(&mut self) {
        let mut rng = rand::thread_rng();
        let ih_scale = (8.0_f32 / self.input_size as f32).sqrt();
        let ho_scale = (8.0_f32 / self.hidden_size as f32).sqrt();

        for w in self.weights_ih.iter_mut() {
            *w = rng.gen_range(-ih_scale..ih_scale);
        }
        for b in self.bias_h.iter_mut() {
            *b = rng.gen_range(-0.5..0.5);
        }
        for w in self.weights_ho.iter_mut() {
            *w = rng.gen_range(-ho_scale..ho_scale);
        }
        for b in self.bias_o.iter_mut() {
            *b = rng.gen_range(-0.5..0.5);
        }
    }

    /// Run forward pass through the network.
    /// Returns output array with values in [-1, 1] (tanh activation).
    #[func]
    fn forward(&mut self, inputs: PackedFloat32Array) -> PackedFloat32Array {
        let inp = inputs.as_slice();
        let input_size = self.input_size as usize;
        let hidden_size = self.hidden_size as usize;
        let output_size = self.output_size as usize;

        debug_assert_eq!(inp.len(), input_size, "Input size mismatch");

        // Hidden layer: h = tanh(W_ih @ inputs + W_hh @ prev_hidden + b_h)
        for h in 0..hidden_size {
            let mut sum = self.bias_h[h];
            let offset = h * input_size;
            // SAFETY: bounds are guaranteed by construction
            for i in 0..input_size {
                sum += unsafe {
                    self.weights_ih.get_unchecked(offset + i)
                        * inp.get_unchecked(i)
                };
            }
            if self.use_memory {
                let ctx_offset = h * hidden_size;
                for ph in 0..hidden_size {
                    sum += unsafe {
                        self.weights_hh.get_unchecked(ctx_offset + ph)
                            * self.prev_hidden.get_unchecked(ph)
                    };
                }
            }
            self.hidden[h] = sum.tanh();
        }

        // Store current hidden state for next timestep
        if self.use_memory {
            self.prev_hidden.copy_from_slice(&self.hidden);
        }

        // Output layer: o = tanh(W_ho @ hidden + b_o)
        for o in 0..output_size {
            let mut sum = self.bias_o[o];
            let offset = o * hidden_size;
            for h in 0..hidden_size {
                sum += unsafe {
                    self.weights_ho.get_unchecked(offset + h)
                        * self.hidden.get_unchecked(h)
                };
            }
            self.output[o] = sum.tanh();
        }

        PackedFloat32Array::from(self.output.as_slice())
    }

    /// Return all weights as a flat array for evolution.
    /// Order: weights_ih, bias_h, weights_ho, bias_o, [weights_hh if memory enabled]
    #[func]
    fn get_weights(&self) -> PackedFloat32Array {
        let cap = self.weights_ih.len()
            + self.bias_h.len()
            + self.weights_ho.len()
            + self.bias_o.len()
            + if self.use_memory { self.weights_hh.len() } else { 0 };
        let mut all = Vec::with_capacity(cap);
        all.extend_from_slice(&self.weights_ih);
        all.extend_from_slice(&self.bias_h);
        all.extend_from_slice(&self.weights_ho);
        all.extend_from_slice(&self.bias_o);
        if self.use_memory {
            all.extend_from_slice(&self.weights_hh);
        }
        PackedFloat32Array::from(all.as_slice())
    }

    /// Set all weights from a flat array.
    #[func]
    fn set_weights(&mut self, weights: PackedFloat32Array) {
        let w = weights.as_slice();
        let mut idx = 0usize;

        for v in self.weights_ih.iter_mut() {
            *v = w[idx];
            idx += 1;
        }
        for v in self.bias_h.iter_mut() {
            *v = w[idx];
            idx += 1;
        }
        for v in self.weights_ho.iter_mut() {
            *v = w[idx];
            idx += 1;
        }
        for v in self.bias_o.iter_mut() {
            *v = w[idx];
            idx += 1;
        }
        if self.use_memory && idx < w.len() {
            for v in self.weights_hh.iter_mut() {
                *v = w[idx];
                idx += 1;
            }
        }
    }

    /// Total number of trainable parameters.
    #[func]
    fn get_weight_count(&self) -> i32 {
        let count = self.weights_ih.len()
            + self.bias_h.len()
            + self.weights_ho.len()
            + self.bias_o.len()
            + if self.use_memory { self.weights_hh.len() } else { 0 };
        count as i32
    }

    /// Create a deep copy of this network.
    #[func]
    fn clone_network(&self) -> Gd<Self> {
        Gd::from_init_fn(|base| Self {
            base,
            input_size: self.input_size,
            hidden_size: self.hidden_size,
            output_size: self.output_size,
            use_memory: self.use_memory,
            weights_ih: self.weights_ih.clone(),
            bias_h: self.bias_h.clone(),
            weights_ho: self.weights_ho.clone(),
            bias_o: self.bias_o.clone(),
            weights_hh: self.weights_hh.clone(),
            prev_hidden: vec![0.0; if self.use_memory { self.hidden_size as usize } else { 0 }],
            hidden: vec![0.0; self.hidden_size as usize],
            output: vec![0.0; self.output_size as usize],
        })
    }

    /// Alias for clone_network() for API compatibility with GDScript NeuralNetwork.
    #[func]
    fn clone(&self) -> Gd<Self> {
        self.clone_network()
    }

    /// Apply Gaussian mutations to weights.
    /// mutation_rate: probability of mutating each weight
    /// mutation_strength: standard deviation of mutation noise
    /// Batch forward pass for multiple agents sharing the same network weights.
    /// Useful for parallel evaluation during evolution where all agents use the same genome.
    /// inputs_array: Array of PackedFloat32Array (one per agent)
    /// Returns: Array of PackedFloat32Array (outputs for each agent)
    #[func]
    fn batch_forward(&self, inputs_array: Array<PackedFloat32Array>) -> Array<PackedFloat32Array> {
        let batch_size = inputs_array.len();
        let input_size = self.input_size as usize;
        let hidden_size = self.hidden_size as usize;
        let output_size = self.output_size as usize;
        
        let mut outputs = Array::<PackedFloat32Array>::new();
        
        // Pre-allocate buffers for the entire batch to minimize allocations
        let mut hidden_states = vec![0.0f32; batch_size * hidden_size];
        let mut output_states = vec![0.0f32; batch_size * output_size];
        
        // Process each agent
        for idx in 0..batch_size {
            let Some(inputs) = inputs_array.get(idx) else { continue; };
            let inp = inputs.as_slice();
            debug_assert_eq!(inp.len(), input_size, "Input size mismatch");
            
            let hidden_offset = idx * hidden_size;
            let output_offset = idx * output_size;
            
            // Hidden layer computation
            for h in 0..hidden_size {
                let mut sum = self.bias_h[h];
                let weight_offset = h * input_size;
                
                // Input -> Hidden
                for i in 0..input_size {
                    sum += unsafe {
                        self.weights_ih.get_unchecked(weight_offset + i)
                            * inp.get_unchecked(i)
                    };
                }
                
                // Note: In batch mode, we don't use recurrent memory as each agent
                // would need its own memory state. For stateful batch processing,
                // use individual forward() calls with persistent network instances.
                
                hidden_states[hidden_offset + h] = sum.tanh();
            }
            
            // Output layer computation
            for o in 0..output_size {
                let mut sum = self.bias_o[o];
                let weight_offset = o * hidden_size;
                
                // Hidden -> Output
                for h in 0..hidden_size {
                    sum += unsafe {
                        self.weights_ho.get_unchecked(weight_offset + h)
                            * hidden_states.get_unchecked(hidden_offset + h)
                    };
                }
                
                output_states[output_offset + o] = sum.tanh();
            }
            
            // Pack this agent's output
            let agent_output = &output_states[output_offset..output_offset + output_size];
            outputs.push(&PackedFloat32Array::from(agent_output));
        }
        
        outputs
    }

    /// Batch forward pass for multiple networks with individual states.
    /// This is useful when agents have memory (Elman networks) and need persistent state.
    /// networks: Array of RustNeuralNetwork instances
    /// inputs_array: Array of PackedFloat32Array (one per network)
    /// Returns: Array of PackedFloat32Array (outputs for each network)
    #[func]
    fn batch_forward_stateful(networks: Array<Gd<RustNeuralNetwork>>, inputs_array: Array<PackedFloat32Array>) -> Array<PackedFloat32Array> {
        debug_assert_eq!(networks.len(), inputs_array.len(), "Networks and inputs array length mismatch");
        
        let mut outputs = Array::<PackedFloat32Array>::new();
        
        // Process each network-input pair
        for idx in 0..networks.len() {
            if let Some(mut network) = networks.get(idx) {
                if let Some(inputs) = inputs_array.get(idx) {
                    let output = network.bind_mut().forward(inputs);
                    outputs.push(&output);
                }
            }
        }
        
        outputs
    }    fn mutate(&mut self, mutation_rate: f64, mutation_strength: f64) {
        let mut rng = rand::thread_rng();
        let normal = Normal::new(0.0, mutation_strength).unwrap();
        let rate = mutation_rate;

        let mutate_array = |arr: &mut [f32], rng: &mut rand::rngs::ThreadRng, normal: &Normal<f64>, rate: f64| {
            for w in arr.iter_mut() {
                if rng.gen::<f64>() < rate {
                    *w += normal.sample(rng) as f32;
                }
            }
        };

        mutate_array(&mut self.weights_ih, &mut rng, &normal, rate);
        mutate_array(&mut self.bias_h, &mut rng, &normal, rate);
        mutate_array(&mut self.weights_ho, &mut rng, &normal, rate);
        mutate_array(&mut self.bias_o, &mut rng, &normal, rate);
        if self.use_memory {
            mutate_array(&mut self.weights_hh, &mut rng, &normal, rate);
        }
    }

    /// Create a child network by combining weights from two parents.
    /// Uses two-point crossover to preserve weight patterns from each parent.
    #[func]
    fn crossover_with(&self, other: Gd<RustNeuralNetwork>) -> Gd<Self> {
        let other_ref = other.bind();
        let weights_a = self.get_weights_vec();
        let weights_b = other_ref.get_weights_vec();
        let len = weights_a.len();

        let mut rng = rand::thread_rng();
        let mut point1 = rng.gen_range(0..len);
        let mut point2 = rng.gen_range(0..len);
        if point1 > point2 {
            std::mem::swap(&mut point1, &mut point2);
        }

        let mut child_weights = weights_a.clone();
        for i in point1..point2 {
            child_weights[i] = weights_b[i];
        }

        let mut child = Self::create(self.input_size, self.hidden_size, self.output_size);
        if self.use_memory {
            child.bind_mut().enable_memory();
        }
        let packed = PackedFloat32Array::from(child_weights.as_slice());
        child.bind_mut().set_weights(packed);
        child
    }

    /// Save network to a binary file.
    /// Format: [in, hid, out, use_memory_flag, weight_count, weights...]
    #[func]
    fn save_to_file(&self, path: GString) {
        let Some(mut file) = FileAccess::open(&path, ModeFlags::WRITE) else {
            godot_error!("Failed to open file for writing: {}", path);
            return;
        };

        file.store_32(self.input_size as u32);
        file.store_32(self.hidden_size as u32);
        file.store_32(self.output_size as u32);
        file.store_32(if self.use_memory { 1 } else { 0 });

        let weights = self.get_weights_vec();
        file.store_32(weights.len() as u32);
        for &w in &weights {
            file.store_float(w);
        }
    }

    /// Load network from a binary file.
    /// Compatible with the GDScript NeuralNetwork binary format.
    /// Does NOT support JSON NEAT genome format (use the GDScript version for that).
    #[func]
    fn load_from_file(path: GString) -> Option<Gd<RustNeuralNetwork>> {
        let file = FileAccess::open(&path, ModeFlags::READ);
        let mut file = if let Some(f) = file {
            f
        } else {
            // Fallback for packaged demos
            let fallback = format!("res://models/{}", path.to_string().rsplit('/').next().unwrap_or(""));
            let f = FileAccess::open(&GString::from(&fallback), ModeFlags::READ)?;
            f
        };

        // Peek first byte — if '{' it's JSON, which we don't handle in Rust
        let first_byte = file.get_8();
        if first_byte == 0x7B {
            godot_warn!("RustNeuralNetwork::load_from_file: JSON NEAT format not supported, use GDScript NeuralNetwork.load_from_file()");
            return None;
        }
        file.seek(0);

        let in_size = file.get_32() as i32;
        let hid_size = file.get_32() as i32;
        let out_size = file.get_32() as i32;

        // Sanity check
        if in_size > 10000 || hid_size > 10000 || out_size > 10000 {
            godot_error!(
                "Network file appears corrupt (unreasonable sizes: in={} hid={} out={})",
                in_size, hid_size, out_size
            );
            return None;
        }

        // Format detection: 4th u32 is use_memory flag (0 or 1) or legacy weight_count (>1)
        let fourth = file.get_32();
        let (has_memory, weight_count) = if fourth > 1 {
            // Legacy format
            (false, fourth as usize)
        } else {
            // New format
            (fourth == 1, file.get_32() as usize)
        };

        // Sanity check weight count
        let max_expected = ((in_size * hid_size + hid_size + hid_size * out_size + out_size
            + hid_size * hid_size) * 2) as usize;
        if weight_count > max_expected || weight_count > 1_000_000 {
            godot_error!(
                "Network file appears corrupt (weight_count={}, max_expected={})",
                weight_count, max_expected
            );
            return None;
        }

        let mut weights = Vec::with_capacity(weight_count);
        for _ in 0..weight_count {
            weights.push(file.get_float());
        }

        let mut nn = Self::create(in_size, hid_size, out_size);
        if has_memory {
            nn.bind_mut().enable_memory();
        }
        let packed = PackedFloat32Array::from(weights.as_slice());
        nn.bind_mut().set_weights(packed);
        Some(nn)
    }
}

// Private helpers (not exposed to GDScript)
impl RustNeuralNetwork {
    fn get_weights_vec(&self) -> Vec<f32> {
        let cap = self.weights_ih.len()
            + self.bias_h.len()
            + self.weights_ho.len()
            + self.bias_o.len()
            + if self.use_memory { self.weights_hh.len() } else { 0 };
        let mut all = Vec::with_capacity(cap);
        all.extend_from_slice(&self.weights_ih);
        all.extend_from_slice(&self.bias_h);
        all.extend_from_slice(&self.weights_ho);
        all.extend_from_slice(&self.bias_o);
        if self.use_memory {
            all.extend_from_slice(&self.weights_hh);
        }
        all
    }
}
