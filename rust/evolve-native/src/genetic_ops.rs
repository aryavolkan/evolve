use godot::prelude::*;
use rand::Rng;
use rand_distr::{Distribution, Normal};

/// Rust implementations of genetic operations for performance.
/// Tournament selection, crossover, mutation - operations that run frequently during evolution.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RustGeneticOps {
    base: Base<RefCounted>,
}

#[godot_api]
impl RustGeneticOps {
    /// Fast tournament selection. Returns index of winner.
    /// indexed_fitness: Array of dictionaries with "index" and "fitness" keys
    /// tournament_size: Number of individuals to compete (default 3)
    #[func]
    fn tournament_select(indexed_fitness: VarArray, tournament_size: i32) -> i32 {
        let n = indexed_fitness.len();
        if n == 0 {
            return -1;
        }

        let t_size = tournament_size.max(2).min(n as i32) as usize;
        let mut rng = rand::thread_rng();
        
        let mut best_idx = -1;
        let mut best_fitness = f32::NEG_INFINITY;
        
        // Select tournament participants
        for _ in 0..t_size {
            let rand_idx = rng.gen_range(0..n);
            let entry: VarDictionary = indexed_fitness.at(rand_idx).to();
            let idx: i32 = entry.get_or_nil("index").to();
            let fitness: f32 = entry.get_or_nil("fitness").to();
            
            if fitness > best_fitness {
                best_fitness = fitness;
                best_idx = idx;
            }
        }
        
        best_idx
    }

    /// Batch tournament selection. Returns array of selected indices.
    /// More efficient than calling tournament_select multiple times.
    #[func]
    fn batch_tournament_select(indexed_fitness: VarArray, count: i32, tournament_size: i32) -> PackedInt32Array {
        let n = indexed_fitness.len();
        if n == 0 || count <= 0 {
            return PackedInt32Array::new();
        }

        // Pre-extract fitness values for faster access
        let mut fitness_vec: Vec<(i32, f32)> = Vec::with_capacity(n);
        for i in 0..n {
            let entry: VarDictionary = indexed_fitness.at(i).to();
            let idx: i32 = entry.get_or_nil("index").to();
            let fitness: f32 = entry.get_or_nil("fitness").to();
            fitness_vec.push((idx, fitness));
        }

        let t_size = tournament_size.max(2).min(n as i32) as usize;
        let mut rng = rand::thread_rng();
        let mut results = Vec::with_capacity(count as usize);

        for _ in 0..count {
            let mut best_idx = -1;
            let mut best_fitness = f32::NEG_INFINITY;
            
            for _ in 0..t_size {
                let rand_idx = rng.gen_range(0..n);
                let (idx, fitness) = fitness_vec[rand_idx];
                
                if fitness > best_fitness {
                    best_fitness = fitness;
                    best_idx = idx;
                }
            }
            
            results.push(best_idx);
        }

        PackedInt32Array::from(results.as_slice())
    }

    /// Efficient weight crossover for neural networks.
    /// Uses two-point crossover to preserve weight patterns.
    #[func]
    fn crossover_weights(weights_a: PackedFloat32Array, weights_b: PackedFloat32Array) -> PackedFloat32Array {
        let a = weights_a.as_slice();
        let b = weights_b.as_slice();
        let len = a.len().min(b.len());
        
        if len == 0 {
            return PackedFloat32Array::new();
        }

        let mut rng = rand::thread_rng();
        let mut point1 = rng.gen_range(0..len);
        let mut point2 = rng.gen_range(0..len);
        
        if point1 > point2 {
            std::mem::swap(&mut point1, &mut point2);
        }

        let mut child = Vec::with_capacity(len);
        
        // Three segments: [0..point1] from A, [point1..point2] from B, [point2..len] from A
        child.extend_from_slice(&a[..point1]);
        child.extend_from_slice(&b[point1..point2]);
        child.extend_from_slice(&a[point2..]);

        PackedFloat32Array::from(child.as_slice())
    }

    /// Batch crossover - create multiple offspring at once.
    /// More cache-efficient than repeated single crossovers.
    #[func]
    fn batch_crossover(weights_a: PackedFloat32Array, weights_b: PackedFloat32Array, count: i32) -> VarArray {
        let a = weights_a.as_slice();
        let b = weights_b.as_slice();
        let len = a.len().min(b.len());
        
        if len == 0 || count <= 0 {
            return VarArray::new();
        }

        let mut rng = rand::thread_rng();
        let mut results = VarArray::new();

        for _ in 0..count {
            let mut point1 = rng.gen_range(0..len);
            let mut point2 = rng.gen_range(0..len);
            
            if point1 > point2 {
                std::mem::swap(&mut point1, &mut point2);
            }

            let mut child = Vec::with_capacity(len);
            child.extend_from_slice(&a[..point1]);
            child.extend_from_slice(&b[point1..point2]);
            child.extend_from_slice(&a[point2..]);

            results.push(&PackedFloat32Array::from(child.as_slice()).to_variant());
        }

        results
    }

