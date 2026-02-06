# NSGA-II Multi-Objective Optimization Design

**Status:** 🟡 Planned — waiting for `feature/curriculum-learning` to merge to main  
**Branch:** `feature/nsga2-multi-objective` (to be created off main after merge)  
**Date:** 2026-02-06

---

## Overview

Replace the single scalar fitness with NSGA-II (Non-dominated Sorting Genetic Algorithm II) optimizing 3 objectives simultaneously:

1. **Survival time** — how long the agent stays alive
2. **Kill count** — enemies destroyed  
3. **Powerup collection** — powerups gathered

This eliminates the need to manually weight fitness components and produces diverse strategies (aggressive fighters, cautious survivors, collectors).

---

## 3 Objectives

Currently `training_manager.gd` already tracks these as `score_from_kills`, `score_from_powerups`, and `score - score_from_kills - score_from_powerups` (survival score). We'll formalize these as separate objective values rather than summing into a single score.

| Objective | Source | Currently Tracked? |
|-----------|--------|--------------------|
| Survival time | `eval.scene.survival_time` or `eval.time` | ✅ As survival_score |
| Kill count | `eval.scene.score_from_kills` | ✅ |
| Powerup collection | `eval.scene.score_from_powerups` | ✅ |

---

## Algorithm: NSGA-II

### Key Functions in `evolution.gd`

#### 1. `non_dominated_sort(objectives: Array[Vector3]) -> Array[Array]`
- Input: Array of Vector3 (one per individual, each component = one objective)
- Output: Array of fronts, where front[0] = Pareto-optimal, front[1] = next best, etc.
- Algorithm: For each individual, count how many others dominate it. Front 0 = dominated by none.

```
Dominates(A, B): A is >= B on ALL objectives AND strictly > on at least one
```

**Complexity:** O(MN²) where M=objectives, N=population. Fine for N≤200.

#### 2. `crowding_distance(front: Array, objectives: Array[Vector3]) -> PackedFloat32Array`
- For each individual in a front, measure how spread out its neighbors are in objective space
- Boundary individuals get ∞ distance (always selected)
- Used to break ties within the same front — prefer diverse solutions

#### 3. `nsga2_select(population: Array, objectives: Array[Vector3], target_size: int) -> Array`
- Non-dominated sort → fronts
- Fill new population front by front
- When a front would overflow, sort by crowding distance descending, take top individuals
- Returns indices of selected parents

### Modified `evolve()` Flow

```
Current:
  sort by fitness → elitism → tournament selection → crossover/mutation

New:
  non_dominated_sort(objectives) → fronts
  fill new_pop with fronts until full
  last front: sort by crowding distance, take best
  crossover + mutation from selected pool
  elites = front[0] individuals (up to elite_count)
```

### Estimated Code Changes

| File | Changes | Lines |
|------|---------|-------|
| `evolution.gd` | Add NSGA-II functions, modify `evolve()` | ~150 new |
| `evolution.gd` | New `objectives` array replacing `fitness_scores` | ~20 modified |
| `training_manager.gd` | Store 3 objectives per individual instead of single fitness | ~30 modified |
| `training_manager.gd` | Update stats/history for multi-objective | ~40 modified |
| UI (pause overlay) | Pareto front scatter plot | ~80 new |

---

## Data Structures

```gdscript
# In evolution.gd — replace fitness_scores with:
var objective_scores: Array = []  # Array of Vector3 per individual
# Vector3(survival_time, kill_score, powerup_score)

# Pareto front tracking for visualization
var pareto_front: Array[Vector3] = []  # Current gen front 0

# In training_manager.gd — replace fitness_accumulator with:
var objective_accumulator: Dictionary = {}  
# {individual_index: [{survival, kills, powerups}, ...per seed]}
```

---

## Compatibility with Existing Features

### Curriculum Learning
- ✅ Compatible — curriculum controls arena difficulty, NSGA-II controls selection
- Advancement threshold changes from single avg fitness to: use **hypervolume** of Pareto front or a **reference point** metric
- Simplest: advance when median survival_time exceeds threshold (same as current but using one objective)

### Adaptive Mutation
- ✅ Keep — stagnation detection changes to track hypervolume instead of best fitness
- Hypervolume = volume dominated by Pareto front relative to a reference point

### Save/Load Population
- ⚠️ Needs update — must save objective scores alongside weights
- Backward-compatible: detect old format (no objectives) and fall back to single fitness

### Best Network Tracking
- Changes meaning: "best" = front 0 individual with highest crowding distance, OR user-selectable from Pareto front
- Keep `all_time_best` as the individual with highest summed objectives (backward compat)

---

## Pareto Front Visualization

Add a scatter plot to the pause overlay showing:
- X-axis: Kill score, Y-axis: Survival time (or any 2 of 3 objectives)
- Color: Powerup score (3rd objective as color gradient)
- Front 0 individuals highlighted/connected
- Toggle between objective pairs with keyboard

---

## Testing Strategy

1. **Unit test non_dominated_sort**: Known dominance relationships → verify fronts
2. **Unit test crowding_distance**: Known objective values → verify distances
3. **Integration test**: Run 3 generations, verify diverse strategies emerge
4. **Regression test**: Compare training curves single-objective vs NSGA-II
5. **Edge cases**: All identical fitness, single individual dominates all, population size 1

### Test file: `tests/test_nsga2.gd`

```gdscript
# Test cases for non_dominated_sort:
# Case 1: Clear dominance — A=(10,10,10), B=(5,5,5) → A in front 0, B in front 1
# Case 2: Non-dominated — A=(10,5,3), B=(5,10,3), C=(3,3,10) → all in front 0
# Case 3: Mixed — 5 individuals with known Pareto structure
# Case 4: All equal → all in front 0
# Case 5: Large population (100) with random objectives → verify front sizes sum to 100
```

---

## Implementation Phases

### Phase A: Core NSGA-II (ask for approval)
- [ ] `non_dominated_sort()` 
- [ ] `crowding_distance()`
- [ ] `nsga2_select()`
- [ ] Unit tests for all three

### Phase B: Integration (ask for approval)  
- [ ] Modify `evolve()` to use NSGA-II
- [ ] Update `training_manager.gd` objective tracking
- [ ] Update stats display
- [ ] Integration tests

### Phase C: Visualization (ask for approval)
- [ ] Pareto front scatter plot on pause screen
- [ ] Objective breakdown in stats
- [ ] Save/load compatibility

### Phase D: PR
- [ ] Create PR with full description
- [ ] Performance comparison data

---

## Blockers

- **`feature/curriculum-learning` must be merged to main first** — NSGA-II branch will be based on main after that merge
- Curriculum advancement logic needs updating for multi-objective (Phase B)
