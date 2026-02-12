# Evolve — Unified Development Roadmap

**Last Updated:** 2026-02-12
**Status:** Active Development
**Current Best Result:** Fitness 147,672 (sweep x0cst76l, comfy-sweep-22)

---

## Overview

This roadmap consolidates recommendations from multiple AI agents (Alfred, Grok, Claude, Codex) with the existing long-term plan. It balances immediate wins, technical debt reduction, and visionary features across three horizons.

---

## Current State Assessment

### ✅ Strengths
- **Solid algorithmic foundation:** NEAT, NSGA-II, MAP-Elites, curriculum learning all working
- **Excellent test coverage:** 137 tests covering core systems and integration
- **Clean PR discipline:** Incremental feature branches with design docs
- **W&B integration:** Automated sweeps producing measurable results
- **Optimal hyperparameters identified:** pop=120, hidden=80, elite=20, mut_rate=0.27
- **Co-evolution operational:** Dual-population adversarial training with Hall of Fame
- **Full game modes:** 6 modes (human, training, playback, sandbox, comparison, archive playback)
- **Comprehensive UI:** Title screen, game over, sandbox panel, comparison panel, network visualizer, MAP-Elites heatmap

### ⚠️ Key Risks
1. **`training_manager.gd` is still large** (2,292 LOC) — extraction succeeded but co-evolution, sandbox, and comparison modes added bulk
2. **Duplicate training flows** — `ai/trainer.gd` marked @deprecated but retained for test compatibility

### 🎯 Strategic Priorities
1. **Explore advanced architectures** — rtNEAT, cooperative multi-agent, educational mode
2. **Continue polishing** — death animations, in-game training dashboard
3. **Consider further decomposition** of `training_manager.gd` as new modes are added

---

## Horizon 1: Foundation & Quick Wins (1-3 weeks)

### Phase 1A: Documentation & Onboarding
**Goal:** Make the project accessible to humans and AI contributors

| Task | Priority | Effort | Owner |
|------|----------|--------|-------|
| ~~Architecture diagram (data flow: training → evolution → networks → arenas)~~ | ~~Critical~~ | ~~Small~~ | ✅ Done — README has Mermaid diagram |
| ~~RESULTS.md documenting sweep findings and optimal configs~~ | ~~High~~ | ~~Small~~ | ✅ Done — RESULTS.md created |
| ~~CONTRIBUTING.md with test framework, PR process, algorithm extension guide~~ | ~~High~~ | ~~Medium~~ | ✅ Done — CONTRIBUTING.md created |
| ~~Fix cross-platform paths (env vars for Godot, user data)~~ | ~~High~~ | ~~Small~~ | ✅ Done — `wandb_bridge.py` supports `GODOT_USER_DIR` env var |

**Deliverables:** ✅ All complete
- ~~README gets architecture section with Mermaid diagram~~
- ~~RESULTS.md captures sweep findings, optimal configs, algorithm comparisons~~
- ~~CONTRIBUTING.md enables new contributors~~

### Phase 1B: Technical Debt Reduction
**Goal:** Reduce complexity before Track A/B expansion

| Task | Priority | Effort | Files |
|------|----------|--------|-------|
| ~~Extract `CurriculumManager` from `training_manager.gd`~~ | ~~Critical~~ | ~~Medium~~ | ✅ Done — `ai/curriculum_manager.gd` |
| ~~Extract `ArenaPool` (SubViewport lifecycle)~~ | ~~High~~ | ~~Medium~~ | ✅ Done — `ai/arena_pool.gd` |
| ~~Extract `StatsTracker` (fitness accumulation, history)~~ | ~~High~~ | ~~Small~~ | ✅ Done — `ai/stats_tracker.gd` |
| ~~Deprecate or clarify `ai/trainer.gd` vs `training_manager.gd`~~ | ~~High~~ | ~~Small~~ | ✅ Done — `trainer.gd` marked `@deprecated` |
| ~~Create `TrainingConfig` resource (centralize all settings)~~ | ~~High~~ | ~~Medium~~ | ✅ Done — `ai/training_config.gd` |

