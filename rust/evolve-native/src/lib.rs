use godot::prelude::*;

mod neural_network;
mod neat_network;
mod nsga2;
mod genetic_ops;

struct EvolveNativeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EvolveNativeExtension {}
