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
    a[0] >= b[0] && a[1] >= b[1] && a[2] >= b[2]
        && (a[0] > b[0] || a[1] > b[1] || a[2] > b[2])
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

        for i in 0..n {
            if domination_count[i] == 0 {
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
