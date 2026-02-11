# Evolve — Unified Development Roadmap

**Last Updated:** 2026-02-10  
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

### ⚠️ Key Risks
1. **`training_manager.gd` is a god object** (1,600+ LOC) — mixes UI, orchestration, persistence, analytics
2. **Duplicate training flows** — `ai/trainer.gd` vs `training_manager.gd` creates confusion
3. **Performance bottlenecks** — sensor queries scan entire scene tree per frame per arena
4. **Configuration sprawl** — settings scattered across files, no validation
5. **Missing architecture docs** — newcomers can't understand data flow
6. **No results documentation** — research findings not captured

### 🎯 Strategic Priorities
1. **Consolidate and refactor** before adding complexity (co-evolution, sandbox)
2. **Document what works** — capture sweep findings, architectural patterns
3. **Polish the game itself** — it deserves the same care as the AI
4. **Enable others to contribute** — onboarding docs, cross-platform support

---

## Horizon 1: Foundation & Quick Wins (1-3 weeks)

### Phase 1A: Documentation & Onboarding
**Goal:** Make the project accessible to humans and AI contributors

| Task | Priority | Effort | Owner |
|------|----------|--------|-------|
| Architecture diagram (data flow: training → evolution → networks → arenas) | Critical | Small | Any |
| RESULTS.md documenting sweep findings and optimal configs | High | Small | Alfred |
| CONTRIBUTING.md with test framework, PR process, algorithm extension guide | High | Medium | Grok |
| Fix cross-platform paths (env vars for Godot, user data) | High | Small | Codex |

**Deliverables:**
- README gets architecture section with Mermaid diagram
- RESULTS.md captures:
  - Best hyperparameters from sweeps (x0cst76l)
  - Training curves and learning progression
  - Algorithm comparisons (NEAT vs fixed-topology, with/without curriculum)
- CONTRIBUTING.md enables new contributors

### Phase 1B: Technical Debt Reduction
**Goal:** Reduce complexity before Track A/B expansion

| Task | Priority | Effort | Files |
|------|----------|--------|-------|
| Extract `CurriculumManager` from `training_manager.gd` | Critical | Medium | New: `ai/curriculum_manager.gd`, Modify: `training_manager.gd` |
| Extract `ArenaPool` (SubViewport lifecycle) | High | Medium | New: `ai/arena_pool.gd`, Modify: `training_manager.gd` |
| Extract `StatsTracker` (fitness accumulation, history) | High | Small | New: `ai/stats_tracker.gd`, Modify: `training_manager.gd` |
| Deprecate or clarify `ai/trainer.gd` vs `training_manager.gd` | High | Small | Mark deprecated or document separation |
| Create `TrainingConfig` resource (centralize all settings) | High | Medium | New: `ai/training_config.gd` |

**Deliverables:**
- `training_manager.gd` reduced from 1,600 LOC → ~400 LOC (thin coordinator)
- Clear single source of truth for training configuration
- Testable, modular components

**Rationale (Codex):** The god object risks cascade failures when adding co-evolution and sandbox modes. Split now before complexity doubles.

### Phase 1C: Performance Optimization
**Goal:** Enable scaling to more arenas and faster training

| Task | Priority | Effort | Impact |
|------|----------|--------|--------|
| Cache group members per arena (avoid `get_nodes_in_group()` per frame) | High | Medium | 30-50% frame time reduction |
| Pool SubViewports (recycle instead of destroy/create each batch) | Medium | Medium | Faster batch transitions |
| Profile sensor queries at 20 arenas, optimize hot paths | Medium | Small | Baseline measurement |

**Deliverables:**
- Sensor queries scale O(1) per arena instead of O(A×E)
- 20-arena training runs smoother at 16× speed

---

## Horizon 2: Enhanced Capabilities (3-8 weeks)

### Phase 2A: Game Polish & UX
**Goal:** Make Evolve enjoyable to play and watch, not just train

| Feature | Priority | Effort | Description |
|---------|----------|--------|-------------|
| Title screen & main menu | High | Small | Game mode select, AI watch mode, training mode |
| Game over screen with stats | High | Small | Final score, time survived, kills, best run leaderboard |
| Visual sensor feedback | High | Medium | Highlight active rays, color-code threats/powerups |
| Death animations | Medium | Small | Enemy explosions, player respawn effect |
| In-game training dashboard | Medium | Large | Real-time charts (fitness curves, species count, archive fill) |

