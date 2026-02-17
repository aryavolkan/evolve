use godot::prelude::*;

/// A NEAT variable-topology neural network.
///
/// Rust port of `ai/neat_network.gd` — same API surface, ~8-15x faster forward pass.
/// Uses Vec-based topological-order evaluation instead of Dictionary lookups.
///
/// Class is named `RustNeatNetwork` to coexist with the GDScript version during migration.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RustNeatNetwork {
    base: Base<RefCounted>,

    /// Topologically sorted node indices (into node_biases)
    node_order: Vec<usize>,

    /// Node biases indexed by internal node index
    node_biases: Vec<f32>,

    /// Map from node_id (NEAT innovation ID) → internal index
    #[allow(dead_code)]
    id_to_idx: Vec<(i32, usize)>, // sorted by id for binary search

    /// Input node internal indices (in order)
    input_indices: Vec<usize>,
    /// Output node internal indices (in order)
    output_indices: Vec<usize>,

    /// Connections: (from_idx, to_idx, weight) — only enabled
    connections: Vec<(usize, usize, f32)>,

    /// Per-node: precomputed list of (from_idx, weight) for incoming connections
    /// incoming[node_idx] = Vec<(from_idx, weight)>
    incoming: Vec<Vec<(usize, f32)>>,

    /// Current activation values
    activations: Vec<f32>,

    /// Cached input membership for skipping in forward pass
    is_input: Vec<bool>,

    /// Cached output array (avoid allocation per forward call)
    cached_outputs: PackedFloat32Array,
}

impl RustNeatNetwork {
    #[allow(dead_code)]
    fn lookup_idx(&self, node_id: i32) -> Option<usize> {
        self.id_to_idx
            .binary_search_by_key(&node_id, |&(id, _)| id)
            .ok()
            .map(|pos| self.id_to_idx[pos].1)
    }
}

