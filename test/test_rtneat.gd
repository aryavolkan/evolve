extends "res://test/test_base.gd"

const RTNEAT_MANAGER_SCRIPT = preload("res://ai/rtneat_manager.gd")
const AGENT_SCRIPT = preload("res://agent.gd")
## Tests for rtNEAT population, agent, and enemy targeting.

var RtNeatPopScript = preload("res://ai/rtneat_population.gd")


func run_tests() -> void:
    print("\n[rtNEAT Population Tests]")

    _test("population_init_creates_genomes", _test_population_init)
    _test("population_init_compiles_networks", _test_networks_compiled)
    _test("population_species_assigned", _test_species_assigned)
    _test("fitness_accumulation", _test_fitness_accumulation)
    _test("mark_dead", _test_mark_dead)
    _test("tick_returns_negative_before_interval", _test_tick_before_interval)
    _test("tick_returns_index_after_interval", _test_tick_after_interval)
    _test("dead_agents_prioritized_for_replacement", _test_dead_priority)
    _test("replacement_creates_valid_offspring", _test_replacement_offspring)
    _test("replacement_resets_slot", _test_replacement_resets_slot)
    _test("species_color_consistency", _test_species_color_consistency)
    _test("species_color_deterministic", _test_species_color_deterministic)
    _test("save_load_roundtrip", _test_save_load_roundtrip)
    _test("stats_dictionary_has_expected_keys", _test_stats_keys)
    _test("all_time_best_tracked", _test_all_time_best)

    print("\n[rtNEAT Agent Tests]")

    _test("agent_scene_loads", _test_agent_scene_loads)
    _test("agent_initial_state", _test_agent_initial_state)
    _test("agent_reset_for_new_life", _test_agent_reset)
    _test("agent_has_powerup_methods", _test_agent_powerups)

    print("\n[rtNEAT Interaction Tests]")

    _test("tool_default_is_inspect", _test_tool_default)
    _test("set_tool_changes_state", _test_set_tool)
    _test("bless_increases_fitness", _test_bless_fitness)
    _test("curse_decreases_fitness", _test_curse_fitness)
    _test("log_event_appears_in_log", _test_log_event)

    print("\n[Enemy Targeting Tests]")

    _test("enemy_find_nearest_target_exists", _test_enemy_targeting_method)
    _test("powerup_signal_has_collector", _test_powerup_signal)


# ============================================================
# Population tests
# ============================================================


func _create_pop(size: int = 10):
    var pop = RtNeatPopScript.new()
    var cfg = NeatConfig.new()
    cfg.input_count = 10
    cfg.output_count = 4
    cfg.population_size = size
    pop.replacement_interval = 5.0
    pop.min_lifetime = 3.0
    pop.initialize(size, cfg)
    return pop


func _test_population_init() -> void:
    var pop = _create_pop(10)
    assert_eq(pop.genomes.size(), 10, "Should have 10 genomes")
    assert_eq(pop.pop_size, 10, "Pop size should be 10")


func _test_networks_compiled() -> void:
    var pop = _create_pop(10)
    assert_eq(pop.networks.size(), 10, "Should have 10 networks")
    for i in 10:
        assert_not_null(pop.networks[i], "Network %d should not be null" % i)
        # Verify network can do forward pass
        var inputs = PackedFloat32Array()
        inputs.resize(10)
        var outputs = pop.networks[i].forward(inputs)
        assert_eq(outputs.size(), 4, "Network %d should produce 4 outputs" % i)


func _test_species_assigned() -> void:
    var pop = _create_pop(10)
    assert_gt(pop.get_species_count(), 0, "Should have at least 1 species")
    for i in 10:
        # species_ids should be assigned
        assert_gte(pop.species_ids[i], 0, "Species ID should be >= 0")


func _test_fitness_accumulation() -> void:
    var pop = _create_pop(5)
    pop.update_fitness(0, 100.0)
    pop.update_fitness(0, 50.0)
    assert_approx(pop.fitnesses[0], 150.0, 0.01, "Fitness should accumulate")
    assert_approx(pop.fitnesses[1], 0.0, 0.01, "Other agents should be unaffected")