**Deliverables:** ✅ All 4 components extracted
- ~~`training_manager.gd` reduced from 1,600 LOC → ~400 LOC (thin coordinator)~~ — Now 2,292 LOC: extraction succeeded but co-evolution, sandbox, and comparison modes added significant new functionality. Further decomposition deferred.
- ~~Clear single source of truth for training configuration~~ — `ai/training_config.gd`
- ~~Testable, modular components~~ — All 4 extracted modules tested

**Rationale (Codex):** The god object risks cascade failures when adding co-evolution and sandbox modes. Split now before complexity doubles. *Outcome: the split enabled adding co-evolution, sandbox, and comparison modes without blocking, though `training_manager.gd` grew with the new mode orchestration logic.*

### Phase 1C: Performance Optimization
**Goal:** Enable scaling to more arenas and faster training

| Task | Priority | Effort | Impact |
|------|----------|--------|--------|
| ~~Cache group members per arena (avoid `get_nodes_in_group()` per frame)~~ | ~~High~~ | ~~Medium~~ | ✅ Done — `sensor.gd` static per-frame cache (60→3 calls/frame) |
| ~~Pool SubViewports (recycle instead of destroy/create each batch)~~ | ~~Medium~~ | ~~Medium~~ | ✅ Done — `ai/arena_pool.gd` centralizes SubViewport lifecycle |
| ~~Profile sensor queries at 20 arenas, optimize hot paths~~ | ~~Medium~~ | ~~Small~~ | ✅ Done — optimized |

**Deliverables:** ✅ All complete
- ~~Sensor queries scale O(1) per arena instead of O(A×E)~~
- ~~20-arena training runs smoother at 16× speed~~

---

## Horizon 2: Enhanced Capabilities (3-8 weeks)

### Phase 2A: Game Polish & UX
**Goal:** Make Evolve enjoyable to play and watch, not just train

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| ~~Title screen & main menu~~ | ~~High~~ | ~~Small~~ | ✅ Done — `ui/title_screen.gd` with 6 game modes |
| ~~Game over screen with stats~~ | ~~High~~ | ~~Small~~ | ✅ Done — `ui/game_over_screen.gd` |
| ~~Visual sensor feedback~~ | ~~High~~ | ~~Medium~~ | ✅ Done — `ui/sensor_visualizer.gd` (V key toggle, color-coded rays) |
| Death animations | Medium | Small | Enemy explosions, player respawn effect |
| In-game training dashboard | Medium | Large | Real-time charts (fitness curves, species count, archive fill) |

**Rationale (Claude):** The chess-piece concept is creative but underexplored. The game exists primarily as a training environment but could stand alone as a fun arcade game.

### Phase 2B: Research Infrastructure
**Goal:** Automate comparative studies and capture findings

| Task | Priority | Effort | Output |
|------|----------|--------|--------|
| ~~Benchmark suite (fixed vs NEAT, single vs multi-objective, ±curriculum)~~ | ~~High~~ | ~~Medium~~ | ✅ `scripts/benchmark.py` — controlled A/B comparison with presets, multi-seed, reports |
| Results auto-publish to `docs/results/` with charts | Medium | Small | Jekyll/Hugo site or simple markdown |
| Export trained models as standalone demos | Medium | Medium | `.pck` files users can run without Godot |

**Deliverables:**
- ✅ `scripts/benchmark.py` runs controlled experiments, outputs report
- Evidence-based algorithm selection for future projects

### Phase 2C: Quick Wins from Track B
**Goal:** Immediate visual payoff from existing MAP-Elites data

| PR | Title | Effort | Risk | Key Files | Dependencies |
|----|-------|--------|------|-----------|--------------|
| ~~**B1**~~ | ~~MAP-Elites Heatmap~~ | ~~Medium~~ | ~~Low~~ | ✅ Done — `ui/map_elites_heatmap.gd` (20×20 clickable grid) | ~~None~~ |
| ~~**B2**~~ | ~~Archive Playback~~ | ~~Medium~~ | ~~Low~~ | ✅ Done — click cell → playback in single arena | ~~B1~~ |