    /// Fast Gaussian mutation of weight arrays.
    /// Mutates in-place and returns the same array.
    #[func]
    fn mutate_weights(mut weights: PackedFloat32Array, mutation_rate: f64, mutation_strength: f64) -> PackedFloat32Array {
        let mut rng = rand::thread_rng();
        let normal = Normal::new(0.0, mutation_strength).unwrap();
        
        let w_slice = weights.as_mut_slice();
        for w in w_slice.iter_mut() {
            if rng.gen::<f64>() < mutation_rate {
                *w += normal.sample(&mut rng) as f32;
            }
        }
        
        weights
    }

    /// Batch fitness calculation for sorting.
    /// Takes objectives (Array of Vector3) and returns scalar fitnesses.
    #[func]
    fn calculate_fitnesses(objectives: VarArray) -> PackedFloat32Array {
        let n = objectives.len();
        let mut fitnesses = Vec::with_capacity(n);
        
        for i in 0..n {
            let obj: Vector3 = objectives.at(i).to();
            // Simple sum of objectives
            fitnesses.push(obj.x + obj.y + obj.z);
        }
        
        PackedFloat32Array::from(fitnesses.as_slice())
    }
    
    /// Fast batch update of fitness scores with delta values.
    /// Updates multiple individuals' fitness in one call.
    #[func]
    fn batch_update_fitness(mut current_fitness: PackedFloat32Array, indices: PackedInt32Array, delta: f32) -> PackedFloat32Array {
        let fitness_slice = current_fitness.as_mut_slice();
        let idx_slice = indices.as_slice();
        
        for &idx in idx_slice {
            if (idx as usize) < fitness_slice.len() {
                fitness_slice[idx as usize] += delta;
            }
        }
        
        current_fitness
    }

    /// Fast sorting of indexed fitness array.
    /// Returns sorted indices (highest fitness first).
    #[func]
    fn sort_by_fitness(indexed_fitness: VarArray) -> PackedInt32Array {
        let n = indexed_fitness.len();
        let mut items: Vec<(i32, f32)> = Vec::with_capacity(n);
        
        for i in 0..n {
            let entry: VarDictionary = indexed_fitness.at(i).to();
            let idx: i32 = entry.get_or_nil("index").to();
            let fitness: f32 = entry.get_or_nil("fitness").to();
            items.push((idx, fitness));
        }
        
        // Sort by fitness descending
        items.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        
        let indices: Vec<i32> = items.into_iter().map(|(idx, _)| idx).collect();
        PackedInt32Array::from(indices.as_slice())
    }

    /// Argsort a PackedFloat32Array — returns indices sorted descending by fitness.
    /// ~5x faster than sort_by_fitness because it avoids VarArray/Dict overhead.
    /// Pass fitness_scores directly from EvolutionBase.
    #[func]
    fn argsort_fitness(fitness: PackedFloat32Array) -> PackedInt32Array {
        let f = fitness.as_slice();
        let n = f.len();
        let mut indices: Vec<i32> = (0..n as i32).collect();
        // Unstable sort is fine for evolution — same quality, slightly faster
        indices.sort_unstable_by(|&a, &b| {
            f[b as usize].partial_cmp(&f[a as usize])
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        PackedInt32Array::from(indices.as_slice())
    }

    /// Tournament selection directly on a PackedFloat32Array of fitness values.
    /// Avoids all VarArray/Dict creation — ~4x faster than batch_tournament_select.
    /// Returns `count` selected parent indices.
    #[func]
    fn batch_tournament_select_packed(fitness: PackedFloat32Array, count: i32, tournament_size: i32) -> PackedInt32Array {
        let f = fitness.as_slice();
        let n = f.len();
        if n == 0 || count <= 0 {
            return PackedInt32Array::new();
        }

        let t_size = tournament_size.max(2).min(n as i32) as usize;
        let mut rng = rand::thread_rng();
        let mut results = Vec::with_capacity(count as usize);

        for _ in 0..count {
            let mut best_idx = 0usize;
            let mut best_fit = f32::NEG_INFINITY;

            for _ in 0..t_size {
                let rand_idx = rng.gen_range(0..n);
                let fit = unsafe { *f.get_unchecked(rand_idx) };
                if fit > best_fit {
                    best_fit = fit;
                    best_idx = rand_idx;
                }
            }
            results.push(best_idx as i32);
        }

        PackedInt32Array::from(results.as_slice())
    }

    /// Compute sum, min, max over a fitness array in a single pass.
    /// Returns [sum, min, max] as Vector3 — avoids 3 separate GDScript loops.
    #[func]
    fn fitness_stats(fitness: PackedFloat32Array) -> Vector3 {
        let f = fitness.as_slice();
        if f.is_empty() {
            return Vector3::ZERO;
        }
        let mut total = 0.0f64;
        let mut min_f = f32::INFINITY;
        let mut max_f = f32::NEG_INFINITY;
        for &v in f {
            total += v as f64;
            if v < min_f { min_f = v; }
            if v > max_f { max_f = v; }
        }
        Vector3::new(total as f32, min_f, max_f)
    }
}