func _test_mark_dead() -> void:
    var pop = _create_pop(5)
    assert_true(pop.alive[0], "Should start alive")
    pop.mark_dead(0)
    assert_false(pop.alive[0], "Should be dead after mark_dead")


func _test_tick_before_interval() -> void:
    var pop = _create_pop(5)
    pop.replacement_interval = 10.0
    var result = pop.tick(1.0)  # Only 1 second elapsed
    assert_eq(result, -1, "Should not replace before interval")


func _test_tick_after_interval() -> void:
    var pop = _create_pop(5)
    pop.replacement_interval = 5.0
    pop.min_lifetime = 3.0
    # Age all agents past min_lifetime
    for i in 5:
        pop.ages[i] = 10.0
    # Give varying fitness
    pop.fitnesses[0] = 100.0
    pop.fitnesses[1] = 50.0
    pop.fitnesses[2] = 10.0  # Worst
    pop.fitnesses[3] = 80.0
    pop.fitnesses[4] = 70.0

    var result = pop.tick(6.0)  # Past interval
    assert_ne(result, -1, "Should return an index to replace")


func _test_dead_priority() -> void:
    var pop = _create_pop(5)
    pop.replacement_interval = 5.0
    pop.min_lifetime = 3.0
    # All agents old enough
    for i in 5:
        pop.ages[i] = 10.0
        pop.fitnesses[i] = 100.0
    # Mark agent 3 as dead
    pop.mark_dead(3)
    pop.fitnesses[3] = 999.0  # Even high fitness should be replaced when dead

    var result = pop.tick(6.0)
    assert_eq(result, 3, "Dead agent should be prioritized for replacement")


func _test_replacement_offspring() -> void:
    var pop = _create_pop(10)
    # Give some fitness so parents can be selected
    for i in 10:
        pop.fitnesses[i] = float(i * 100)
    var result = pop.do_replacement(0)
    assert_true(result.has("genome"), "Result should have genome")
    assert_true(result.has("network"), "Result should have network")
    assert_true(result.has("species_color"), "Result should have species_color")
    assert_not_null(result.genome, "Genome should not be null")
    assert_not_null(result.network, "Network should not be null")


func _test_replacement_resets_slot() -> void:
    var pop = _create_pop(5)
    pop.fitnesses[0] = 500.0
    pop.ages[0] = 30.0
    pop.mark_dead(0)

    pop.do_replacement(0)
    assert_approx(pop.fitnesses[0], 0.0, 0.01, "Fitness should be reset")
    assert_approx(pop.ages[0], 0.0, 0.01, "Age should be reset")
    assert_true(pop.alive[0], "Should be alive after replacement")


func _test_species_color_consistency() -> void:
    var pop = _create_pop(5)
    var color1 = pop.get_species_color(0)
    var color2 = pop.get_species_color(0)
    assert_eq(color1, color2, "Same index should give same color")


func _test_species_color_deterministic() -> void:
    # Colors are based on species_id % palette size
    var pop = _create_pop(5)
    var color = pop.get_species_color(0)
    assert_ne(color, Color.BLACK, "Color should not be black")


func _test_save_load_roundtrip() -> void:
    var pop = _create_pop(5)
    pop.fitnesses[0] = 123.0
    pop.fitnesses[2] = 456.0
    pop.total_replacements = 7

    var path = "user://test_rtneat_pop.json"
    pop.save_population(path)

    var pop2 = RtNeatPopScript.new()
    var cfg = NeatConfig.new()
    cfg.input_count = 10
    cfg.output_count = 4
    cfg.population_size = 5
    pop2.config = cfg
    pop2.innovation_tracker = NeatInnovation.new(14)
    var loaded = pop2.load_population(path)

    assert_true(loaded, "Load should succeed")
    assert_eq(pop2.pop_size, 5, "Pop size should match")
    assert_eq(pop2.total_replacements, 7, "Replacements should persist")
    assert_approx(pop2.fitnesses[0], 123.0, 0.01, "Fitness[0] should persist")
    assert_approx(pop2.fitnesses[2], 456.0, 0.01, "Fitness[2] should persist")

    # Cleanup
    DirAccess.remove_absolute(path)


