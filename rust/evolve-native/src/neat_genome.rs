use godot::prelude::*;
use rand::Rng;
use rand_distr::{Distribution, Normal};
use std::collections::{HashMap, HashSet};

/// Fast NEAT genome operations in Rust.
/// Provides mutation, crossover, and distance calculations for NEAT genomes.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RustNeatGenome {
    base: Base<RefCounted>,
}

/// Connection gene representation (innovation tracked as HashMap key; only weight needed here)
#[derive(Clone, Copy, Debug)]
struct ConnectionGene {
    weight: f32,
}

/// Node gene representation (reserved for future structural mutations)
#[allow(dead_code)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct NodeGene {
    id: i32,
    node_type: i32, // 0=input, 1=hidden, 2=output
}

#[allow(dead_code)]
const NODE_INPUT: i32 = 0;
#[allow(dead_code)]
const NODE_HIDDEN: i32 = 1;
#[allow(dead_code)]
const NODE_OUTPUT: i32 = 2;

/// Free function for internal use (e.g. from neat_species.rs).
pub fn neat_distance(genome_a: VarDictionary, genome_b: VarDictionary, config: VarDictionary) -> f32 {
    let c1: f32 = config.get_or_nil("compatibility_excess_coeff").to();
    let c2: f32 = config.get_or_nil("compatibility_disjoint_coeff").to();
    let c3: f32 = config.get_or_nil("compatibility_weight_coeff").to();

    let conns_a: VarArray = genome_a.get_or_nil("connections").to();
    let conns_b: VarArray = genome_b.get_or_nil("connections").to();

    if conns_a.is_empty() && conns_b.is_empty() {
        return 0.0;
    }

    let mut innov_a: HashMap<i32, ConnectionGene> = HashMap::new();
    let mut innov_b: HashMap<i32, ConnectionGene> = HashMap::new();
    let mut max_innov_a = 0i32;
    let mut max_innov_b = 0i32;

    for i in 0..conns_a.len() {
        let conn: VarDictionary = conns_a.at(i).to();
        let innovation: i32 = conn.get_or_nil("innovation").to();
        let gene = ConnectionGene {
            weight: conn.get_or_nil("weight").to(),
        };
        innov_a.insert(innovation, gene);
        max_innov_a = max_innov_a.max(innovation);
    }

    for i in 0..conns_b.len() {
        let conn: VarDictionary = conns_b.at(i).to();
        let innovation: i32 = conn.get_or_nil("innovation").to();
        let gene = ConnectionGene {
            weight: conn.get_or_nil("weight").to(),
        };
        innov_b.insert(innovation, gene);
        max_innov_b = max_innov_b.max(innovation);
    }

    let all_innovations: HashSet<i32> = innov_a.keys().chain(innov_b.keys()).cloned().collect();

    let mut excess = 0;
    let mut disjoint = 0;
    let mut weight_diff = 0.0;
    let mut matching = 0;

    for &innov in &all_innovations {
        match (innov_a.get(&innov), innov_b.get(&innov)) {
            (Some(a), Some(b)) => {
                matching += 1;
                weight_diff += (a.weight - b.weight).abs();
            }
            (Some(_), None) | (None, Some(_)) => {
                if innov > max_innov_a.min(max_innov_b) {
                    excess += 1;
                } else {
                    disjoint += 1;
                }
            }
            _ => {}
        }
    }

    let weight_avg = if matching > 0 { weight_diff / matching as f32 } else { 0.0 };
    let n = conns_a.len().max(conns_b.len()).max(1) as f32;
    let normalize = n > 20.0;

    if normalize {
        c1 * excess as f32 / n + c2 * disjoint as f32 / n + c3 * weight_avg
    } else {
        c1 * excess as f32 + c2 * disjoint as f32 + c3 * weight_avg
    }
}

#[godot_api]
impl RustNeatGenome {
    /// Fast NEAT distance calculation using coefficient-weighted differences.
    /// Compatible with the GDScript implementation but ~10x faster.
    #[func]
    fn distance(&self, genome_a: VarDictionary, genome_b: VarDictionary, config: VarDictionary) -> f32 {
        neat_distance(genome_a, genome_b, config)
    }

