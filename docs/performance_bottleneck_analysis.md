# Performance Bottleneck Analysis — Evolve Training Pipeline

**Date:** 2026-02-15  
**Hardware:** Apple M3 Max (macOS)  
**Config:** 20 parallel arenas, population 150, 2 evals/individual, 16× time scale  
**Goal:** Maximize generations/hour for overnight evolution runs

---

## Executive Summary

After profiling all hot paths in the training loop, I identified **5 major bottlenecks** ordered by estimated per-frame cost. The single biggest win is **integrating the Rust neural network** into the actual training pipeline (it exists but is only used in benchmarks). Combined, the proposed optimizations could yield a **2-3× overall training throughput increase**.

---

## Per-Frame Cost Model (20 arenas, ~50 FPS)

Budget: **20ms per frame** at 50 FPS.

| Component | Per-Arena Cost | × 20 Arenas | % of Frame | Notes |
|-----------|---------------|-------------|------------|-------|
| **Sensor system** (`get_inputs()`) | ~0.35ms | **7.0ms** | **35%** | 16 rays × entity iteration + cache build |
| **Neural network forward** | ~0.15ms | **3.0ms** | **15%** | 86→80→6 in GDScript (measured ~150µs) |
| **Physics (move_and_slide)** | ~0.15ms | **3.0ms** | **15%** | Player + enemies + projectiles |
| **Enemy AI** (`calculate_next_move` + `find_nearest_target`) | ~0.10ms | **2.0ms** | **10%** | Per-enemy tree walk every move cycle |
| **Rendering (SubViewport)** | ~0.20ms | **4.0ms** | **20%** | 1280×720 per viewport |
| **Scene management** (spawns, signals, GC) | ~0.05ms | **1.0ms** | **5%** | Instantiation, queue_free, signals |
| **Total estimated** | | **~20ms** | 100% | |

---

## Bottleneck #1: Sensor System — `get_inputs()` (~35% of frame)

### What's happening
Every frame, each of the 20 AI agents calls `sensor.get_inputs()` which:
1. Rebuilds the entity cache once per frame (`_build_cache`) — **4 `get_nodes_in_group()` calls** + O(entities) partitioning
2. Casts **16 rays**, each iterating over **all enemies, obstacles, and powerups** in the arena
3. Computes 80 ray values + 6 player state values = **86 inputs**

### The hot loop
```gdscript
# For each of 16 rays:
for entity in entities:           # Could be 10-40 enemies
    var to_entity = entity.global_position - origin
    var projection = to_entity.dot(direction)
    # ... distance checks, type classification
```

With ~20 enemies per arena: **16 rays × 20 enemies × 20 arenas = 6,400 distance computations per frame** — all in GDScript.

### Cache efficiency
The static `_build_cache` is well-designed (once per frame, shared across all sensors). But the **per-ray entity iteration** is the bottleneck, not the cache build.

### Optimization opportunities

**O1: Spatial partitioning for ray casting (Medium effort, ~30% sensor speedup)**
- Use a simple grid/sector lookup instead of iterating all entities per ray
- Divide arena into 8×8 sectors, only check entities in sectors the ray passes through
- Reduces entity checks from O(rays × entities) to O(rays × entities_in_sector)

**O2: Move sensor system to Rust (High effort, ~5-10× sensor speedup)**
- Port `cast_ray_to_entities()` and `get_wall_distance()` to Rust GDExtension
- The 86-value computation becomes a single Rust function call
- This is the highest-ROI Rust migration target after neural networks

**O3: Reduce ray count in training mode (Low effort, ~50% sensor speedup)**
- 16 rays is very high for training. 8 rays works well for most neuroevolution
- Halves sensor computation AND neural network size (input drops from 86 to 46)
- Would need retraining from scratch (not backward-compatible with saved networks)

---

## Bottleneck #2: Neural Network Forward Pass — GDScript (~15% of frame)

### What's happening
The GDScript `forward()` is a double nested loop:
```gdscript
for h in hidden_size:           # 80 iterations
    for i in input_size:        # 86 iterations
        sum += weights_ih[offset + i] * inputs[i]
```
That's **86 × 80 = 6,880** multiply-accumulates for the input→hidden layer alone, plus **80 × 6 = 480** for hidden→output. Total: **~7,360 FP multiply-add operations per forward pass in GDScript**.

