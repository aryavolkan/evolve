# 🧬 EVOLVE: Research Plan & Roadmap

*Generated 2026-02-06. Next session: pick a phase and start building.*

## Current State
- 2D arcade survival, chess-piece enemies, 10 powerup types, 3840² arena
- Neuroevolution: 100 fixed-topology networks (86→32→6), tournament selection, crossover, mutation
- 20 parallel SubViewport training arenas, deterministic preset events
- Adaptive mutation, elitism, early stopping, W&B sweep integration
- All GDScript, Godot 4.5+

---

## Phase 1: Quick Wins (1-2 weeks each)

### 1. Curriculum Learning — Automated Difficulty Staging
Instead of throwing agents into the full game from gen 0, start simple and progressively increase complexity.

**Stages (auto-advance when median fitness crosses threshold):**

| Stage | Arena | Enemies | Powerups | Threshold |
|-------|-------|---------|----------|-----------|
| 1 | 960² | Pawns only | Health only | Median survival > 30s |
| 2 | 1920² | + Knights | + Speed, Shield | Median survival > 45s |
| 3 | 3840² | + Bishops, Rooks | All types | Median survival > 60s |
| 4 | 3840² | + Queens | All | Median survival > 45s |
| 5 | 3840², more obstacles | All, faster spawn | All, rarer | Median survival > 30s |

**Implementation:** Parameterize arena setup, gate on population stats. ~50 lines on top of existing `training_manager.gd`.

**Why first:** Dramatically faster initial learning. Cleaner fitness gradients. Easy to build.

### 2. Multi-Objective Fitness (NSGA-II)
Stop hand-tuning fitness weight ratios. Evolve the Pareto front across three objectives:
1. **Survival time** (ticks alive)
2. **Kills** (enemies destroyed)
3. **Collection** (powerups gathered)

**Implementation:** Replace tournament selection with non-dominated sorting + crowding distance. ~100 lines in `evolution.gd`.

**Why:** Eliminates fitness weight tuning. Produces a natural spectrum of strategies. Combines well with MAP-Elites later.

---

## Phase 2: Diversity + Memory (2-3 weeks)

### 3. MAP-Elites — Quality-Diversity Archive
Instead of one best agent, fill a 2D behavioral grid:
- **Axis 1:** Aggression (% time moving toward enemies vs away)
- **Axis 2:** Collection focus (powerups collected per minute)

20×20 grid = 400 cells, each holding the fittest agent with that behavioral profile. You get a zoo: pacifist, berserker, sniper, balanced, kamikaze, cautious collector...

**Implementation:** ~200 lines. Archive dictionary keyed by behavior bin, uniform random parent selection from archive, standard mutation.

```gdscript
var archive: Dictionary = {}  # Vector2i(aggression_bin, collection_bin) → {genome, fitness, behavior}

func add_to_archive(genome, behavior: Vector2, fitness: float):
    var bin = Vector2i(int(behavior.x * GRID_SIZE), int(behavior.y * GRID_SIZE))
    if bin not in archive or archive[bin].fitness < fitness:
        archive[bin] = {genome = genome, fitness = fitness, behavior = behavior}
```

**Why:** Inherently more interesting than one optimized bot. Enables browsable playstyle library. Cross-pollination between niches.

### 4. Recurrent Memory (Elman Network)
Feed previous hidden state back as additional input. Agents develop temporal strategies: "that knight just L-shaped past me — it'll circle back."

**Implementation:** Trivial. Store `prev_hidden` (32 values), concatenate to input (86 + 32 = 118 inputs). Adjust weight matrix sizes.

```gdscript
var prev_hidden: PackedFloat32Array = []

func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
    var full_input = PackedFloat32Array()
    full_input.append_array(inputs)
    full_input.append_array(prev_hidden)
    # ... standard forward pass with full_input ...
    prev_hidden = hidden.duplicate()
    return output
```

**Why:** Enables temporal strategies impossible with feedforward. Visibly more intelligent, less twitchy behavior.

---

## Phase 3: NEAT (3-4 weeks)

### 5. NEAT — Evolve the Topology
Evolve both structure and weights. Start from minimal networks (direct input→output), complexify through structural mutations (add node, add connection).

**Core components:**
- `neat_genome.gd` — Node genes + connection genes with innovation numbers
- `neat_species.gd` — Genomes grouped by compatibility distance
- `neat_population.gd` — Speciated evolution with fitness sharing
- `neat_network.gd` — Arbitrary-topology forward pass via topological sort

**Key concepts:**
- Global innovation counter for structural mutations
- Crossover by gene alignment (innovation numbers)
- Speciation protects new topological innovations from immediate competition
- Fitness sharing within species

**Why wait:** Best done after validating training pipeline with simpler improvements. Biggest single architectural change.

---

## Phase 4: The Vision (4-6 weeks)

### 6. Competitive Co-Evolution
Give enemies neural networks. Two populations co-evolve in an arms race.

- Enemy nets are small (8 inputs → 8 hidden → 2-3 outputs per type)
- Player fitness = survival/kills, Enemy fitness = damage dealt/player kills
- **Hall of Fame:** Archive top-5 enemies per generation, test new players against them to prevent cycling

**Why:** Emergent difficulty without hand-tuning. The chess theme becomes literal — an evolving chess match.

### 7. Live Evolution Sandbox — The Game IS Evolution
Transform from "game with AI training" to "interactive evolution simulator."

- Real-time NEAT (rtNEAT): replace worst agent every N ticks with offspring
- 20-50 agents visible simultaneously in one arena
- Player interactions: place obstacles, spawn enemy waves, drop powerups, bless/curse agents
- **Live network visualization:** Click any agent, see its neural network firing
- **Phylogenetic tree:** Real-time lineage visualization
- **Educational mode:** Sidebar explains what's evolving, sliders for mutation rate/selection pressure

**Why this is the endgame:** Zero games on the market combine interactive evolution guidance + live neuroevolution visualization + chess-themed survival. Compelling as indie game, educational tool, and streaming content.

---

## Summary Roadmap

| Phase | Ideas | Effort | Impact |
|-------|-------|--------|--------|
| 1 | Curriculum (#1) + NSGA-II (#2) | 1-2 weeks | Training quality ↑↑ |
| 2 | MAP-Elites (#3) + Elman Memory (#4) | 2-3 weeks | Diversity + intelligence ↑↑ |
| 3 | NEAT (#5) | 3-4 weeks | Architecture evolution ↑↑↑ |
| 4 | Co-Evolution (#6) + Live Sandbox (#7) | 4-6 weeks | Product vision ↑↑↑↑ |

---

## References
- Stanley & Miikkulainen, "Evolving Neural Networks through Augmenting Topologies" (2002) — NEAT
- Mouret & Clune, "Illuminating search spaces by mapping elites" (2015) — MAP-Elites
- Deb et al., "A fast and elitist multiobjective genetic algorithm: NSGA-II" (2002)
- Stanley et al., "Real-time neuroevolution in the NERO video game" (2005) — rtNEAT
- Rawal & Miikkulainen, "Evolving Deep LSTM-based Memory cells" (2016)
