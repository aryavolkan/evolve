extends RefCounted
## Manages curriculum learning — progressive difficulty staging.
## Extracted from training_manager.gd to reduce its responsibility.

signal stage_advanced(old_stage: int, new_stage: int)

var enabled: bool = true
var stage: int = 0
var generations_at_stage: int = 0

const STAGES: Array[Dictionary] = [
    # Stage 0: Tiny arena, pawns only, health powerups only
    {"arena_scale": 0.25, "enemy_types": [0], "powerup_types": [0, 6],
    "advancement_threshold": 5000.0, "min_generations": 3, "label": "Nursery"},
    # Stage 1: Small arena, pawns + knights, basic powerups
    {"arena_scale": 0.5, "enemy_types": [0, 1], "powerup_types": [0, 2, 6],
    "advancement_threshold": 10000.0, "min_generations": 3, "label": "Elementary"},
    # Stage 2: Medium arena, add bishops, most powerups
    {"arena_scale": 0.75, "enemy_types": [0, 1, 2], "powerup_types": [0, 1, 2, 4, 5, 6],
    "advancement_threshold": 15000.0, "min_generations": 3, "label": "Intermediate"},
    # Stage 3: Full arena, all except queen, all powerups
    {"arena_scale": 1.0, "enemy_types": [0, 1, 2, 3], "powerup_types": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    "advancement_threshold": 12000.0, "min_generations": 3, "label": "Advanced"},
    # Stage 4: Full arena, all enemy types, all powerups (final)
    {"arena_scale": 1.0, "enemy_types": [0, 1, 2, 3, 4], "powerup_types": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    "advancement_threshold": 0.0, "min_generations": 0, "label": "Final"},
]


func reset() -> void:
    ## Reset curriculum to initial state.
    stage = 0
    generations_at_stage = 0


func get_current_config() -> Dictionary:
    ## Return the curriculum config for the current stage.
    ## Returns empty dict if curriculum is disabled.
    if not enabled:
        return {}
    if stage < 0 or stage >= STAGES.size():
        return {}
    return STAGES[stage]


func check_advancement(history_avg_fitness: Array[float]) -> bool:
    ## Check if agents should advance to the next curriculum stage.
    ## Called after each generation completes. Returns true if advanced.
    if not enabled:
        return false
    if stage >= STAGES.size() - 1:
        return false  # Already at final stage

    generations_at_stage += 1

    var stage_config = STAGES[stage]
    var min_gens: int = stage_config.get("min_generations", 3)

    # Need minimum generations to assess performance
    if generations_at_stage < min_gens:
        return false

    var threshold: float = stage_config.get("advancement_threshold", 0.0)
    if threshold <= 0.0:
        return false  # No threshold = stay here

    # Check rolling average fitness over last min_gens generations
    if history_avg_fitness.size() < min_gens:
        return false

    var recent_avg: float = 0.0
    for i in range(min_gens):
        recent_avg += history_avg_fitness[history_avg_fitness.size() - 1 - i]
    recent_avg /= min_gens

    if recent_avg >= threshold:
        var old_stage = stage
        stage += 1
        generations_at_stage = 0
        print("🎓 CURRICULUM ADVANCEMENT: Stage %d (%s) → Stage %d (%s) | rolling avg: %.0f ≥ %.0f" % [
            old_stage, STAGES[old_stage].label,
            stage, STAGES[stage].label,
            recent_avg, threshold
        ])
        stage_advanced.emit(old_stage, stage)
        return true

    return false


func get_label() -> String:
    ## Get a display label for the current curriculum stage.
    if not enabled:
        return ""
    var config = get_current_config()
    if config.is_empty():
        return ""
    return "Stage %d/%d: %s (%.0f%%)" % [
        stage, STAGES.size() - 1,
        config.get("label", "?"),
        config.get("arena_scale", 1.0) * 100.0
    ]