### Current state
The Rust `RustNeuralNetwork` exists and benchmarks show **5-15× speedup**, but **it is NOT integrated into the training pipeline**. It's only used in `scripts/benchmark_rust.gd`. The `evolution.gd` still creates GDScript `NeuralNetwork` instances.

### The fix
**O4: Wire RustNeuralNetwork into evolution.gd (Medium effort, ~12% total frame time reduction)**
- Modify `evolution.gd` to create `RustNeuralNetwork` instances instead of `NeuralNetwork`
- API is already compatible (`forward()`, `get_weights()`, `set_weights()`, `mutate()`, `crossover_with()`, `clone_network()`)
- The `clone()` → `clone_network()` name difference needs handling
- Save/load format is compatible

**Estimated impact:** At 150µs/forward → ~15µs/forward per arena = **2.7ms saved per frame** across 20 arenas.

---

## Bottleneck #3: Enemy `find_nearest_target()` — Tree Walk (~10% of frame)

### What's happening
Every enemy calls `find_nearest_target()` when:
1. First spawned (`_ready()`)
2. Every move cycle (`calculate_next_move()`, ~1-2 times per second per enemy)
3. Every physics frame for backup collision check (bottom of `_physics_process`)

The function walks **up the scene tree** to find "Main", then iterates **all children** checking group membership:
```gdscript
func find_nearest_target() -> CharacterBody2D:
    var current = get_parent()
    while current:          # Walk up tree
        if current.name == "Main":
            main_node = current
            break
        current = current.get_parent()
    for child in main_node.get_children():    # Iterate ALL children
        if child is CharacterBody2D and child.is_in_group("player"):
```

With 20+ enemies per arena × 20 arenas = **400+ enemies** doing this, and Main could have 50+ children (obstacles, enemies, powerups).

### Optimization
**O5: Cache player reference per-arena (Low effort, ~8% enemy cost reduction)**
- Each arena has exactly one player. Cache it after first lookup.
- Only re-lookup if player becomes invalid (death/respawn).
- The backup collision check at the bottom of `_physics_process` calls `find_nearest_target()` **every single frame** — this is the biggest cost.

**O6: Remove per-frame `find_nearest_target` from collision backup check (Low effort, ~50% enemy cost reduction)**
```gdscript
# Current: calls find_nearest_target() EVERY frame
var nearest = find_nearest_target()
if nearest and is_instance_valid(nearest):
    ...distance check...
```
Instead, just use the cached `player` variable that's already set.

---

## Bottleneck #4: SubViewport Rendering (~20% of frame in GUI mode)

### What's happening
Each of 20 arenas renders into a 1280×720 SubViewport, which is **massive** for training. The rendering includes:
- Sprite rendering (player, enemies, obstacles, projectiles, powerups)
- Death effects (particle-like animations)
- UI elements (score labels)

### Current headless behavior
The arena_pool sets `viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS`. In `--headless` mode, Godot's rendering backend is a no-op, so this is free. **But in GUI training mode, this eats 20% of frame time.**

### Optimization
**O7: Reduce SubViewport resolution for GUI training (Low effort, ~50% rendering cost)**
- Change from 1280×720 to 640×360 per arena
- At 5×4 grid, each viewport already renders tiny on screen — no visible quality loss
- `viewport.size = Vector2(640, 360)` — one-line change in `arena_pool.gd`

**O8: Use UPDATE_WHEN_VISIBLE for non-focused arenas (Low effort, ~30% rendering cost)**
- Only the fullscreen arena needs `UPDATE_ALWAYS`
- Grid view: render at reduced frequency
- `viewport.render_target_update_mode = SubViewport.UPDATE_ONCE` then trigger manually

---

## Bottleneck #5: Scene Instantiation & Cleanup (~5% of frame, spiky)

### What's happening
When an individual finishes evaluation, `_replace_eval_instance()` is called which:
1. Creates a new `SubViewportContainer` + `SubViewport`
2. Instantiates a full `Main` scene (`MainScenePacked.instantiate()`)
3. Sets up arena with 40 obstacles, 3 initial enemies
4. Creates AI controller and sensor

**Enemies don't use object pooling** — they `queue_free()` on death and new ones are `instantiate()`'d. Projectiles DO use pooling (good).

### Optimization
**O9: Pool enemy instances (Medium effort, ~variable speedup on GC pressure)**
- Apply the same `ObjectPool` pattern used for projectiles
- Reduces allocation pressure during training