**Why First (Grok):** Quick wins, immediate user-visible improvements, low risk.

**Implementation Details (from LONG_TERM_PLAN.md):**
- **B1:** 20×20 colored grid, cell color intensity = fitness, axes = kill rate × collection rate
- **B2:** Click cell → load strategy → playback in single arena

---

## Horizon 3: Advanced Features (8+ weeks)

### Track A: Competitive Co-Evolution
**Goal:** Enemies evolve neural networks, co-adapting with player AI

| PR | Title | Effort | Risk | Key Changes | Dependencies |
|----|-------|--------|------|-------------|--------------|
| ~~**A1**~~ | ~~Enemy Sensor + AI Controller~~ | ~~Medium~~ | ~~Low~~ | ✅ Done — `ai/enemy_sensor.gd`, `ai/enemy_ai_controller.gd` | ~~Phase 1B~~ |
| ~~**A2**~~ | ~~Enemy Evolution Backend~~ | ~~Medium~~ | ~~Low~~ | ✅ Done — `ai/coevolution.gd` (dual `Evolution` instances) | ~~A1~~ |
| ~~**A3**~~ | ~~Training Manager Integration~~ | ~~Large~~ | ~~Medium~~ | ✅ Done — dual-population eval in `training_manager.gd` | ~~A2~~ |
| ~~**A4**~~ | ~~Fitness Tuning + Hall of Fame~~ | ~~Medium~~ | ~~Medium~~ | ✅ Done — HoF (top-5 enemies/gen) in `coevolution.gd` | ~~A3~~ |
| ~~**A5**~~ | ~~Save/Load + W&B Metrics~~ | ~~Small~~ | ~~Low~~ | ✅ Done — dual-population persistence, enemy metrics logged | ~~A4~~ |

~~**Critical Dependency:** A3 requires refactored `training_manager.gd` (Phase 1B) to avoid ~2,500 LOC monolith.~~ *Resolved — Phase 1B completed before A3.*

**Architecture Notes (from LONG_TERM_PLAN.md):**
- One universal enemy network (type as input, outputs 8 directional preferences)
- CoEvolution wraps two Evolution instances (player + enemy populations)
- Adversarial fitness: player unchanged, enemy = damage dealt - survival time
- Hall of Fame: top-5 enemy networks per generation to prevent cycling

### Track B: Live Sandbox (Remaining)
**Goal:** Interactive exploration of evolved strategies

| PR | Title | Effort | Risk | Description | Dependencies |
|----|-------|--------|------|-------------|--------------|
| ~~**B3**~~ | ~~Sandbox Mode + Params~~ | ~~Medium~~ | ~~Low~~ | ✅ Done — `ui/sandbox_panel.gd` (enemy toggles, spawn/powerup rates, difficulty) | ~~B2~~ |
| ~~**B4**~~ | ~~Side-by-Side Comparison~~ | ~~Medium~~ | ~~Med~~ | ✅ Done — `ui/comparison_panel.gd` (2-4 strategies, identical seeds) | ~~B3~~ |
| ~~**B5**~~ | ~~Network Topology Viz~~ | ~~Large~~ | ~~Med~~ | ✅ Done — `ui/network_visualizer.gd` (NEAT + fixed topology, live activations) | ~~Any time~~ |

**B4 Enhancement:** More meaningful after Track A (compare vs co-evolved enemies)

**B5 Independence:** Fully standalone, can implement anytime as polish feature

---

## Sequencing & Dependencies

### Recommended Order
```
Phase 1A (Docs) ──┬──> Phase 1B (Refactor) ──> Phase 1C (Perf)
                  │                                 │
                  └──> Phase 2A (Game Polish) ─────┤
                                                    │
Phase 2B (Research) ────────────────────────────>  │
                                                    ▼
Phase 2C (B1 → B2) ─────────────────────────> Track A (A1→A2→A3→A4→A5)
                                                    │
                                                    └──> Track B (B3→B4)
                                                              │
                                                              └──> B5 (anytime)
```

