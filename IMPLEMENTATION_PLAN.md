# 🧬 EVOLVE: Detailed Implementation Plan

*Alfred, 2026-02-06. Ready for Arya's approval.*

## TL;DR: Start with Curriculum Learning
**First milestone:** Automated difficulty progression that cuts training time in half.
**Effort:** ~2-3 hours of focused coding
**Risk:** Low (just parameter changes, no architecture changes)

---

## Phase 1A: Curriculum Learning [RECOMMENDED START]

### What Changes
Transform the static "throw agents into chaos" training into progressive difficulty stages.

### File Changes Required
1. **`training_manager.gd`** — Add curriculum system (~80 new lines)
2. **`main.gd`** — Parameterize arena/enemy setup (modify 3 existing functions)
3. **Optional:** Add curriculum UI panel for monitoring

### Detailed Implementation

#### Step 1: Add Curriculum State Tracking
```gdscript
# Add to training_manager.gd after existing vars
var curriculum_stage: int = 0
var curriculum_generations_at_stage: int = 0
var curriculum_enabled: bool = true

const CURRICULUM_STAGES = [
    # stage_id, arena_size, enemy_types, powerup_types, advancement_threshold
    {"arena_scale": 0.25, "enemy_mask": ["pawn"], "powerup_mask": ["health"], "median_survival_threshold": 30.0},
    {"arena_scale": 0.5, "enemy_mask": ["pawn", "knight"], "powerup_mask": ["health", "speed", "shield"], "median_survival_threshold": 45.0},
    {"arena_scale": 0.75, "enemy_mask": ["pawn", "knight", "bishop"], "powerup_mask": ["health", "speed", "shield", "spread", "multi"], "median_survival_threshold": 60.0},
    {"arena_scale": 1.0, "enemy_mask": ["pawn", "knight", "bishop", "rook"], "powerup_mask": ["all"], "median_survival_threshold": 45.0},
    {"arena_scale": 1.0, "enemy_mask": ["all"], "powerup_mask": ["all"], "median_survival_threshold": 0.0}  # Final stage
]
```

#### Step 2: Modify Arena Setup
```gdscript
# In main.gd, modify existing function
func set_training_mode(training: bool, curriculum_config: Dictionary = {}):
    is_training = training
    if training and not curriculum_config.is_empty():
        # Scale arena
        var scale = curriculum_config.get("arena_scale", 1.0)
        ARENA_WIDTH = int(3840 * scale)
        ARENA_HEIGHT = int(3840 * scale)
        
        # Filter enemy types
        allowed_enemy_types = curriculum_config.get("enemy_mask", ["all"])
        allowed_powerup_types = curriculum_config.get("powerup_mask", ["all"])
```

#### Step 3: Add Advancement Logic
```gdscript
# In training_manager.gd, add to generation complete handler
func check_curriculum_advancement():
    if not curriculum_enabled or curriculum_stage >= CURRICULUM_STAGES.size() - 1:
        return false
        
    curriculum_generations_at_stage += 1
    
    # Need at least 3 generations to assess median performance
    if curriculum_generations_at_stage < 3:
        return false
    
    var current_stage = CURRICULUM_STAGES[curriculum_stage]
    var threshold = current_stage.median_survival_threshold
    
    # Get last 3 generations of survival times
    var recent_survivals = []
    # ... collect survival data from history ...
    
    var median_survival = get_median(recent_survivals)
    
    if median_survival >= threshold:
        curriculum_stage += 1
        curriculum_generations_at_stage = 0
        print("🎓 CURRICULUM ADVANCEMENT: Stage %d → %d (median survival: %.1fs)" % [curriculum_stage - 1, curriculum_stage, median_survival])
        return true
    
    return false
```

### Testing Strategy
1. **Smoke test:** Does stage 1 (tiny arena, pawns only) work?
2. **Advancement test:** Do agents actually progress through stages?
3. **Performance test:** Compare curriculum vs non-curriculum training on same config

### Expected Results
- Training time to 50k fitness: **60-90 min → 30-45 min**
- More consistent learning curves (no early plateau)
- Higher quality final networks

### Approval Checkpoints
- [ ] **Code review:** Show curriculum logic before implementation
- [ ] **Stage 1 demo:** Single stage working correctly
- [ ] **Full pipeline:** Complete 5-stage progression
- [ ] **Performance comparison:** A/B test vs current method

---

## Phase 1B: NSGA-II Multi-Objective [AFTER CURRICULUM]

### What Changes
Replace single fitness value with 3-objective optimization:
1. Survival time
2. Kill count  
3. Powerup collection

### File Changes Required
1. **`evolution.gd`** — Replace tournament selection with NSGA-II (~150 new lines)
2. **`training_manager.gd`** — Track 3 fitness components separately
3. **UI updates** — Show Pareto front visualization

### Key Functions to Implement
```gdscript
# In evolution.gd
func non_dominated_sort(population: Array) -> Array:
    # Returns array of fronts [[front0_indices], [front1_indices], ...]

func calculate_crowding_distance(front: Array, objectives: Array) -> Array:
    # Returns crowding distance for each individual in front

func nsga2_selection(population: Array, objectives: Array, target_size: int) -> Array:
    # NSGA-II environmental selection
```