**O10: Pre-instantiate replacement scenes (Medium effort, smoother frame times)**
- Start instantiating the next scene 1-2 seconds before the current one finishes
- Spreads the instantiation cost across multiple frames

---

## Prioritized Optimization Roadmap

| Priority | Optimization | Effort | Estimated Speedup | ROI |
|----------|-------------|--------|-------------------|-----|
| **🔴 P0** | **Wire RustNeuralNetwork into training** (O4) | 2-4 hours | **12-15% frame time reduction** | ⭐⭐⭐⭐⭐ |
| **🔴 P0** | **Fix enemy find_nearest_target per-frame** (O5+O6) | 30 min | **5-8% frame time reduction** | ⭐⭐⭐⭐⭐ |
| **🟡 P1** | **Reduce SubViewport resolution** (O7) | 15 min | **10% in GUI mode** | ⭐⭐⭐⭐ |
| **🟡 P1** | **Spatial partitioning for sensors** (O1) | 4-6 hours | **10-15% frame time reduction** | ⭐⭐⭐⭐ |
| **🟢 P2** | **Reduce ray count to 8** (O3) | 1 hour | **15-20% frame time reduction** | ⭐⭐⭐ |
| **🟢 P2** | **Port sensor system to Rust** (O2) | 8-12 hours | **25-30% frame time reduction** | ⭐⭐⭐ |
| **🟢 P2** | **Enemy object pooling** (O9) | 2-3 hours | **Smoother frames** | ⭐⭐ |
| **🔵 P3** | **UPDATE_WHEN_VISIBLE viewports** (O8) | 1 hour | **5-10% in GUI mode** | ⭐⭐ |
| **🔵 P3** | **Pre-instantiate replacement scenes** (O10) | 3-4 hours | **Smoother frames** | ⭐⭐ |

---

## Quick Wins (Implementable Now)

### 1. Integrate RustNeuralNetwork into Training (P0)
The Rust extension already exists with a compatible API. Changes needed:
- `evolution.gd`: Use `RustNeuralNetwork.create()` instead of `NeuralNetworkScript.new()`
- Handle `clone()` → `clone_network()` rename
- Ensure `crossover_with()` works (Rust takes `Gd<RustNeuralNetwork>`)

### 2. Cache Enemy Player Reference (P0)
```gdscript
# enemy.gd: Replace per-frame find_nearest_target() in backup collision check
# Just use self.player (already cached from _ready and calculate_next_move)
if player and is_instance_valid(player):
    var dist = global_position.distance_to(player.global_position)
    if dist < collision_dist:
        player.on_enemy_collision(self)
```

### 3. Reduce SubViewport Resolution (P1)
```gdscript
# arena_pool.gd: In create_slot() and replace_slot()
viewport.size = Vector2(640, 360)  # Was 1280×720
```

---

## Headless vs GUI Analysis

For overnight runs with `--headless`:
- Rendering is free (no-op backend)
- SubViewport resolution doesn't matter
- Focus should be on **sensor system + neural network + enemy AI**

For development/debugging runs (GUI):
- Rendering is ~20% of frame time
- SubViewport optimization matters
- Reducing to 640×360 or using UPDATE_WHEN_VISIBLE helps

---

## Long-Term Architecture Recommendations

1. **Batch sensor computation in Rust**: Process all 20 agents' sensors in a single Rust call, with SIMD vectorization
2. **Batch neural network forward**: All 20 forward passes in one Rust call using matrix multiplication libraries
3. **Move evolution operators to Rust**: `mutate()`, `crossover_with()`, `tournament_select()` are already in Rust for individual networks but the population-level operations are still in GDScript
4. **Consider disabling physics for training**: Replace `move_and_slide()` with direct position updates + manual collision checks — eliminates Godot physics engine overhead

---

## Appendix: Neural Network Benchmark Data

From `scripts/benchmark_rust.gd` (86→80→6 architecture):
- **GDScript**: ~150µs per forward pass (~6,667 passes/sec)
- **Rust**: ~10-20µs per forward pass (~50,000-100,000 passes/sec)
- **Speedup**: 5-15× depending on memory vs feedforward mode

At 20 arenas × 60 FPS: needs 1,200 forward passes/sec. Current GDScript handles this (budget: 180ms/sec of 1000ms), but with Rust it would drop to ~24ms/sec — freeing **156ms/sec** for more arenas or higher time scale.