### Critical Path
1. **Phase 1B refactor MUST complete before A3** (Training Manager Integration)
2. **B1-B2 can proceed in parallel** with Phase 1
3. **Track A and Track B (B3-B5) are independent** after their respective starts

---

## Resource Allocation & Coordination

### If Solo Developer
- **Week 1-2:** Phase 1A (docs) + 1B (extract CurriculumManager)
- **Week 3:** Phase 1B (extract ArenaPool, StatsTracker) + 1C (cache optimization)
- **Week 4-5:** B1 → B2 (quick visual wins)
- **Week 6-8:** A1 → A2 (enemy AI foundation)
- **Week 9+:** Evaluate: continue Track A (co-evolution) or pivot to Track B (sandbox)

### If Team Available
- **Developer 1:** Phase 1B refactor + Track A
- **Developer 2:** Phase 2A game polish + Track B
- **Any:** Phase 1A docs (parallelizable)

### Monitoring & Checkpoints
- **Milestone 1 (Week 3):** Refactored training_manager, architecture docs published
- **Milestone 2 (Week 5):** B1-B2 live, MAP-Elites heatmap clickable
- **Milestone 3 (Week 8):** A1-A2 complete, enemies with neural networks training
- **Milestone 4 (Week 12):** Track A or Track B fully delivered

---

## Success Metrics

### Phase 1 Success
- [x] README has architecture section
- [x] RESULTS.md documents x0cst76l sweep findings
- [ ] `training_manager.gd` < 500 LOC — *2,292 LOC: extraction succeeded but new modes (co-evolution, sandbox, comparison) added bulk. Target deferred.*
- [x] Sensor queries profiled, optimized
- [x] Godot path configurable via env var

### Phase 2 Success
- [x] Game playable standalone (title screen, game over, polish)
- [x] Benchmark suite compares algorithms automatically
- [x] MAP-Elites heatmap interactive (click to playback)

### Track A Success
- [x] Enemies with neural networks hunting players
- [x] Co-evolution produces harder enemies over generations
- [x] Hall of Fame prevents cycling

### Track B Success
- [x] Sandbox mode with configurable params
- [x] Side-by-side strategy comparison
- [x] NEAT topology visualizer (optional polish)

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Refactor breaks existing training | Keep comprehensive test suite green, add integration test for refactored components |
| Co-evolution fitness tuning difficult | Implement A4 incrementally with logging, use W&B sweeps for adversarial fitness params |
| Training Manager refactor too large | Split into 3 PRs (Curriculum, Arena, Stats), merge incrementally |
| Team coordination overhead | Use this roadmap as living doc, weekly check-ins, clear PR ownership |
| Scope creep | Stick to sequencing, resist adding features mid-phase |

---

## Open Questions & Future Exploration

1. **Real-time evolution (rtNEAT)?** — Not in roadmap yet, could be Phase 3 after sandbox
2. **Player interactions in sandbox?** — Place obstacles, spawn waves, bless/curse agents
3. **Phylogenetic tree visualization?** — Track lineage of successful strategies
4. **Educational mode?** — Annotated playback explaining AI decisions
5. **Multi-agent cooperation?** — Team-based scenarios (not in current scope)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- How to add a new evolution algorithm
- Test framework usage
- PR review process
- Code style guidelines

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-02-12 | Comprehensive status update — mark all completed items across Phases 1-2, Tracks A-B | Claude |
| 2026-02-12 | Add `scripts/benchmark.py` — Phase 2B benchmark suite | Claude |
| 2026-02-10 | Initial unified roadmap synthesizing 4 agent analyses | Alfred |

---

**This roadmap is a living document.** Update as priorities shift, new findings emerge, or team capacity changes. Review quarterly or after major milestones.
