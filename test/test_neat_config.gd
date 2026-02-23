extends "res://test/test_base.gd"

## Tests for NeatConfig: hyperparameter storage and duplication.

const NeatConfigClass = preload("res://evolve-core/ai/neat/neat_config.gd")


func _run_tests() -> void:
    _test("Default config has valid network dimensions", _test_default_dimensions)
    _test("Default config has valid mutation rates", _test_default_mutation_rates)
    _test("Default config has valid speciation params", _test_default_speciation)
    _test("Default config has valid reproduction params", _test_default_reproduction)
    _test("Duplicate creates independent copy", _test_duplicate_independent)
    _test("Duplicate preserves all values", _test_duplicate_values)
    _test("Config values are mutable", _test_mutable)


func _test_default_dimensions():
    var cfg = NeatConfigClass.new()
    assert_eq(cfg.input_count, 86, "Default input count matches sensor.gd TOTAL_INPUTS")
    assert_eq(cfg.output_count, 6, "Default output count matches action space")


func _test_default_mutation_rates():
    var cfg = NeatConfigClass.new()
    assert_gt(cfg.weight_mutate_rate, 0.0, "Weight mutation rate > 0")
    assert_lte(cfg.weight_mutate_rate, 1.0, "Weight mutation rate <= 1")
    assert_gt(cfg.add_node_rate, 0.0, "Add node rate > 0")
    assert_lt(cfg.add_node_rate, 1.0, "Add node rate < 1 (should be rare)")
    assert_gt(cfg.add_connection_rate, 0.0, "Add connection rate > 0")
    assert_gt(cfg.weight_perturb_strength, 0.0, "Perturb strength > 0")


func _test_default_speciation():
    var cfg = NeatConfigClass.new()
    assert_gt(cfg.compatibility_threshold, 0.0, "Compatibility threshold > 0")
    assert_gt(cfg.c1_excess, 0.0, "Excess coefficient > 0")
    assert_gt(cfg.c2_disjoint, 0.0, "Disjoint coefficient > 0")
    assert_gt(cfg.c3_weight_diff, 0.0, "Weight diff coefficient > 0")
    assert_gt(cfg.target_species_count, 1, "Target species > 1")


func _test_default_reproduction():
    var cfg = NeatConfigClass.new()
    assert_gt(cfg.population_size, 0, "Population size > 0")
    assert_gt(cfg.elite_fraction, 0.0, "Elite fraction > 0")
    assert_lt(cfg.elite_fraction, 1.0, "Elite fraction < 1")
    assert_gt(cfg.survival_fraction, 0.0, "Survival fraction > 0")
    assert_lte(cfg.survival_fraction, 1.0, "Survival fraction <= 1")
    assert_gt(cfg.crossover_rate, 0.0, "Crossover rate > 0")
    assert_gt(cfg.stagnation_threshold, 0, "Stagnation threshold > 0")
    assert_gte(cfg.min_species_protected, 1, "At least 1 species protected")


func _test_duplicate_independent():
    var cfg = NeatConfigClass.new()
    var copy = cfg.duplicate()

    copy.input_count = 999
    copy.weight_mutate_rate = 0.001
    copy.compatibility_threshold = 99.9

    assert_eq(cfg.input_count, 86, "Original input_count unchanged")
    assert_approx(cfg.weight_mutate_rate, 0.8, 0.001, "Original weight_mutate_rate unchanged")
    assert_approx(cfg.compatibility_threshold, 3.0, 0.001, "Original threshold unchanged")


func _test_duplicate_values():
    var cfg = NeatConfigClass.new()
    cfg.input_count = 42
    cfg.add_node_rate = 0.99
    cfg.parsimony_coefficient = 0.05

    var copy = cfg.duplicate()
    assert_eq(copy.input_count, 42, "Duplicated input_count matches")
    assert_approx(copy.add_node_rate, 0.99, 0.001, "Duplicated add_node_rate matches")
    assert_approx(copy.parsimony_coefficient, 0.05, 0.001, "Duplicated parsimony matches")


func _test_mutable():
    var cfg = NeatConfigClass.new()
    cfg.population_size = 500
    cfg.initial_connection_fraction = 0.5
    assert_eq(cfg.population_size, 500, "Population size updated")
    assert_approx(cfg.initial_connection_fraction, 0.5, 0.001, "Connection fraction updated")
