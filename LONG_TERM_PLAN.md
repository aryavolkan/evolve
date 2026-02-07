# Long-Term Roadmap

Two independent feature tracks remaining after Phase 1-3 completion. Both can be developed in parallel.

---

## Track A: Competitive Co-Evolution (5 PRs)

Evolve enemy behaviors alongside player behaviors in an adversarial arms race. Enemies gain neural networks and evolve to hunt players more effectively, while players co-evolve to survive smarter enemies.

### Architecture Decisions

- **One universal enemy network** — enemy type is an input, not a separate network per type. The network outputs 8 directional preferences; the controller picks the closest *legal* move for that piece type.
- **Enemy sensor** — ~16 inputs: player direction/distance (2), nearest obstacle directions (4), wall distances (4), own type encoding (1), player velocity (2), player power-up state flags (3).
- **CoEvolution wraps two Evolution instances** — it's a coordinator, not a replacement. Player evolution unchanged; enemy evolution added alongside.
- **Complements curriculum learning** — curriculum gates which enemy types appear; co-evolution makes those enemies smarter within each stage.
- **Adversarial fitness** — player fitness unchanged; enemy fitness = damage dealt to player + proximity pressure - time player survived. Zero-sum tension drives the arms race.
- **Hall of Fame** — archive top-5 enemy networks per generation. Periodically evaluate players against archived enemies to prevent cycling (A beats B beats C beats A).

### PR Breakdown

| PR | Title | Effort | Risk | Key Files |
|----|-------|--------|------|-----------|
| A1 | Enemy Sensor + AI Controller | Medium | Low | New: `ai/enemy_sensor.gd`, `ai/enemy_ai_controller.gd`. Modify: `enemy.gd` (add `ai_controlled` flag, wire network outputs through legal move filter) |
| A2 | Enemy Evolution Backend | Medium | Low | New: `ai/coevolution.gd` — dual-population coordinator. Uses existing `Evolution` class for both populations |
| A3 | Training Manager Integration | Large | Medium | Modify: `training_manager.gd` — new `COEVOLUTION` mode, dual-population evaluation loop, assign evolved enemy networks to arena enemies |
| A4 | Fitness Tuning + Hall of Fame | Medium | Medium | Modify: `ai/coevolution.gd` — hall-of-fame archive, adversarial fitness shaping, anti-cycling evaluation schedule |
| A5 | Save/Load + W&B Metrics | Small | Low | Persistence for both populations (`user://enemy_population.evo`), enemy metrics in `scripts/wandb_bridge.py` |

### PR Details