**Rationale (Claude):** The chess-piece concept is creative but underexplored. The game exists primarily as a training environment but could stand alone as a fun arcade game.

### Phase 2B: Research Infrastructure
**Goal:** Automate comparative studies and capture findings

| Task | Priority | Effort | Output |
|------|----------|--------|--------|
| Benchmark suite (fixed vs NEAT, single vs multi-objective, ±curriculum) | High | Medium | Automated overnight comparison script |
| Results auto-publish to `docs/results/` with charts | Medium | Small | Jekyll/Hugo site or simple markdown |
| Export trained models as standalone demos | Medium | Medium | `.pck` files users can run without Godot |

**Deliverables:**
- `scripts/benchmark.py` runs controlled experiments, outputs report
- Evidence-based algorithm selection for future projects

### Phase 2C: Quick Wins from Track B
**Goal:** Immediate visual payoff from existing MAP-Elites data

| PR | Title | Effort | Risk | Key Files | Dependencies |
|----|-------|--------|------|-----------|--------------|
| **B1** | MAP-Elites Heatmap | Medium | Low | New: `ui/map_elites_heatmap.gd`, Modify: `ai/map_elites.gd` | None |
| **B2** | Archive Playback | Medium | Low | Modify: `training_manager.gd`, `ui/map_elites_heatmap.gd` | B1 |

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
| **A1** | Enemy Sensor + AI Controller | Medium | Low | New: `ai/enemy_sensor.gd`, `ai/enemy_ai_controller.gd`, Modify: `enemy.gd` | Phase 1B complete |
| **A2** | Enemy Evolution Backend | Medium | Low | New: `ai/coevolution.gd` | A1 |
| **A3** | Training Manager Integration | Large | Medium | Modify: `training_manager.gd` (dual-population evaluation) | A2 + refactored manager |
| **A4** | Fitness Tuning + Hall of Fame | Medium | Medium | Modify: `ai/coevolution.gd` (anti-cycling archive) | A3 |
| **A5** | Save/Load + W&B Metrics | Small | Low | Persistence for both populations, enemy metrics | A4 |

**Critical Dependency:** A3 requires refactored `training_manager.gd` (Phase 1B) to avoid ~2,500 LOC monolith.

**Architecture Notes (from LONG_TERM_PLAN.md):**
- One universal enemy network (type as input, outputs 8 directional preferences)
- CoEvolution wraps two Evolution instances (player + enemy populations)
- Adversarial fitness: player unchanged, enemy = damage dealt - survival time
- Hall of Fame: top-5 enemy networks per generation to prevent cycling

### Track B: Live Sandbox (Remaining)
**Goal:** Interactive exploration of evolved strategies

| PR | Title | Effort | Risk | Description | Dependencies |
|----|-------|--------|------|-------------|--------------|
| **B3** | Sandbox Mode + Params | Medium | Low | UI panel with sliders (enemy types, spawn rate, arena scale) | B2 |
| **B4** | Side-by-Side Comparison | Medium | Med | 2-4 strategies simultaneously with identical seeds | B3 |
| **B5** | Network Topology Viz | Large | Med | Real-time NEAT graph rendering with live activations | Any time |

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
- [ ] README has architecture section
- [ ] RESULTS.md documents x0cst76l sweep findings
- [ ] `training_manager.gd` < 500 LOC
- [ ] Sensor queries profiled, optimized
- [ ] Godot path configurable via env var

### Phase 2 Success
- [ ] Game playable standalone (title screen, game over, polish)
- [ ] Benchmark suite compares algorithms automatically
- [ ] MAP-Elites heatmap interactive (click to playback)

### Track A Success
- [ ] Enemies with neural networks hunting players
- [ ] Co-evolution produces harder enemies over generations
- [ ] Hall of Fame prevents cycling

### Track B Success
- [ ] Sandbox mode with configurable params
- [ ] Side-by-side strategy comparison
- [ ] NEAT topology visualizer (optional polish)

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

See [CONTRIBUTING.md](CONTRIBUTING.md) (to be created in Phase 1A) for:
- How to add a new evolution algorithm
- Test framework usage
- PR review process
- Code style guidelines

---

## Changelog

| Date | Change | Author |
|------|--------|--------|
| 2026-02-10 | Initial unified roadmap synthesizing 4 agent analyses | Alfred |

---

**This roadmap is a living document.** Update as priorities shift, new findings emerge, or team capacity changes. Review quarterly or after major milestones.