#[godot_api]
impl RustNeatNetwork {
    /// Build a NEAT network from node and connection data.
    ///
    /// node_ids: PackedInt32Array of node IDs
    /// node_types: PackedInt32Array of node types (0=input, 1=hidden, 2=output)
    /// node_biases: PackedFloat32Array of node biases
    /// conn_in_ids: PackedInt32Array of connection input node IDs
    /// conn_out_ids: PackedInt32Array of connection output node IDs
    /// conn_weights: PackedFloat32Array of connection weights
    /// conn_enabled: packed byte array (0/1) — which connections are enabled
    #[func]
    fn create(
        node_ids: PackedInt32Array,
        node_types: PackedInt32Array,
        node_biases_arr: PackedFloat32Array,
        conn_in_ids: PackedInt32Array,
        conn_out_ids: PackedInt32Array,
        conn_weights: PackedFloat32Array,
        conn_enabled: PackedByteArray,
    ) -> Gd<Self> {
        let n_ids = node_ids.as_slice();
        let n_types = node_types.as_slice();
        let n_biases = node_biases_arr.as_slice();
        let num_nodes = n_ids.len();

        // Build id→idx mapping
        let mut id_to_idx: Vec<(i32, usize)> = Vec::with_capacity(num_nodes);
        let mut node_biases_vec = Vec::with_capacity(num_nodes);
        let mut input_indices = Vec::new();
        let mut output_indices = Vec::new();

        for i in 0..num_nodes {
            id_to_idx.push((n_ids[i], i));
            node_biases_vec.push(n_biases[i]);
            match n_types[i] {
                0 => input_indices.push(i),
                2 => output_indices.push(i),
                _ => {}
            }
        }
        id_to_idx.sort_unstable_by_key(|&(id, _)| id);

        // Helper closure for id lookup
        let lookup = |node_id: i32| -> Option<usize> {
            id_to_idx
                .binary_search_by_key(&node_id, |&(id, _)| id)
                .ok()
                .map(|pos| id_to_idx[pos].1)
        };

        // Build enabled connections
        let c_in = conn_in_ids.as_slice();
        let c_out = conn_out_ids.as_slice();
        let c_w = conn_weights.as_slice();
        let c_en = conn_enabled.as_slice();
        let num_conns = c_in.len();

        let mut connections = Vec::new();
        let mut incoming: Vec<Vec<(usize, f32)>> = vec![Vec::new(); num_nodes];

        for c in 0..num_conns {
            if c_en[c] == 0 {
                continue;
            }
            if let (Some(from_idx), Some(to_idx)) = (lookup(c_in[c]), lookup(c_out[c])) {
                connections.push((from_idx, to_idx, c_w[c]));
                incoming[to_idx].push((from_idx, c_w[c]));
            }
        }

        // Topological sort (Kahn's algorithm)
        let mut in_degree = vec![0u32; num_nodes];
        let mut adjacency: Vec<Vec<usize>> = vec![Vec::new(); num_nodes];

        for &(from, to, _) in &connections {
            in_degree[to] += 1;
            adjacency[from].push(to);
        }

        let mut queue: Vec<usize> = in_degree
            .iter()
            .enumerate()
            .filter(|(_, &d)| d == 0)
            .map(|(i, _)| i)
            .collect();

        let mut node_order = Vec::with_capacity(num_nodes);
        let mut head = 0;
        while head < queue.len() {
            let node = queue[head];
            head += 1;
            node_order.push(node);
            for &downstream in &adjacency[node] {
                in_degree[downstream] -= 1;
                if in_degree[downstream] == 0 {
                    queue.push(downstream);
                }
            }
        }

        // Cycle fallback: type-based order (inputs, hidden, outputs)
        if node_order.len() < num_nodes {
            node_order.clear();
            for (i, &t) in n_types.iter().enumerate() {
                if t == 0 {
                    node_order.push(i);
                }
            }
            for (i, &t) in n_types.iter().enumerate() {
                if t == 1 {
                    node_order.push(i);
                }
            }
            for (i, &t) in n_types.iter().enumerate() {
                if t == 2 {
                    node_order.push(i);
                }
            }
        }

        let activations = vec![0.0f32; num_nodes];

        // Precompute input membership
        let mut is_input = vec![false; num_nodes];
        for &idx in &input_indices {
            is_input[idx] = true;
        }

        // Pre-allocate output array
        let mut cached_outputs = PackedFloat32Array::new();
        cached_outputs.resize(output_indices.len());

        Gd::from_init_fn(|base| Self {
            base,
            node_order,
            node_biases: node_biases_vec,
            id_to_idx,
            input_indices,
            output_indices,
            connections,
            incoming,
            activations,
            is_input,
            cached_outputs,
        })
    }

    /// Forward pass: feed inputs, return outputs.
    #[func]
    fn forward(&mut self, inputs: PackedFloat32Array) -> PackedFloat32Array {
        let inp = inputs.as_slice();

        // Set input activations
        for (i, &idx) in self.input_indices.iter().enumerate() {
            self.activations[idx] = if i < inp.len() { inp[i] } else { 0.0 };
        }

        // Process in topological order (skip inputs via cached bitmap)
        for &node_idx in &self.node_order {
            if self.is_input[node_idx] {
                continue;
            }

            let mut sum = self.node_biases[node_idx];
            for &(from_idx, weight) in &self.incoming[node_idx] {
                sum += self.activations[from_idx] * weight;
            }
            self.activations[node_idx] = sum.tanh();
        }

        // Collect outputs into cached array
        let out_slice = self.cached_outputs.as_mut_slice();
        for (i, &idx) in self.output_indices.iter().enumerate() {
            out_slice[i] = self.activations[idx];
        }
        self.cached_outputs.clone()
    }

    #[func]
    fn get_input_count(&self) -> i32 {
        self.input_indices.len() as i32
    }

    #[func]
    fn get_output_count(&self) -> i32 {
        self.output_indices.len() as i32
    }