**A1: Enemy Sensor + AI Controller**
- `enemy_sensor.gd`: Raycast-free sensor (enemies don't need 360 vision). Direct vector inputs: player direction, wall distances, nearest obstacle. ~16 float inputs total.
- `enemy_ai_controller.gd`: Takes 8 network outputs (N, NE, E, SE, S, SW, W, NW), filters to legal moves for the enemy's piece type (reusing `get_pawn_move()`, `get_knight_move()`, etc. logic from `enemy.gd`), picks highest-scored legal direction.
- `enemy.gd` changes: Add `var ai_controlled: bool = false` and `var ai_network`. In `calculate_next_move()`, branch: if `ai_controlled`, use AI controller; else use existing hardcoded logic.

**A2: Enemy Evolution Backend**
- `coevolution.gd`: Holds `player_evolution: Evolution` and `enemy_evolution: Evolution`. Coordinates generational lifecycle: evaluate players against current enemy population, evaluate enemies against current player population, evolve both.
- Enemy network architecture: 16 inputs → 16 hidden (smaller than player, enemies are simpler) → 8 outputs.
- Same mutation/crossover operators as player evolution (reuse `Evolution` class).

**A3: Training Manager Integration**
- New mode `Mode.COEVOLUTION` in training manager.
- Each arena gets a player AI + an enemy AI controlling all enemies in that arena.
- Evaluation pairs: round-robin or random sampling from opposing population.
- Batch scheduling: evaluate `parallel_count` player-enemy pairs simultaneously.
- UI: stats bar shows both populations' best fitness.

**A4: Fitness Tuning + Hall of Fame**
- Hall of Fame: `Array` of top-5 enemy networks per generation (deep-copied).
- Every N generations, evaluate players against HoF enemies instead of current population.
- Prevents Red Queen cycling where populations chase each other without net improvement.
- Fitness shaping: enemy bonus for forcing player movement changes, penalty for clumping.

**A5: Save/Load + W&B**
- Save enemy population to `user://enemy_population.evo`.
- Save HoF to `user://enemy_hof.evo`.
- W&B bridge: log enemy population best/mean fitness, HoF evaluation scores, diversity metrics.

---

## Track B: Live Sandbox (5 PRs)

Interactive environment for exploring evolved strategies. Watch, compare, and understand what the AI has learned.

### Architecture Decisions

- **UI lives in `ui/` directory** — follows existing pattern (`ui/pareto_chart.gd`).
- **`_draw()`-based rendering** — ParetoChart pattern: custom `_draw()` for data visualization widgets. No scene files needed for charts/heatmaps.
- **MAP-Elites archive is the data source** — heatmap reads from `MapElites.archive` (Dictionary of `Vector2i → {solution, fitness, behavior}`). Needs a `get_archive_grid()` helper for bulk access.
- **Sandbox reuses existing arena infrastructure** — SubViewportContainer grid from training mode. Sandbox configures arenas differently but doesn't rebuild them.

### PR Breakdown

| PR | Title | Effort | Risk | Key Files |
|----|-------|--------|------|-----------|
| B1 | MAP-Elites Heatmap | Medium | Low | New: `ui/map_elites_heatmap.gd`. Modify: `ai/map_elites.gd` (add `get_archive_grid()`) |
| B2 | Archive Playback | Medium | Low | Modify: `training_manager.gd` (add archive playback mode), `ui/map_elites_heatmap.gd` (click handling) |
| B3 | Sandbox Mode + Params | Medium | Low | New: `ui/sandbox_panel.gd`. Modify: `training_manager.gd` (add `SANDBOX` mode with configurable params) |
| B4 | Side-by-Side Comparison | Medium | Low-Med | Modify: `training_manager.gd` (multi-strategy playback), `ui/sandbox_panel.gd` (strategy selection) |
| B5 | Network Topology Viz | Large | Medium | New: `ui/network_visualizer.gd` — real-time NEAT graph rendering with live activation coloring |

### PR Details

**B1: MAP-Elites Heatmap**
- 20x20 colored grid overlaid on pause/stats screen.
- Cell color: empty=dark gray, occupied=green intensity proportional to fitness.
- Axes labeled: X=kill rate, Y=collection rate (matching `MapElites` behavior dimensions).
- Add `MapElites.get_archive_grid() -> Array` — returns 20x20 array of `{fitness, behavior}` or `null` for empty cells.
- Uses `_draw()` pattern from `ParetoChart`.

**B2: Archive Playback**
- Click a heatmap cell → load that strategy's network → play it back in a single arena.
- New mode `Mode.ARCHIVE_PLAYBACK` in training manager (similar to existing `GENERATION_PLAYBACK`).
- `MapElites.get_elite(bin)` already returns the solution — just need to wire it to playback.
- Show cell coordinates and fitness score during playback.

**B3: Sandbox Mode + Params**
- `sandbox_panel.gd`: UI panel with sliders/dropdowns for:
  - Enemy types to include (checkboxes per type)
  - Spawn rate multiplier (0.5x - 3x)
  - Arena scale (960, 1920, 3840)
  - Power-up frequency
  - Starting difficulty
- Sandbox mode uses a single arena with custom configuration.
- Load any saved network (best, or from archive) into the sandbox.

**B4: Side-by-Side Comparison**
- Run 2-4 strategies simultaneously in parallel arenas with identical seeds.
- Reuse SubViewportContainer grid (already supports 20 arenas, just use 2-4).
- Strategy selection: best overall, archive cells, or saved networks.
- Identical `generation_events_by_seed` ensures fair comparison.
- Display per-arena stats: score, kills, survival time, powerups collected.

**B5: Network Topology Viz**
- NEAT networks have variable topology — visualize as a directed graph.
- Nodes positioned in layers (input → hidden → output), colored by activation value (blue=negative, white=zero, red=positive).
- Connections drawn with thickness proportional to weight magnitude, color for sign.
- Updates in real-time during playback (every physics frame would be too fast — throttle to ~10fps).
- Falls back to fixed-layout diagram for non-NEAT networks (fixed topology = fixed positions).

---

## Dependencies

```
Track A (Co-Evolution)          Track B (Live Sandbox)
========================        ========================
A1  Enemy Sensor + Controller   B1  MAP-Elites Heatmap
 ↓                               ↓
A2  Evolution Backend           B2  Archive Playback
 ↓                               ↓
A3  Training Integration        B3  Sandbox Mode
 ↓                               ↓
A4  Fitness + Hall of Fame      B4  Side-by-Side Comparison
 ↓
A5  Save/Load + W&B            B5  Network Topology Viz
                                    (independent, anytime)
```

- **Tracks A and B are independent** — can develop in parallel.
- **B4 optionally benefits from A** — comparing player strategies against co-evolved enemies is more interesting, but not required.
- **B5 is fully independent** — can be implemented at any point since it only reads network structure.

## Suggested Order

1. **B1 → B2** — Quick wins, immediate visual payoff from existing MAP-Elites data.
2. **A1 → A2** — Enemy AI foundation, low risk.
3. **B3** — Sandbox mode unlocks manual experimentation.
4. **A3 → A4 → A5** — Full co-evolution pipeline.
5. **B4** — Side-by-side comparison (more meaningful after co-evolution exists).
6. **B5** — Network viz as a polish feature.
