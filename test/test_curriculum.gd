extends "res://test/test_base.gd"
## Tests for the curriculum learning system in training_manager.gd

var TrainingManagerScript = preload("res://training_manager.gd")


func run_tests() -> void:
    _test("curriculum_stages_are_valid", _test_stages_valid)
    _test("curriculum_initial_state", _test_initial_state)
    _test("curriculum_config_returns_stage_0", _test_config_stage_0)
    _test("curriculum_config_disabled_returns_empty", _test_config_disabled)
    _test("curriculum_no_advance_before_min_generations", _test_no_early_advance)
    _test("curriculum_advances_when_threshold_met", _test_advances_on_threshold)
    _test("curriculum_does_not_advance_below_threshold", _test_no_advance_below_threshold)
    _test("curriculum_does_not_advance_past_final_stage", _test_no_advance_past_final)
    _test("curriculum_resets_stagnation_on_advance", _test_resets_stagnation)
    _test("curriculum_label_format", _test_label_format)
    _test("curriculum_all_stages_have_required_keys", _test_stage_keys)
    _test("curriculum_arena_scale_monotonic", _test_arena_scale_monotonic)
    _test("curriculum_enemy_types_grow", _test_enemy_types_grow)
    _test("curriculum_final_stage_no_threshold", _test_final_stage)


func _create_manager() -> Node:
    ## Create a training manager instance for testing (not added to tree).
    var tm = TrainingManagerScript.new()
    # Don't call initialize() - we're testing curriculum logic in isolation
    return tm


func _test_stages_valid() -> void:
    var tm = _create_manager()
    assert_gt(tm.CURRICULUM_STAGES.size(), 0, "Should have at least 1 stage")
    assert_eq(tm.CURRICULUM_STAGES.size(), 5, "Should have exactly 5 stages")


func _test_initial_state() -> void:
    var tm = _create_manager()
    assert_eq(tm.curriculum_stage, 0, "Should start at stage 0")
    assert_eq(tm.curriculum_generations_at_stage, 0, "Should start with 0 gens at stage")
    assert_true(tm.curriculum_enabled, "Curriculum should be enabled by default")


func _test_config_stage_0() -> void:
    var tm = _create_manager()
    var config = tm.get_current_curriculum_config()
    assert_false(config.is_empty(), "Config should not be empty")
    assert_eq(config.arena_scale, 0.25, "Stage 0 arena scale should be 0.25")
    assert_true(config.enemy_types.has(0), "Stage 0 should have pawns (type 0)")
    assert_eq(config.enemy_types.size(), 1, "Stage 0 should only have pawns")


func _test_config_disabled() -> void:
    var tm = _create_manager()
    tm.curriculum_enabled = false
    var config = tm.get_current_curriculum_config()
    assert_true(config.is_empty(), "Disabled curriculum should return empty config")


func _test_no_early_advance() -> void:
    var tm = _create_manager()
    # Add high fitness but only 1 generation (need 3 minimum)
    tm.history_avg_fitness.append(99999.0)
    var advanced = tm.check_curriculum_advancement()
    assert_false(advanced, "Should not advance with only 1 generation")
    assert_eq(tm.curriculum_stage, 0, "Should still be at stage 0")
    assert_eq(tm.curriculum_generations_at_stage, 1, "Should have counted the generation")


func _test_advances_on_threshold() -> void:
    var tm = _create_manager()
    # Stage 0 threshold is 5000, min_generations is 3
    # Simulate 3 generations with high fitness
    tm.history_avg_fitness.append(6000.0)
    tm.check_curriculum_advancement()  # gen 1 at stage
    tm.history_avg_fitness.append(6000.0)
    tm.check_curriculum_advancement()  # gen 2 at stage
    tm.history_avg_fitness.append(6000.0)
    var advanced = tm.check_curriculum_advancement()  # gen 3 at stage
    assert_true(advanced, "Should advance when threshold met over 3 gens")
    assert_eq(tm.curriculum_stage, 1, "Should be at stage 1")
    assert_eq(tm.curriculum_generations_at_stage, 0, "Gens at stage should reset")


func _test_no_advance_below_threshold() -> void:
    var tm = _create_manager()
    # Stage 0 threshold is 5000
    tm.history_avg_fitness.append(2000.0)
    tm.check_curriculum_advancement()
    tm.history_avg_fitness.append(2000.0)
    tm.check_curriculum_advancement()
    tm.history_avg_fitness.append(2000.0)
    var advanced = tm.check_curriculum_advancement()
    assert_false(advanced, "Should not advance below threshold")
    assert_eq(tm.curriculum_stage, 0, "Should still be at stage 0")


func _test_no_advance_past_final() -> void:
    var tm = _create_manager()
    tm.curriculum_stage = tm.CURRICULUM_STAGES.size() - 1  # Final stage
    tm.history_avg_fitness.append(99999.0)
    tm.history_avg_fitness.append(99999.0)
    tm.history_avg_fitness.append(99999.0)
    var advanced = tm.check_curriculum_advancement()
    assert_false(advanced, "Should not advance past final stage")
    assert_eq(tm.curriculum_stage, tm.CURRICULUM_STAGES.size() - 1)


func _test_resets_stagnation() -> void:
    var tm = _create_manager()
    tm.generations_without_improvement = 8
    tm.best_avg_fitness = 3000.0
    # Force advancement
    tm.history_avg_fitness.append(6000.0)
    tm.check_curriculum_advancement()
    tm.history_avg_fitness.append(6000.0)
    tm.check_curriculum_advancement()
    tm.history_avg_fitness.append(6000.0)
    tm.check_curriculum_advancement()
    assert_eq(tm.generations_without_improvement, 0, "Stagnation should reset on advance")
    assert_eq(tm.best_avg_fitness, 0.0, "Best avg should reset on advance")


func _test_label_format() -> void:
    var tm = _create_manager()
    var label = tm.get_curriculum_label()
    assert_true(label.length() > 0, "Label should not be empty")
    assert_true("Stage 0" in label, "Label should contain stage number")
    assert_true("Nursery" in label, "Label should contain stage name")
    assert_true("25%" in label, "Label should contain arena scale")


func _test_stage_keys() -> void:
    var tm = _create_manager()
    var required_keys = [
        "arena_scale",
        "enemy_types",
        "powerup_types",
        "advancement_threshold",
        "min_generations",
        "label"
    ]
    for i in tm.CURRICULUM_STAGES.size():
        var stage = tm.CURRICULUM_STAGES[i]
        for key in required_keys:
            assert_true(stage.has(key), "Stage %d missing key: %s" % [i, key])


func _test_arena_scale_monotonic() -> void:
    var tm = _create_manager()
    var prev_scale = 0.0
    for i in tm.CURRICULUM_STAGES.size():
        var scale = tm.CURRICULUM_STAGES[i].arena_scale
        assert_gte(scale, prev_scale, "Arena scale should be non-decreasing at stage %d" % i)
        prev_scale = scale


func _test_enemy_types_grow() -> void:
    var tm = _create_manager()
    var prev_count = 0
    for i in tm.CURRICULUM_STAGES.size():
        var count = tm.CURRICULUM_STAGES[i].enemy_types.size()
        assert_gte(count, prev_count, "Enemy types should grow at stage %d" % i)
        prev_count = count


func _test_final_stage() -> void:
    var tm = _create_manager()
    var final = tm.CURRICULUM_STAGES[-1]
    assert_eq(final.advancement_threshold, 0.0, "Final stage should have no threshold")
    assert_eq(final.enemy_types.size(), 5, "Final stage should have all 5 enemy types")
