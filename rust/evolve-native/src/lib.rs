use godot::prelude::*;

mod genetic_ops;
mod neat_network;
mod neural_network;
mod nsga2;

struct EvolveNativeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EvolveNativeExtension {}
