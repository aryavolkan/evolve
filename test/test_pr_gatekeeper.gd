extends "res://test/test_base.gd"
## Tests for PR gatekeeper integration infrastructure.
## Validates that the gameplay test runner's dependencies are available
## and that the training API surface used by the gatekeeper works correctly.

var curriculum_manager_script
var stats_tracker_script


func run_tests() -> void:
    curriculum_manager_script = load("res://ai/curriculum_manager.gd")
    stats_tracker_script = load("res://ai/stats_tracker.gd")
    _test("curriculum_manager_stages_available", _test_curriculum_stages)
    _test("curriculum_manager_config_has_required_keys", _test_curriculum_config_keys)
    _test("stats_tracker_record_and_retrieve", _test_stats_tracker_roundtrip)
    _test("stats_tracker_multi_seed_averaging", _test_stats_tracker_averaging)
    _test("stats_tracker_generation_recording", _test_stats_tracker_generation)
    _test("stats_tracker_behavior_tracking", _test_stats_tracker_behavior)
    _test("gameplay_runner_scenario_list", _test_scenario_list)
    _test("compare_reports_script_exists", _test_compare_script_exists)
    _test("pr_gatekeeper_script_exists", _test_gatekeeper_script_exists)


func _test_curriculum_stages() -> void:
    assert_true(curriculum_manager_script != null, "CurriculumManager script loads")
    assert_gte(
        curriculum_manager_script.STAGES.size(),
        5.0,
        "At least 5 curriculum stages (got %d)" % curriculum_manager_script.STAGES.size()
    )


func _test_curriculum_config_keys() -> void:
    var required_keys := ["arena_scale", "enemy_types", "powerup_types", "label"]
    for stage_config in curriculum_manager_script.STAGES:
        for key in required_keys:
            assert_true(stage_config.has(key), "Stage config has key '%s'" % key)


func _test_stats_tracker_roundtrip() -> void:
    var st = stats_tracker_script.new()

    st.record_eval_result(0, 500.0, 200.0, 150.0, 150.0)
    assert_approx(st.get_avg_fitness(0), 500.0, 0.1, "Single eval fitness")

    st.record_eval_result(0, 300.0, 100.0, 100.0, 100.0)
    assert_approx(st.get_avg_fitness(0), 400.0, 0.1, "Average of two evals")


func _test_stats_tracker_averaging() -> void:
    var st = stats_tracker_script.new()

    # Simulate 3 seeds for individual 0
    st.record_eval_result(0, 100.0, 50.0, 30.0, 20.0)
    st.record_eval_result(0, 200.0, 80.0, 60.0, 60.0)
    st.record_eval_result(0, 300.0, 120.0, 90.0, 90.0)

    assert_approx(st.get_avg_fitness(0), 200.0, 0.1, "Avg fitness across 3 seeds")

    # Check objectives
    var avg_obj: Vector3 = st.get_avg_objectives(0)
    # Objectives: Vector3(survival, kills, powerups)
    assert_approx(avg_obj.x, (20.0 + 60.0 + 90.0) / 3.0, 0.1, "Avg survival objective")
    assert_approx(avg_obj.y, (50.0 + 80.0 + 120.0) / 3.0, 0.1, "Avg kill objective")


func _test_stats_tracker_generation() -> void:
    var st = stats_tracker_script.new()

    st.record_eval_result(0, 100.0, 40.0, 30.0, 30.0)
    st.record_eval_result(1, 200.0, 80.0, 60.0, 60.0)

    var breakdown = st.record_generation(200.0, 150.0, 100.0, 2, 1)
    assert_gt(breakdown.avg_kill_score, 0.0, "Kill score recorded")
    assert_eq(st.history_best_fitness.size(), 1, "History has one entry")
    assert_approx(st.history_best_fitness[0], 200.0, 0.1, "Best fitness recorded")


func _test_stats_tracker_behavior() -> void:
    var st = stats_tracker_script.new()

    st.record_behavior(0, 5.0, 3.0, 30.0)
    st.record_behavior(0, 7.0, 1.0, 20.0)

    var avg_beh = st.get_avg_behavior(0)
    assert_approx(avg_beh.kills, 6.0, 0.1, "Avg kills")
    assert_approx(avg_beh.powerups_collected, 2.0, 0.1, "Avg powerups")
    assert_approx(avg_beh.survival_time, 25.0, 0.1, "Avg survival time")


func _test_scenario_list() -> void:
    # The gameplay_test_runner.gd defines scenarios — verify the key ones exist
    # by checking the file can be loaded (it extends SceneTree, so we can't instantiate here)
    var script = load("res://test/integration/gameplay_test_runner.gd")
    assert_true(script != null, "Gameplay test runner script loads")


func _test_compare_script_exists() -> void:
    assert_true(
        FileAccess.file_exists("res://test/integration/compare_reports.py"),
        "compare_reports.py exists"
    )


func _test_gatekeeper_script_exists() -> void:
    assert_true(
        FileAccess.file_exists("res://test/integration/pr_gatekeeper.sh"), "pr_gatekeeper.sh exists"
    )
