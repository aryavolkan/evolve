use godot::prelude::*;

/// Rust port of NSGA-II non-dominated sorting from `ai/nsga2.gd`.
///
/// Accepts an Array of Vector3 objectives and returns fronts as Array of PackedInt32Array.
/// O(MN²) pairwise comparisons — same algorithm, ~5-10x faster in Rust.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RustNsga2 {
    base: Base<RefCounted>,
}

#[inline]
fn dominates(a: &[f32; 3], b: &[f32; 3]) -> bool {
    // a dominates b iff a >= b on all objectives AND a > b on at least one
    a[0] >= b[0] && a[1] >= b[1] && a[2] >= b[2] && (a[0] > b[0] || a[1] > b[1] || a[2] > b[2])
}

#[godot_api]
impl RustNsga2 {
    /// Perform fast non-dominated sorting.
    /// Input: Array of Vector3 (one per individual, 3 objectives)
    /// Output: Array of PackedInt32Array — each is a front of individual indices.
    #[func]
    fn non_dominated_sort(objectives: VarArray) -> VarArray {
        let n = objectives.len();
        if n == 0 {
            return VarArray::new();
        }

        // Extract objectives into flat Vec for cache-friendly access
        let mut objs: Vec<[f32; 3]> = Vec::with_capacity(n);
        for i in 0..n {
            let v: Vector3 = objectives.at(i).to();
            objs.push([v.x, v.y, v.z]);
        }

        let mut domination_count = vec![0i32; n];
        let mut dominated_set: Vec<Vec<i32>> = vec![Vec::new(); n];

        // Pairwise comparison
        for i in 0..n {
            for j in (i + 1)..n {
                if dominates(&objs[i], &objs[j]) {
                    dominated_set[i].push(j as i32);
                    domination_count[j] += 1;
                } else if dominates(&objs[j], &objs[i]) {
                    dominated_set[j].push(i as i32);
                    domination_count[i] += 1;
                }
            }
        }

        // Build fronts
        let mut fronts = VarArray::new();
        let mut current_front: Vec<i32> = Vec::new();

        for (i, &count) in domination_count.iter().enumerate().take(n) {
            if count == 0 {
                current_front.push(i as i32);
            }
        }

        while !current_front.is_empty() {
            let packed = PackedInt32Array::from(current_front.as_slice());
            fronts.push(&packed.to_variant());

            let mut next_front: Vec<i32> = Vec::new();
            for &i in &current_front {
                for &j in &dominated_set[i as usize] {
                    domination_count[j as usize] -= 1;
                    if domination_count[j as usize] == 0 {
                        next_front.push(j);
                    }
                }
            }
            current_front = next_front;
        }

        fronts
    }

    /// Build a flat rank lookup: individual index → front rank.
    /// Call once after non_dominated_sort, then use for O(1) rank lookups.
    #[func]
    fn build_rank_map(fronts: VarArray, pop_size: i32) -> PackedInt32Array {
        let n = pop_size as usize;
        let mut ranks = PackedInt32Array::new();
        ranks.resize(n);
        let default_rank = fronts.len() as i32;
        let ranks_slice = ranks.as_mut_slice();
        for r in ranks_slice.iter_mut() {
            *r = default_rank;
        }

        for rank in 0..fronts.len() {
            let front: PackedInt32Array = fronts.at(rank).to();
            for idx in front.as_slice() {
                let i = *idx as usize;
                if i < n {
                    ranks_slice[i] = rank as i32;
                }
            }
        }
        ranks
    }

    /// Crowding distance calculation for a single front.
    /// Input: objectives (Array of Vector3), front (PackedInt32Array of indices)
    /// Output: Dictionary {index: crowding_distance}
    #[func]
    fn crowding_distance(objectives: VarArray, front: PackedInt32Array) -> VarDictionary {
        let indices = front.as_slice();
        let n = indices.len();
        let mut result = VarDictionary::new();

        if n <= 2 {
            for &idx in indices {
                result.set(idx, f64::INFINITY);
            }
            return result;
        }

        // Extract objectives for front members
        let mut objs: Vec<(i32, [f32; 3])> = Vec::with_capacity(n);
        for &idx in indices {
            let v: Vector3 = objectives.at(idx as usize).to();
            objs.push((idx, [v.x, v.y, v.z]));
        }

        let mut distances = vec![0.0f64; n];

        // For each objective dimension
        for m in 0..3 {
            // Sort by this objective
            let mut sorted_indices: Vec<usize> = (0..n).collect();
            sorted_indices.sort_by(|&a, &b| {
                objs[a].1[m]
                    .partial_cmp(&objs[b].1[m])
                    .unwrap_or(std::cmp::Ordering::Equal)
            });

            // Boundary points get infinity
            distances[sorted_indices[0]] = f64::INFINITY;
            distances[sorted_indices[n - 1]] = f64::INFINITY;

            let obj_min = objs[sorted_indices[0]].1[m];
            let obj_max = objs[sorted_indices[n - 1]].1[m];
            let range = obj_max - obj_min;

            if range > 0.0 {
                for i in 1..(n - 1) {
                    let prev = sorted_indices[i - 1];
                    let next = sorted_indices[i + 1];
                    distances[sorted_indices[i]] += ((objs[next].1[m] - objs[prev].1[m]) / range) as f64;
                }
            }
        }

        for (i, &idx) in indices.iter().enumerate() {
            result.set(idx, distances[i]);
        }
        result
    }