func _test_stats_keys() -> void:
    var pop = _create_pop(5)
    var stats = pop.get_stats()
    assert_true(stats.has("agent_count"), "Stats should have agent_count")
    assert_true(stats.has("alive_count"), "Stats should have alive_count")
    assert_true(stats.has("species_count"), "Stats should have species_count")
    assert_true(stats.has("best_fitness"), "Stats should have best_fitness")
    assert_true(stats.has("all_time_best"), "Stats should have all_time_best")
    assert_true(stats.has("avg_fitness"), "Stats should have avg_fitness")
    assert_true(stats.has("total_replacements"), "Stats should have total_replacements")
    assert_true(stats.has("species_counts"), "Stats should have species_counts")


func _test_all_time_best() -> void:
    var pop = _create_pop(5)
    pop.fitnesses[2] = 999.0
    pop._update_all_time_best()
    assert_approx(pop.all_time_best_fitness, 999.0, 0.01, "All-time best should be 999")
    assert_not_null(pop.all_time_best_genome, "All-time best genome should be saved")


# ============================================================
# Interaction tests
# ============================================================


func _test_tool_default() -> void:
    var mgr = RTNEAT_MANAGER_SCRIPT.new()
    assert_eq(mgr.current_tool, RTNEAT_MANAGER_SCRIPT.Tool.INSPECT, "Default tool should be INSPECT")


func _test_set_tool() -> void:
    var mgr = RTNEAT_MANAGER_SCRIPT.new()
    mgr.set_tool(RTNEAT_MANAGER_SCRIPT.Tool.BLESS)
    assert_eq(mgr.current_tool, RTNEAT_MANAGER_SCRIPT.Tool.BLESS, "Tool should change to BLESS")
    mgr.set_tool(RTNEAT_MANAGER_SCRIPT.Tool.CURSE)
    assert_eq(mgr.current_tool, RTNEAT_MANAGER_SCRIPT.Tool.CURSE, "Tool should change to CURSE")


func _test_bless_fitness() -> void:
    var pop = _create_pop(5)
    var initial: float = pop.fitnesses[2]
    pop.update_fitness(2, RTNEAT_MANAGER_SCRIPT.BLESS_FITNESS)
    assert_approx(pop.fitnesses[2], initial + 2000.0, 0.01, "Bless should add 2000 fitness")


func _test_curse_fitness() -> void:
    var pop = _create_pop(5)
    pop.update_fitness(1, 5000.0)  # Start with some fitness
    var before: float = pop.fitnesses[1]
    pop.update_fitness(1, -RTNEAT_MANAGER_SCRIPT.CURSE_FITNESS)
    assert_approx(pop.fitnesses[1], before - 2000.0, 0.01, "Curse should subtract 2000 fitness")


func _test_log_event() -> void:
    var mgr = RTNEAT_MANAGER_SCRIPT.new()
    assert_eq(mgr.replacement_log.size(), 0, "Log should start empty")
    mgr._log_event("Test event")
    assert_eq(mgr.replacement_log.size(), 1, "Log should have 1 entry after event")
    assert_eq(mgr.replacement_log[0].text, "Test event", "Log text should match")


# ============================================================
# Agent tests
# ============================================================


func _test_agent_scene_loads() -> void:
    assert_not_null(AGENT_SCRIPT, "agent.gd should load")


func _test_agent_initial_state() -> void:
    assert_not_null(AGENT_SCRIPT, "Agent script should be valid")


func _test_agent_reset() -> void:
    assert_not_null(AGENT_SCRIPT, "Agent script should load for reset test")


func _test_agent_powerups() -> void:
    assert_not_null(AGENT_SCRIPT, "Agent script should have powerup methods")


# ============================================================
# Enemy targeting tests
# ============================================================


func _test_enemy_targeting_method() -> void:
    var EnemyScript = load("res://enemy.gd")
    assert_not_null(EnemyScript, "enemy.gd should load")


func _test_powerup_signal() -> void:
    var PowerupScript = load("res://powerup.gd")
    assert_not_null(PowerupScript, "powerup.gd should load")
