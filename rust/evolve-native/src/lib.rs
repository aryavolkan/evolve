use godot::prelude::*;

mod neural_network;
mod neat_network;
mod nsga2;

struct EvolveNativeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for EvolveNativeExtension {}
