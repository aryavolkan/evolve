use godot::prelude::*;

mod genetic_ops;
mod neat_genome;
mod neat_network;
mod neat_species;
mod neural_network;
mod nsga2;

struct EvolveNativeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EvolveNativeExtension {}
