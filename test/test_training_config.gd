extends "res://test/test_base.gd"
## Tests for ai/training_config.gd — centralized hyperparameters and sweep config.

var TrainingConfigScript = preload("res://ai/training_config.gd")


func _run_tests() -> void:
    print("\n[TrainingConfig Tests]")

    _test("default_values_reasonable", _test_default_values_reasonable)
    _test("path_constants_use_user_directory", _test_path_constants_use_user_directory)
    _test("path_constants_correct_extensions", _test_path_constants_correct_extensions)
    _test("load_from_sweep_sets_values", _test_load_from_sweep_sets_values)
    _test("load_from_sweep_worker_id_empty", _test_load_from_sweep_worker_id_empty)
    _test("get_metrics_path_default", _test_get_metrics_path_default)
    _test("get_metrics_path_with_worker", _test_get_metrics_path_with_worker)
    _test("get_raw_key_missing", _test_get_raw_missing_key)


func _test_default_values_reasonable() -> void:
    var cfg = TrainingConfigScript.new()
    assert_eq(cfg.population_size, 150, "Default pop size should be 150")
    assert_eq(cfg.max_generations, 100, "Default max gen should be 100")
    assert_eq(cfg.evals_per_individual, 2, "Default evals per individual should be 2")
    assert_eq(cfg.hidden_size, 80, "Default hidden size should be 80")
    assert_eq(cfg.elite_count, 20, "Default elite count should be 20")
    assert_approx(cfg.mutation_rate, 0.30, 0.001, "Default mutation rate should be 0.30")
    assert_approx(cfg.mutation_strength, 0.09, 0.001, "Default mutation strength should be 0.09")
    assert_approx(cfg.crossover_rate, 0.73, 0.001, "Default crossover rate should be 0.73")
    assert_approx(cfg.time_scale, 16.0, 0.001, "Default time scale should be 16.0")
    assert_eq(cfg.parallel_count, 20, "Default parallel count should be 20")
    assert_false(cfg.use_neat, "NEAT should be off by default")
    assert_false(cfg.use_nsga2, "NSGA-II should be off by default")
    assert_false(cfg.use_memory, "Memory should be off by default")
    assert_true(cfg.use_map_elites, "MAP-Elites should be on by default")
    assert_true(cfg.curriculum_enabled, "Curriculum should be enabled by default")
    assert_eq(cfg.map_elites_grid_size, 20, "Default MAP-Elites grid size should be 20")


func _test_path_constants_use_user_directory() -> void:
    assert_true(
        TrainingConfigScript.BEST_NETWORK_PATH.begins_with("user://"),
        "Best network path should use user://"
    )
    assert_true(
        TrainingConfigScript.POPULATION_PATH.begins_with("user://"),
        "Population path should use user://"
    )
    assert_true(
        TrainingConfigScript.SWEEP_CONFIG_PATH.begins_with("user://"),
        "Sweep config path should use user://"
    )
    assert_true(
        TrainingConfigScript.METRICS_PATH.begins_with("user://"), "Metrics path should use user://"
    )
    assert_true(
        TrainingConfigScript.ENEMY_POPULATION_PATH.begins_with("user://"),
        "Enemy pop path should use user://"
    )
    assert_true(
        TrainingConfigScript.ENEMY_HOF_PATH.begins_with("user://"),
        "Enemy HoF path should use user://"
    )
    assert_true(
        TrainingConfigScript.MIGRATION_POOL_DIR.begins_with("user://"),
        "Migration pool dir should use user://"
    )


func _test_path_constants_correct_extensions() -> void:
    assert_true(
        TrainingConfigScript.BEST_NETWORK_PATH.ends_with(".nn"),
        "Network file should have .nn extension"
    )
    assert_true(
        TrainingConfigScript.POPULATION_PATH.ends_with(".evo"),
        "Population file should have .evo extension"
    )
    assert_true(
        TrainingConfigScript.SWEEP_CONFIG_PATH.ends_with(".json"),
        "Sweep config should have .json extension"
    )
    assert_true(
        TrainingConfigScript.METRICS_PATH.ends_with(".json"),
        "Metrics file should have .json extension"
    )


func _test_load_from_sweep_sets_values() -> void:
    # After load_from_sweep, values should come from config or fallbacks
    var cfg = TrainingConfigScript.new()
    cfg.load_from_sweep(200, 50)
    # Values should be set (either from file or fallback)
    assert_gt(cfg.population_size, 0, "Pop size should be positive after load")
    assert_gt(cfg.max_generations, 0, "Max gen should be positive after load")
    assert_gt(cfg.hidden_size, 0, "Hidden size should be positive after load")
    assert_gt(cfg.mutation_rate, 0.0, "Mutation rate should be positive after load")


func _test_load_from_sweep_worker_id_empty() -> void:
    # Worker ID should be empty if no --worker-id= arg
    var cfg = TrainingConfigScript.new()
    cfg.load_from_sweep(75, 25)
    # In test mode, no --worker-id= arg is passed, so worker_id stays empty
    assert_eq(cfg.worker_id, "", "Worker ID should be empty without --worker-id arg")


func _test_get_metrics_path_default() -> void:
    var cfg = TrainingConfigScript.new()
    assert_eq(
        cfg.get_metrics_path(),
        "user://metrics.json",
        "Default metrics path should be user://metrics.json"
    )


func _test_get_metrics_path_with_worker() -> void:
    var cfg = TrainingConfigScript.new()
    cfg.worker_id = "worker_42"
    assert_eq(
        cfg.get_metrics_path(),
        "user://metrics_worker_42.json",
        "Worker metrics path should include worker ID"
    )


func _test_get_raw_missing_key() -> void:
    var cfg = TrainingConfigScript.new()
    assert_null(cfg.get_raw("nonexistent_key"), "Missing key should return null")
    assert_eq(
        cfg.get_raw("nonexistent_key", 42), 42, "Missing key with default should return default"
    )