    /// Binary tournament selection using NSGA-II crowded comparison.
    /// rank_map: from build_rank_map, crowding: from crowding_distance
    #[func]
    fn tournament_select(pop_size: i32, rank_map: PackedInt32Array, crowding: VarDictionary) -> i32 {
        let n = pop_size as usize;
        if n == 0 {
            return 0;
        }

        // Use simple random (Godot's randi isn't easily accessible, use a basic approach)
        let a = fastrand_usize(n);
        let mut b = fastrand_usize(n);
        while b == a && n > 1 {
            b = fastrand_usize(n);
        }

        let ranks = rank_map.as_slice();
        let rank_a = if a < ranks.len() { ranks[a] } else { i32::MAX };
        let rank_b = if b < ranks.len() { ranks[b] } else { i32::MAX };

        if rank_a < rank_b {
            return a as i32;
        }
        if rank_b < rank_a {
            return b as i32;
        }

        // Same rank — prefer higher crowding distance
        let cd_a: f64 = crowding.get_or_nil(a as i32).to();
        let cd_b: f64 = crowding.get_or_nil(b as i32).to();

        if cd_a >= cd_b {
            a as i32
        } else {
            b as i32
        }
    }
}

/// Simple fast pseudo-random using thread-local state
fn fastrand_usize(max: usize) -> usize {
    use std::cell::Cell;
    thread_local! {
        static STATE: Cell<u64> = const { Cell::new(0x12345678_9abcdef0) };
    }
    STATE.with(|s| {
        let mut x = s.get();
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        s.set(x);
        (x as usize) % max
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dominates() {
        assert!(dominates(&[3.0, 2.0, 1.0], &[2.0, 2.0, 1.0]));
        assert!(dominates(&[3.0, 3.0, 3.0], &[1.0, 1.0, 1.0]));
        assert!(!dominates(&[1.0, 2.0, 3.0], &[3.0, 2.0, 1.0])); // trade-off
        assert!(!dominates(&[1.0, 1.0, 1.0], &[1.0, 1.0, 1.0])); // equal
        assert!(!dominates(&[1.0, 2.0, 1.0], &[2.0, 1.0, 1.0])); // trade-off
    }

    #[test]
    fn test_non_dominated_sort_logic() {
        // Test the pure dominance logic without Godot types
        let objs = vec![
            [3.0, 3.0, 3.0], // 0: dominates all
            [1.0, 1.0, 1.0], // 1: dominated by 0
            [2.0, 0.5, 2.0], // 2: trade-off with 1
            [0.5, 0.5, 0.5], // 3: dominated by 0, 1, 2
        ];
        let n = objs.len();
        let mut domination_count = vec![0i32; n];
        let mut dominated_set: Vec<Vec<usize>> = vec![Vec::new(); n];

        for i in 0..n {
            for j in (i + 1)..n {
                if dominates(&objs[i], &objs[j]) {
                    dominated_set[i].push(j);
                    domination_count[j] += 1;
                } else if dominates(&objs[j], &objs[i]) {
                    dominated_set[j].push(i);
                    domination_count[i] += 1;
                }
            }
        }

        // Front 0: individual 0 (dominates all)
        assert_eq!(domination_count[0], 0);
        // Individual 3 dominated by multiple
        assert!(domination_count[3] > 0);

        // Build fronts
        let mut fronts: Vec<Vec<usize>> = Vec::new();
        let mut current: Vec<usize> = (0..n).filter(|&i| domination_count[i] == 0).collect();

        while !current.is_empty() {
            fronts.push(current.clone());
            let mut next = Vec::new();
            for &i in &current {
                for &j in &dominated_set[i] {
                    domination_count[j] -= 1;
                    if domination_count[j] == 0 {
                        next.push(j);
                    }
                }
            }
            current = next;
        }

        assert_eq!(fronts[0], vec![0]); // Pareto front
        assert!(fronts.len() >= 2);
    }
}
