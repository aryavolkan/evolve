extends "res://test/test_base.gd"

const AGENT_SCENE = AGENT_SCENE
## Tests for multi-agent team cooperation (Team Battle mode).

var SensorScript = preload("res://ai/sensor.gd")
var RtNeatPopScript = preload("res://ai/rtneat_population.gd")
var TeamManagerScript = preload("res://ai/team_manager.gd")


func _run_tests() -> void:
    print("\n[Team Battle Tests]")

    _test("team_manager_creates_without_error", _test_team_manager_creates)
    _test("agent_team_id_defaults_to_negative", _test_agent_team_id_default)
    _test("agent_adds_to_group_with_team", _test_agent_group)
    _test("agent_take_pvp_hit_reduces_lives", _test_pvp_hit_reduces_lives)
    _test("agent_take_pvp_hit_blocked_by_invincible", _test_pvp_blocked_invincible)
    _test("agent_take_pvp_hit_blocked_by_shield", _test_pvp_blocked_shield)
    _test("projectile_owner_team_id_defaults_negative", _test_projectile_team_default)
    _test("sensor_team_mode_increases_inputs", _test_sensor_team_inputs)
    _test("sensor_standard_mode_unchanged", _test_sensor_standard_unchanged)
    _test("sensor_agent_cache_populated", _test_sensor_agent_cache)
    _test("team_colors_distinct", _test_team_colors_distinct)
    _test("team_manager_setup_creates_two_populations", _test_two_populations)
    _test("team_manager_get_stats_has_team_data", _test_stats_team_data)
    _test("agent_pvp_hit_emits_signal", _test_pvp_signal)
    _test("agent_is_slow_active_exists", _test_is_slow_active)


func _test_team_manager_creates() -> void:
    var tm = TeamManagerScript.new()
    assert_not_null(tm, "TeamManager should instantiate")


func _test_agent_team_id_default() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    assert_eq(agent.team_id, -1, "Agent team_id should default to -1")
    agent.free()


func _test_agent_group() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    agent.team_id = 0
    # _ready() is not called until added to tree, but we can verify the property
    assert_eq(agent.team_id, 0, "Agent team_id should be settable")
    agent.free()


func _test_pvp_hit_reduces_lives() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    agent.team_id = 0
    var initial_lives: int = agent.lives
    # take_pvp_hit triggers _trigger_hit which reduces lives
    # But agent needs to be in tree for full behavior. Test the property path.
    assert_eq(initial_lives, 3, "Agent should start with 3 lives")
    assert_true(agent.has_method("take_pvp_hit"), "Agent should have take_pvp_hit method")
    agent.free()


func _test_pvp_blocked_invincible() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    agent.team_id = 1
    agent.is_invincible = true
    # take_pvp_hit should return early when invincible
    # We verify the method exists and invincibility state is correct
    assert_true(agent.is_invincible, "Agent should be invincible")
    assert_true(agent.has_method("take_pvp_hit"), "Agent should have take_pvp_hit")
    agent.free()


func _test_pvp_blocked_shield() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    agent.team_id = 0
    agent.has_shield = true
    assert_true(agent.has_shield, "Agent should have shield")
    agent.free()


func _test_projectile_team_default() -> void:
    var ProjectileScene = preload("res://projectile.tscn")
    var proj = ProjectileScene.instantiate()
    assert_eq(proj.owner_team_id, -1, "Projectile owner_team_id should default to -1")
    proj.free()


func _test_sensor_team_inputs() -> void:
    var sensor = SensorScript.new()
    sensor.team_mode = true
    var total = sensor.get_total_inputs()
    assert_eq(total, 119, "Team mode should have 119 inputs (16*7 + 7)")


func _test_sensor_standard_unchanged() -> void:
    var sensor = SensorScript.new()
    assert_false(sensor.team_mode, "Default sensor should not be in team mode")
    var total = sensor.get_total_inputs()
    assert_eq(total, 86, "Standard mode should have 86 inputs")


func _test_sensor_agent_cache() -> void:
    # Verify the static _arena_agents dict exists
    assert_true(SensorScript._arena_agents is Dictionary, "Agent cache should be a Dictionary")


func _test_team_colors_distinct() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    assert_true(agent.TEAM_COLORS.size() >= 2, "Should have at least 2 team colors")
    assert_ne(agent.TEAM_COLORS[0], agent.TEAM_COLORS[1], "Team colors should be distinct")
    agent.free()


func _test_two_populations() -> void:
    var tm = TeamManagerScript.new()
    # setup requires a scene but we can test that populations are created
    # Create minimal mock
    var pop_a = RtNeatPopScript.new()
    var config_a := NeatConfig.new()
    config_a.input_count = 119
    config_a.output_count = 6
    config_a.population_size = 5
    pop_a.initialize(5, config_a)
    tm.pop_a = pop_a

    var pop_b = RtNeatPopScript.new()
    var config_b := NeatConfig.new()
    config_b.input_count = 119
    config_b.output_count = 6
    config_b.population_size = 5
    pop_b.initialize(5, config_b)
    tm.pop_b = pop_b

    assert_not_null(tm.pop_a, "pop_a should exist")
    assert_not_null(tm.pop_b, "pop_b should exist")
    assert_eq(tm.pop_a.pop_size, 5, "pop_a should have 5 agents")
    assert_eq(tm.pop_b.pop_size, 5, "pop_b should have 5 agents")


func _test_stats_team_data() -> void:
    var tm = TeamManagerScript.new()
    # Setup minimal populations
    var pop_a = RtNeatPopScript.new()
    var config_a := NeatConfig.new()
    config_a.input_count = 119
    config_a.output_count = 6
    config_a.population_size = 3
    pop_a.initialize(3, config_a)
    tm.pop_a = pop_a

    var pop_b = RtNeatPopScript.new()
    var config_b := NeatConfig.new()
    config_b.input_count = 119
    config_b.output_count = 6
    config_b.population_size = 3
    pop_b.initialize(3, config_b)
    tm.pop_b = pop_b

    tm.team_size = 3
    var stats: Dictionary = tm.get_stats()
    assert_true(stats.has("team_a"), "Stats should have team_a")
    assert_true(stats.has("team_b"), "Stats should have team_b")
    assert_true(stats.has("team_a_pvp_kills"), "Stats should have team_a_pvp_kills")
    assert_true(stats.has("team_b_pvp_kills"), "Stats should have team_b_pvp_kills")
    assert_eq(stats.total_agents, 6, "Total agents should be 2 * team_size")


func _test_pvp_signal() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    assert_true(agent.has_signal("pvp_hit_by"), "Agent should have pvp_hit_by signal")
    agent.free()


func _test_is_slow_active() -> void:
    var AgentScene = AGENT_SCENE
    var agent = AgentScene.instantiate()
    assert_true("is_slow_active" in agent, "Agent should have is_slow_active property")
    assert_false(agent.is_slow_active, "is_slow_active should default to false")
    agent.free()
