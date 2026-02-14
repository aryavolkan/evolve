# Rust Performance Investigation (godot-rust / GDExtension)

**Date:** 2026-02-14  
**Status:** Investigation Complete — Recommendation: **YES, pursue incrementally**

---

## 1. godot-rust Overview

[godot-rust/gdext](https://github.com/godot-rust/gdext) provides Rust bindings for Godot 4 via GDExtension. Key facts:

- **Godot 4.6 compatibility:** godot-rust 0.4+ supports Godot 4.2+, so **fully compatible** with our Godot 4.6. Use the `api-4-6` feature flag.
- **Expose Rust to GDScript:** Rust classes decorated with `#[derive(GodotClass)]` and `#[godot_api]` are callable from GDScript like native classes.
- **Incremental adoption:** Rust and GDScript coexist in the same project. You can port one file at a time.
- **License:** MPL 2.0 — fine for commercial/closed-source games.
- **Maturity:** Production-usable since 2023; active development, CI-tested against multiple Godot versions.

## 2. Current Evolve Architecture & Bottlenecks

### Codebase Stats
- **~7,285 lines** across 30 GDScript files in `ai/`
- **~560 tests** (not examined in detail)
- **20 parallel arenas** running simultaneously via `SubViewport` grid

### Computational Hotspots (ranked by impact)

#### 🔴 HIGH — Neural Network Forward Pass (`neural_network.gd`, `neat_network.gd`)
- **`neural_network.gd` forward():** Triple-nested loops — for each hidden neuron, iterates all inputs (64×32 = 2,048 multiply-adds), then for each output, iterates all hidden (32×8 = 256 multiply-adds). With Elman memory: additional 32×32 = 1,024 ops.
- **Called every physics frame for every agent** across 20 arenas. At 60fps with 20 agents, that's **1,200 forward passes/second**.
- **`neat_network.gd` forward():** Even worse — uses Dictionary lookups and linear scans of connection arrays for each node. O(nodes × connections) with hash overhead per step.

#### 🟠 MEDIUM-HIGH — Sensor Calculations (`sensor.gd`)
- **16 rays × 3 entity types = 48 ray-entity intersection tests per agent per frame.**
- Already well-optimized with per-arena entity caching (static cache, once per physics frame).
- Inner loop is simple dot products and distance checks — fast but high volume.

#### 🟡 MEDIUM — Evolution Operations (`neat_evolution.gd`)
- **Once per generation** (not per frame), so lower frequency.
- NSGA-II `non_dominated_sort`: O(MN²) pairwise comparisons — expensive for large populations.
- Speciation, crossover, mutation: moderate cost, lots of array manipulation.

#### 🟢 LOW — MAP-Elites, UI, config parsing
- Infrequent operations, not bottlenecks.

### Parallel Processing
- Already uses **20 parallel arenas** via `SubViewport` containers
- All run on the **main thread** (Godot's scene tree is single-threaded)
- No Rust-level parallelism (rayon, etc.) currently possible within Godot's frame

## 3. Rust Conversion Candidates

### Priority 1: `neural_network.gd` → Rust (HIGH impact, MODERATE effort)
**Why:** Called ~1,200×/sec, pure math, no Godot API dependencies.

**Estimated speedup: 5-10×** for forward pass.

**Example conversion:**

```rust
use godot::prelude::*;

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct NeuralNetwork {
    base: Base<RefCounted>,
    input_size: usize,
    hidden_size: usize,
    output_size: usize,
    weights_ih: Vec<f32>,
    bias_h: Vec<f32>,
    weights_ho: Vec<f32>,
    bias_o: Vec<f32>,
    // Elman memory
    weights_hh: Vec<f32>,
    prev_hidden: Vec<f32>,
    use_memory: bool,
    // Cached
    hidden: Vec<f32>,
    output: Vec<f32>,
}

#[godot_api]
impl NeuralNetwork {
    #[func]
    fn create(input_size: i32, hidden_size: i32, output_size: i32) -> Gd<Self> {
        let i = input_size as usize;
        let h = hidden_size as usize;
        let o = output_size as usize;
        Gd::from_init_fn(|base| Self {
            base,
            input_size: i,
            hidden_size: h,
            output_size: o,
            weights_ih: vec![0.0; i * h],
            bias_h: vec![0.0; h],
            weights_ho: vec![0.0; h * o],
            bias_o: vec![0.0; o],
            weights_hh: Vec::new(),
            prev_hidden: Vec::new(),
            use_memory: false,
            hidden: vec![0.0; h],
            output: vec![0.0; o],
        })
    }

    #[func]
    fn forward(&mut self, inputs: PackedFloat32Array) -> PackedFloat32Array {
        let inp = inputs.as_slice();
        
        // Hidden layer
        for h in 0..self.hidden_size {
            let mut sum = self.bias_h[h];
            let offset = h * self.input_size;
            for i in 0..self.input_size {
                sum += self.weights_ih[offset + i] * inp[i];
            }
            if self.use_memory {
                let ctx_offset = h * self.hidden_size;
                for ph in 0..self.hidden_size {
                    sum += self.weights_hh[ctx_offset + ph] * self.prev_hidden[ph];
                }
            }
            self.hidden[h] = sum.tanh();
        }
        
        if self.use_memory {
            self.prev_hidden.copy_from_slice(&self.hidden);
        }
        
        // Output layer
        for o in 0..self.output_size {
            let mut sum = self.bias_o[o];
            let offset = o * self.hidden_size;
            for h in 0..self.hidden_size {
                sum += self.weights_ho[offset + h] * self.hidden[h];
            }
            self.output[o] = sum.tanh();
        }
        
        PackedFloat32Array::from(self.output.as_slice())
    }

    #[func]
    fn get_weights(&self) -> PackedFloat32Array {
        let mut all = Vec::with_capacity(self.weights_ih.len() + self.bias_h.len() 
            + self.weights_ho.len() + self.bias_o.len() + self.weights_hh.len());
        all.extend_from_slice(&self.weights_ih);
        all.extend_from_slice(&self.bias_h);
        all.extend_from_slice(&self.weights_ho);
        all.extend_from_slice(&self.bias_o);
        if self.use_memory {
            all.extend_from_slice(&self.weights_hh);
        }
        PackedFloat32Array::from(all.as_slice())
    }

    #[func]
    fn set_weights(&mut self, weights: PackedFloat32Array) {
        let w = weights.as_slice();
        let mut idx = 0;
        for v in self.weights_ih.iter_mut() { *v = w[idx]; idx += 1; }
        for v in self.bias_h.iter_mut() { *v = w[idx]; idx += 1; }
        for v in self.weights_ho.iter_mut() { *v = w[idx]; idx += 1; }
        for v in self.bias_o.iter_mut() { *v = w[idx]; idx += 1; }
        if self.use_memory {
            for v in self.weights_hh.iter_mut() { *v = w[idx]; idx += 1; }
        }
    }
}
```

**GDScript call site stays almost identical:**
```gdscript
# Before:
var nn = NeuralNetwork.new(64, 32, 8)
# After (Rust class auto-registered):
var nn = NeuralNetwork.create(64, 32, 8)
var output = nn.forward(inputs)  # Same API!
```

### Priority 2: `neat_network.gd` → Rust (HIGH impact, MODERATE effort)
**Why:** Dictionary-heavy forward pass is worst-case for GDScript. Rust with Vec/HashMap would be dramatically faster.  
**Estimated speedup: 8-15×** (Dictionary access overhead dominates in GDScript).

### Priority 3: `nsga2.gd` → Rust (MEDIUM impact, LOW effort)
**Why:** Pure algorithm, no Godot dependencies. O(MN²) sorting benefits greatly from native speed.  
**Estimated speedup: 5-10×** for `non_dominated_sort`.

### Priority 4: `sensor.gd` math helpers → Rust (MEDIUM impact, HIGH effort)
**Why:** Already well-optimized. Needs Godot node access which complicates Rust integration.  
**Estimated speedup: 2-3×** (limited by Godot API calls, not pure math).

### Priority 5: `neat_evolution.gd` → Rust (MEDIUM impact, HIGH effort)
**Why:** Complex logic with many Godot types. Only runs once per generation.  
**Estimated speedup: 3-5×** but low frequency reduces overall impact.

## 4. Performance Gain Estimates

| Component | Calls/sec | GDScript time est. | Rust speedup | Net impact |
|---|---|---|---|---|
| `neural_network.forward()` | 1,200 | ~40% of frame | 5-10× | **HIGH** |
| `neat_network.forward()` | 1,200 (when used) | ~50% of frame | 8-15× | **HIGH** |
| `sensor.get_inputs()` | 1,200 | ~20% of frame | 2-3× | **MEDIUM** |
| `nsga2.non_dominated_sort()` | 1/gen | ~5% of gen | 5-10× | **LOW** |
| `neat_evolution.evolve()` | 1/gen | ~10% of gen | 3-5× | **LOW** |

**Conservative overall estimate:** Porting neural network forward passes alone could yield a **2-4× overall simulation speedup**, since they dominate per-frame computation.

## 5. Implementation Complexity

### Setup (1-2 days)
1. Install Rust toolchain (`rustup`)
2. Create `rust/` directory with `Cargo.toml` depending on `godot = { git = "https://github.com/godot-rust/gdext", features = ["api-4-6"] }`
3. Create `.gdextension` file pointing to the compiled `.dylib`/`.so`/`.dll`
4. Build with `cargo build` — Godot auto-loads the extension

### Incremental Porting Strategy
- **Start with `neural_network.gd`** — self-contained, pure math, highest impact
- Keep same API surface so GDScript callers need minimal changes
- Run existing tests against Rust implementation to verify correctness
- Port `neat_network.gd` next, then `nsga2.gd`

### Testing
- **No need to rewrite all 560 tests.** Tests call via GDScript API which stays the same.
- Add Rust unit tests for the math internals (run via `cargo test`)
- Verify by running existing training and comparing fitness curves

### Learning Curve
- Moderate. Rust's ownership model has a learning curve, but:
  - godot-rust has good docs and examples
  - Our target code is pure math (no complex lifetime issues)
  - The godot-rust `#[func]` macro handles most boilerplate

## 6. Alternatives Considered

| Alternative | Effort | Gain | Notes |
|---|---|---|---|
| **godot-rust (this proposal)** | Medium | 2-4× overall | Best long-term investment |
| **GDScript optimizations** | Low | 10-30% | Already well-optimized (cached arrays, PackedFloat32Array) |
| **C# via Godot Mono** | Medium | 2-3× | Less than Rust, adds .NET dependency |
| **Compute shaders (GPU)** | High | 10-50× for batched NN | Complex, only helps if batch all agents together |
| **Algorithmic improvements** | Low-Medium | Varies | e.g., sparse NEAT networks already help |
| **Reduce parallel arenas** | None | Linear | Trades speed for training throughput |

## 7. Recommendation

### ✅ YES — Pursue godot-rust, incrementally

**Phase 1 (1 week):** Port `neural_network.gd` to Rust
- Highest impact, lowest risk
- Self-contained pure math
- Verify with existing tests
- Expected: **2-3× overall simulation speedup**

**Phase 2 (1 week):** Port `neat_network.gd` to Rust  
- Eliminates Dictionary overhead in forward pass
- Expected: additional **1.5-2× when using NEAT networks**

**Phase 3 (3-5 days):** Port `nsga2.gd` to Rust
- Quick win, pure algorithm
- Speeds up generation transitions

**Phase 4 (optional):** Explore batched forward passes
- Process all 20 agents' neural networks in a single Rust call
- Could use SIMD or even rayon parallelism within the Rust code
- Potential for **additional 2-4× on top of single-agent gains**

### Total estimated investment: **2-3 weeks**
### Total estimated speedup: **3-6× overall simulation speed**

This means training runs that currently take 8 hours could complete in 1.5-3 hours.

## 8. Next Steps (if proceeding)

1. `cargo init --lib rust/evolve-native`
2. Add godot-rust dependency with `api-4-6` feature
3. Port `NeuralNetwork` class (use the example above as starting point)
4. Create `rust/evolve-native.gdextension` file
5. Build and test: `cd rust/evolve-native && cargo build`
6. Run existing Evolve tests to verify correctness
7. Benchmark: time a generation with GDScript vs Rust neural network
8. If gains confirmed, continue to Phase 2