    /// Fast NEAT crossover producing a child genome.
    /// Parent fitness determines which parent's genes are preferred.
    #[func]
    fn crossover(&self, parent_a: VarDictionary, parent_b: VarDictionary) -> VarDictionary {
        let fitness_a: f32 = parent_a.get_or_nil("fitness").to();
        let fitness_b: f32 = parent_b.get_or_nil("fitness").to();

        let (fitter, less_fit) = if fitness_a >= fitness_b {
            (parent_a.clone(), parent_b)
        } else {
            (parent_b, parent_a.clone())
        };

        let conns_fitter: VarArray = fitter.get_or_nil("connections").to();
        let conns_less: VarArray = less_fit.get_or_nil("connections").to();

        let mut innov_less: HashMap<i32, VarDictionary> = HashMap::new();
        for i in 0..conns_less.len() {
            let conn: VarDictionary = conns_less.at(i).to();
            let innovation: i32 = conn.get_or_nil("innovation").to();
            innov_less.insert(innovation, conn);
        }

        let mut child_connections = VarArray::new();
        let mut rng = rand::thread_rng();

        for i in 0..conns_fitter.len() {
            let conn_fit: VarDictionary = conns_fitter.at(i).to();
            let innovation: i32 = conn_fit.get_or_nil("innovation").to();

            let child_conn = if let Some(conn_less) = innov_less.get(&innovation) {
                if rng.gen_bool(0.5) { conn_fit.clone() } else { conn_less.clone() }
            } else {
                conn_fit.clone()
            };

            child_connections.push(&child_conn.to_variant());
        }

        let mut child = VarDictionary::new();
        child.set("connections", child_connections.to_variant());
        child.set("nodes", fitter.get_or_nil("nodes"));
        child.set("input_count", fitter.get_or_nil("input_count"));
        child.set("output_count", fitter.get_or_nil("output_count"));
        child.set("fitness", 0.0f32.to_variant());

        child
    }

    /// Fast mutation operations on a NEAT genome.
    /// Modifies the genome in-place for efficiency.
    #[func]
    fn mutate(&self, genome: VarDictionary, config: VarDictionary) {
        let mutation_rate: f32 = config.get_or_nil("mutation_rate").to();
        let weight_mutation_rate: f32 = config.get_or_nil("weight_mutation_rate").to();
        let weight_mutation_strength: f32 = config.get_or_nil("weight_mutation_strength").to();
        let weight_replace_rate: f32 = config.get_or_nil("weight_replace_rate").to();
        let conn_add_rate: f32 = config.get_or_nil("conn_add_rate").to();
        let conn_delete_rate: f32 = config.get_or_nil("conn_delete_rate").to();
        let conn_enable_rate: f32 = config.get_or_nil("conn_enable_rate").to();
        let conn_disable_rate: f32 = config.get_or_nil("conn_disable_rate").to();
        let node_add_rate: f32 = config.get_or_nil("node_add_rate").to();

        let mut rng = rand::thread_rng();

        if rng.gen::<f32>() >= mutation_rate {
            return;
        }

        let mut connections: VarArray = genome.get_or_nil("connections").to();

        // Weight mutations
        if rng.gen::<f32>() < weight_mutation_rate {
            for i in 0..connections.len() {
                let mut conn: VarDictionary = connections.at(i).to();
                let weight: f32 = conn.get_or_nil("weight").to();

                let new_weight = if rng.gen::<f32>() < weight_replace_rate {
                    rng.gen_range(-2.0..2.0)
                } else {
                    let normal = Normal::new(0.0, weight_mutation_strength).unwrap();
                    (weight + normal.sample(&mut rng)).clamp(-2.0, 2.0)
                };

                conn.set("weight", new_weight.to_variant());
            }
        }

        // Enable/disable mutations
        if !connections.is_empty() {
            if rng.gen::<f32>() < conn_enable_rate {
                let disabled_indices: Vec<usize> = (0..connections.len())
                    .filter(|&i| {
                        let conn: VarDictionary = connections.at(i).to();
                        let enabled: bool = conn.get_or_nil("enabled").to();
                        !enabled
                    })
                    .collect();

                if !disabled_indices.is_empty() {
                    let idx = disabled_indices[rng.gen_range(0..disabled_indices.len())];
                    let mut conn: VarDictionary = connections.at(idx).to();
                    conn.set("enabled", true.to_variant());
                }
            }

            if rng.gen::<f32>() < conn_disable_rate && connections.len() > 1 {
                let enabled_indices: Vec<usize> = (0..connections.len())
                    .filter(|&i| {
                        let conn: VarDictionary = connections.at(i).to();
                        let enabled: bool = conn.get_or_nil("enabled").to();
                        enabled
                    })
                    .collect();

                if !enabled_indices.is_empty() {
                    let idx = enabled_indices[rng.gen_range(0..enabled_indices.len())];
                    let mut conn: VarDictionary = connections.at(idx).to();
                    conn.set("enabled", false.to_variant());
                }
            }
        }

        // Connection deletion
        if rng.gen::<f32>() < conn_delete_rate && connections.len() > 1 {
            let idx = rng.gen_range(0..connections.len());
            connections.remove(idx);
        }

        // Note: add_node and add_connection mutations require innovation tracking
        // from the evolution system — handled at the GDScript layer for now.
        let _ = (conn_add_rate, node_add_rate); // suppress unused warnings
    }
}