### Expected Results
- **Diverse strategies:** Aggressive fighters, cautious survivors, collectors
- **No fitness weight tuning:** Eliminates the "how to balance survival vs kills" problem
- **Better final performance:** Pareto fronts often contain superior solutions

### Approval Checkpoints
- [ ] **Algorithm review:** NSGA-II implementation correctness
- [ ] **Objective tracking:** 3 fitness components properly logged
- [ ] **Strategy diversity:** Visually distinct agent behaviors
- [ ] **Performance comparison:** Best Pareto solutions vs current single-objective

---

## Phase 2: MAP-Elites + Memory [BIGGER COMMITMENT]

### MAP-Elites Behavioral Archive

#### File Structure
```
ai/
├── map_elites.gd          # Archive management + behavior calculation
├── map_elites_config.gd   # Grid size, behavior descriptors
└── map_elites_ui.gd       # 20x20 grid visualization (optional)
```

#### Core Algorithm
```gdscript
# map_elites.gd
class_name MapElites

var archive: Dictionary = {}  # Vector2i → {genome, fitness, behavior}
var grid_size: int = 20

func calculate_behavior(agent_stats: Dictionary) -> Vector2:
    # Aggression: % time moving toward vs away from enemies
    var aggression = agent_stats.approach_time / agent_stats.total_time
    
    # Collection focus: powerups per minute
    var collection_rate = agent_stats.powerups_collected / (agent_stats.survival_time / 60.0)
    
    return Vector2(aggression, collection_rate)

func add_to_archive(genome, behavior: Vector2, fitness: float):
    var bin = Vector2i(int(behavior.x * grid_size), int(behavior.y * grid_size))
    bin = bin.clamp(Vector2i.ZERO, Vector2i(grid_size - 1, grid_size - 1))
    
    if not archive.has(bin) or archive[bin].fitness < fitness:
        archive[bin] = {"genome": genome, "fitness": fitness, "behavior": behavior}
        return true  # Added to archive
    return false
```

### Elman Memory Networks

#### Minimal Change
```gdscript
# In neural_network.gd, modify constructor
func _init(inputs: int, hidden: int, outputs: int, use_memory: bool = false):
    input_size = inputs + (hidden if use_memory else 0)  # Concat prev hidden
    # ... rest unchanged ...
    
var prev_hidden: PackedFloat32Array = []

func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
    var full_input = inputs.duplicate()
    if prev_hidden.size() > 0:
        full_input.append_array(prev_hidden)
    
    # Standard forward pass...
    prev_hidden = hidden_values.duplicate()
    return output_values
```

### Approval Checkpoints
- [ ] **MAP-Elites proof of concept:** 5x5 grid with dummy behaviors
- [ ] **Behavior calculation:** Aggression/collection metrics make sense
- [ ] **Archive visualization:** Can browse the behavioral zoo
- [ ] **Memory networks:** Agents show temporal learning
- [ ] **Integration test:** MAP-Elites + Elman networks + curriculum

---

## Implementation Priority Queue

### Immediate (This Week)
1. **Curriculum Learning** — Biggest bang for buck, low risk
2. **Better W&B metrics** — Track curriculum stage, survival times
3. **Code cleanup** — Document existing systems before adding complexity

### Short Term (Next 2 Weeks)  
1. **NSGA-II** — If curriculum works well
2. **MAP-Elites planning** — Finalize behavior descriptors

### Medium Term (Next Month)
1. **MAP-Elites implementation**
2. **Elman memory networks**
3. **NEAT planning** — This is the big architectural change

### Long Term (2-3 Months)
1. **NEAT implementation**
2. **Co-evolution experiments**  
3. **Live sandbox vision**

---

## Decision Points for Arya

### ✅ **Green Light Recommendations**
- **Start with Curriculum Learning:** Low risk, high reward, 2-3 hour time investment
- **Add better metrics:** Track survival time distributions, not just fitness
- **A/B test everything:** Keep current training as baseline comparison

### ⚠️ **Yellow Light (Discuss First)**
- **NSGA-II:** More complex, changes core evolution loop
- **MAP-Elites:** Significant UI work for proper visualization
- **Memory networks:** Increases compute cost ~30% (bigger input layer)

### 🛑 **Red Light (Later)**
- **NEAT:** Major architectural overhaul, save for when current system is polished
- **Co-evolution:** Requires NEAT or similar topology evolution first
- **Live sandbox:** Product vision, not research

---

## Next Steps

**If approved for Curriculum Learning:**
1. I'll implement the basic curriculum system (training_manager.gd changes)
2. Test stage 1 (small arena, pawns only) to verify it works
3. Run a comparison: current training vs curriculum on identical sweep config
4. Report results and get approval for stages 2-5

**Timeline:** 2-3 focused work sessions to have a working curriculum system.

Ready for your decision, Sir Bruce Wayne. 🎩