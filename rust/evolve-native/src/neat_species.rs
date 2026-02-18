use godot::prelude::*;
use rand::seq::SliceRandom;
use rand::Rng;

use crate::neat_genome::neat_distance;

/// Fast NEAT speciation in Rust.
/// Groups genomes into species based on genetic distance.
#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct RustNeatSpecies {
    base: Base<RefCounted>,
}

/// Species data structure
struct Species {
    id: i32,
    representative: usize,       // Index into population
    members: Vec<usize>,         // Indices into population
    best_fitness: f32,
    stagnant_generations: i32,
}

#[godot_api]
impl RustNeatSpecies {
    /// Fast speciation algorithm. Groups population into species based on distance.
    /// Returns dictionary with "species" (Array) and "next_id" (int).
    #[func]
    fn speciate(
        &self,
        population: VarArray,
        existing_species: VarArray,
        config: VarDictionary,
        next_species_id: i32,
    ) -> VarDictionary {
        let compatibility_threshold: f32 = config.get_or_nil("compatibility_threshold").to();
        let pop_size = population.len();

        if pop_size == 0 {
            let mut result = VarDictionary::new();
            result.set("species", VarArray::new().to_variant());
            result.set("next_id", next_species_id.to_variant());
            return result;
        }

        // Extract existing species representatives
        let mut species_list: Vec<Species> = Vec::new();
        for i in 0..existing_species.len() {
            let species_dict: VarDictionary = existing_species.at(i).to();
            let id: i32 = species_dict.get_or_nil("id").to();
            let members: VarArray = species_dict.get_or_nil("members").to();

            if members.is_empty() {
                continue;
            }

            // Pick random representative from old members
            let repr_idx = rand::thread_rng().gen::<usize>() % members.len();
            let repr_genome_idx: i32 = members.at(repr_idx).to();

            species_list.push(Species {
                id,
                representative: repr_genome_idx as usize,
                members: Vec::new(),
                best_fitness: 0.0,
                stagnant_generations: species_dict.get_or_nil("stagnant_generations").to(),
            });
        }

        // Assign each genome to a species
        let mut genome_species: Vec<Option<usize>> = vec![None; pop_size];
        let mut unassigned: Vec<usize> = (0..pop_size).collect();

        // Shuffle for random assignment order
        unassigned.shuffle(&mut rand::thread_rng());

        for &genome_idx in &unassigned {
            let genome: VarDictionary = population.at(genome_idx).to();

            // Find compatible species
            let mut found_species = None;
            for (species_idx, species) in species_list.iter().enumerate() {
                let repr_genome: VarDictionary = population.at(species.representative).to();
                let distance = neat_distance(genome.clone(), repr_genome, config.clone());

                if distance < compatibility_threshold {
                    found_species = Some(species_idx);
                    break;
                }
            }

            if let Some(species_idx) = found_species {
                species_list[species_idx].members.push(genome_idx);
                genome_species[genome_idx] = Some(species_idx);
            }
        }

        // Create new species for unassigned genomes
        let mut new_id = next_species_id;
        for (genome_idx, &species_idx) in genome_species.iter().enumerate() {
            if species_idx.is_none() {
                species_list.push(Species {
                    id: new_id,
                    representative: genome_idx,
                    members: vec![genome_idx],
                    best_fitness: 0.0,
                    stagnant_generations: 0,
                });
                new_id += 1;
            }
        }

        // Update representatives to be the best member from current generation
        for species in &mut species_list {
            if !species.members.is_empty() {
                let mut best_idx = species.members[0];
                let mut best_fitness = {
                    let g: VarDictionary = population.at(best_idx).to();
                    let f: f32 = g.get_or_nil("fitness").to();
                    f
                };

                for &member_idx in &species.members[1..] {
                    let g: VarDictionary = population.at(member_idx).to();
                    let f: f32 = g.get_or_nil("fitness").to();
                    if f > best_fitness {
                        best_fitness = f;
                        best_idx = member_idx;
                    }
                }
                species.representative = best_idx;
                species.best_fitness = best_fitness;
            }
        }

        // Remove empty species
        species_list.retain(|s| !s.members.is_empty());

        // Convert back to Godot format
        let mut species_array = VarArray::new();
        for species in species_list {
            let mut species_dict = VarDictionary::new();
            species_dict.set("id", species.id.to_variant());

            let mut members_array = VarArray::new();
            for &idx in &species.members {
                members_array.push(&(idx as i32).to_variant());
            }
            species_dict.set("members", members_array.to_variant());
            species_dict.set("representative", (species.representative as i32).to_variant());
            species_dict.set("best_fitness", species.best_fitness.to_variant());
            species_dict.set("stagnant_generations", species.stagnant_generations.to_variant());

            species_array.push(&species_dict.to_variant());
        }

        let mut result = VarDictionary::new();
        result.set("species", species_array.to_variant());
        result.set("next_id", new_id.to_variant());
        result
    }

    /// Calculate adjusted fitness for all members of a species.
    /// Applies fitness sharing to promote diversity.
    #[func]
    fn calculate_adjusted_fitness(&self, mut species_dict: VarDictionary, population: VarArray) {
        let members: VarArray = species_dict.get_or_nil("members").to();
        let size = members.len() as f32;

        if size == 0.0 {
            return;
        }

        let mut total_adjusted = 0.0f32;

        for i in 0..members.len() {
            let member_idx: i32 = members.at(i).to();
            let mut genome: VarDictionary = population.at(member_idx as usize).to();
            let fitness: f32 = genome.get_or_nil("fitness").to();

            let adjusted = fitness / size;
            genome.set("adjusted_fitness", adjusted.to_variant());
            total_adjusted += adjusted;
        }

        species_dict.set("total_adjusted_fitness", total_adjusted.to_variant());
    }
}