    #[func]
    fn get_node_count(&self) -> i32 {
        self.node_biases.len() as i32
    }

    #[func]
    fn get_connection_count(&self) -> i32 {
        self.connections.len() as i32
    }

    /// Reset all activations to zero.
    #[func]
    fn reset(&mut self) {
        self.activations.fill(0.0);
    }
}

#[cfg(test)]
mod tests {
    // Note: godot types aren't available in `cargo test` without the engine.
    // These tests verify the core logic using plain Rust types.

    /// Simulate the forward pass logic without Godot types.
    fn forward_plain(
        input_indices: &[usize],
        output_indices: &[usize],
        node_order: &[usize],
        node_biases: &[f32],
        incoming: &[Vec<(usize, f32)>],
        inputs: &[f32],
    ) -> Vec<f32> {
        let num_nodes = node_biases.len();
        let mut activations = vec![0.0f32; num_nodes];

        // Set inputs
        for (i, &idx) in input_indices.iter().enumerate() {
            activations[idx] = if i < inputs.len() { inputs[i] } else { 0.0 };
        }

        let mut is_input = vec![false; num_nodes];
        for &idx in input_indices {
            is_input[idx] = true;
        }

        for &node_idx in node_order {
            if is_input[node_idx] {
                continue;
            }
            let mut sum = node_biases[node_idx];
            for &(from_idx, weight) in &incoming[node_idx] {
                sum += activations[from_idx] * weight;
            }
            activations[node_idx] = sum.tanh();
        }

        output_indices.iter().map(|&idx| activations[idx]).collect()
    }

    #[test]
    fn test_simple_network() {
        // 2 inputs (idx 0,1), 1 output (idx 2)
        // connections: 0→2 weight 1.0, 1→2 weight -1.0
        // bias for output = 0.0
        let input_indices = vec![0, 1];
        let output_indices = vec![2];
        let node_order = vec![0, 1, 2];
        let node_biases = vec![0.0, 0.0, 0.0];
        let incoming = vec![
            vec![],                    // node 0: input
            vec![],                    // node 1: input
            vec![(0, 1.0), (1, -1.0)], // node 2: output
        ];

        let out = forward_plain(
            &input_indices,
            &output_indices,
            &node_order,
            &node_biases,
            &incoming,
            &[1.0, 0.5],
        );
        // output = tanh(1.0 * 1.0 + 0.5 * -1.0) = tanh(0.5)
        let expected = 0.5_f32.tanh();
        assert!((out[0] - expected).abs() < 1e-6);
    }

    #[test]
    fn test_with_hidden_and_bias() {
        // 1 input (idx 0), 1 hidden (idx 1), 1 output (idx 2)
        // 0→1 weight 2.0, 1→2 weight 0.5
        // biases: [0, 0.1, -0.2]
        let input_indices = vec![0];
        let output_indices = vec![2];
        let node_order = vec![0, 1, 2];
        let node_biases = vec![0.0, 0.1, -0.2];
        let incoming = vec![vec![], vec![(0, 2.0)], vec![(1, 0.5)]];

        let out = forward_plain(
            &input_indices,
            &output_indices,
            &node_order,
            &node_biases,
            &incoming,
            &[0.3],
        );
        let hidden_val = (0.3 * 2.0 + 0.1_f32).tanh();
        let expected = (hidden_val * 0.5 - 0.2_f32).tanh();
        assert!((out[0] - expected).abs() < 1e-6);
    }

    #[test]
    fn test_no_connections() {
        // Output with no connections just applies tanh(bias)
        let input_indices = vec![0];
        let output_indices = vec![1];
        let node_order = vec![0, 1];
        let node_biases = vec![0.0, 0.5];
        let incoming = vec![vec![], vec![]];

        let out = forward_plain(
            &input_indices,
            &output_indices,
            &node_order,
            &node_biases,
            &incoming,
            &[1.0],
        );
        assert!((out[0] - 0.5_f32.tanh()).abs() < 1e-6);
    }
}
