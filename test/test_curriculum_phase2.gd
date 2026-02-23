extends "res://test/test_base.gd"
## Tests for Phase 2: Curriculum config application to game instances.

var MainScene = load("res://main.gd")


func run_tests() -> void:
    _test("arena_scale_affects_event_generation", _test_arena_scale_events)
    _test("enemy_type_filtering_in_events", _test_enemy_type_filtering)
    _test("powerup_type_filtering_in_events", _test_powerup_type_filtering)
    _test("default_events_no_curriculum", _test_default_events)
    _test("set_training_mode_applies_curriculum_config", _test_set_training_mode_config)
    _test("arena_scale_quarter_size", _test_arena_quarter_scale)
    _test("arena_scale_half_size", _test_arena_half_scale)
    _test("arena_scale_full_size", _test_arena_full_scale)
    _test("obstacle_count_scales_with_arena", _test_obstacle_scaling)
    _test("enemy_spawns_within_scaled_arena", _test_enemy_spawn_bounds)
    _test("powerup_spawns_within_scaled_arena", _test_powerup_spawn_bounds)
    _test("stage0_nursery_config", _test_stage0_nursery)
    _test("stage4_final_all_types", _test_stage4_final)


func _test_arena_scale_events() -> void:
    # Quarter-size arena should generate events within scaled bounds
    var config = {"arena_scale": 0.25, "enemy_types": [0], "powerup_types": [0, 6]}
    var events = MainScene.generate_random_events(42, config)
    var scaled_max = 3840.0 * 0.25  # 960

    for obs in events.obstacles:
        assert_lt(obs.pos.x, scaled_max, "Obstacle X should be within scaled arena")
        assert_lt(obs.pos.y, scaled_max, "Obstacle Y should be within scaled arena")
        assert_gt(obs.pos.x, 0.0, "Obstacle X should be positive")
        assert_gt(obs.pos.y, 0.0, "Obstacle Y should be positive")


func _test_enemy_type_filtering() -> void:
    # Only pawns allowed
    var config = {"arena_scale": 1.0, "enemy_types": [0], "powerup_types": []}
    var events = MainScene.generate_random_events(42, config)
    for spawn in events.enemy_spawns:
        assert_eq(spawn.type, 0, "All enemies should be pawns (type 0)")

    # Pawns and knights allowed
    var config2 = {"arena_scale": 1.0, "enemy_types": [0, 1], "powerup_types": []}
    var events2 = MainScene.generate_random_events(42, config2)
    for spawn in events2.enemy_spawns:
        assert_true(
            spawn.type == 0 or spawn.type == 1, "Enemy type %d should be 0 or 1" % spawn.type
        )


func _test_powerup_type_filtering() -> void:
    # Only health (0) and extra life (6)
    var config = {"arena_scale": 1.0, "enemy_types": [0], "powerup_types": [0, 6]}
    var events = MainScene.generate_random_events(42, config)
    for spawn in events.powerup_spawns:
        assert_true(
            spawn.type == 0 or spawn.type == 6, "Powerup type %d should be 0 or 6" % spawn.type
        )


func _test_default_events() -> void:
    # No curriculum config = backward compatible (all enemy type 0, all powerup types)
    var events = MainScene.generate_random_events(42)
    assert_gt(events.obstacles.size(), 0.0, "Should have obstacles")
    assert_gt(events.enemy_spawns.size(), 0.0, "Should have enemy spawns")
    assert_gt(events.powerup_spawns.size(), 0.0, "Should have powerup spawns")


func _test_set_training_mode_config() -> void:
    # Test that set_training_mode with curriculum config sets effective dimensions
    var scene = MainScene.new()
    var config = {"arena_scale": 0.5, "enemy_types": [0], "powerup_types": [0]}
    scene.set_training_mode(true, config)

    assert_eq(scene.training_mode, true, "Training mode should be true")
    assert_approx(scene.effective_arena_width, 3840.0 * 0.5, 0.1, "Width should be half")
    assert_approx(scene.effective_arena_height, 3840.0 * 0.5, 0.1, "Height should be half")
    assert_false(scene.curriculum_config.is_empty(), "Curriculum config should be set")


func _test_arena_quarter_scale() -> void:
    var scene = MainScene.new()
    scene.set_training_mode(true, {"arena_scale": 0.25, "enemy_types": [0], "powerup_types": [0]})
    assert_approx(scene.effective_arena_width, 960.0, 0.1)
    assert_approx(scene.effective_arena_height, 960.0, 0.1)


func _test_arena_half_scale() -> void:
    var scene = MainScene.new()
    scene.set_training_mode(true, {"arena_scale": 0.5, "enemy_types": [0], "powerup_types": [0]})
    assert_approx(scene.effective_arena_width, 1920.0, 0.1)
    assert_approx(scene.effective_arena_height, 1920.0, 0.1)


func _test_arena_full_scale() -> void:
    var scene = MainScene.new()
    scene.set_training_mode(true, {"arena_scale": 1.0, "enemy_types": [0], "powerup_types": [0]})
    assert_approx(scene.effective_arena_width, 3840.0, 0.1)
    assert_approx(scene.effective_arena_height, 3840.0, 0.1)


func _test_obstacle_scaling() -> void:
    # Quarter arena should have far fewer obstacles
    var config_small = {"arena_scale": 0.25, "enemy_types": [0], "powerup_types": [0]}
    var config_full = {"arena_scale": 1.0, "enemy_types": [0], "powerup_types": [0]}
    var events_small = MainScene.generate_random_events(42, config_small)
    var events_full = MainScene.generate_random_events(42, config_full)

    assert_lt(
        events_small.obstacles.size(),
        events_full.obstacles.size(),
        "Small arena should have fewer obstacles"
    )
    assert_gte(events_small.obstacles.size(), 3.0, "Small arena should have at least 3 obstacles")


func _test_enemy_spawn_bounds() -> void:
    var config = {"arena_scale": 0.5, "enemy_types": [0], "powerup_types": [0]}
    var events = MainScene.generate_random_events(42, config)
    var max_bound = 3840.0 * 0.5

    for spawn in events.enemy_spawns:
        assert_lte(spawn.pos.x, max_bound, "Enemy X should be within scaled arena")
        assert_lte(spawn.pos.y, max_bound, "Enemy Y should be within scaled arena")


func _test_powerup_spawn_bounds() -> void:
    var config = {"arena_scale": 0.5, "enemy_types": [0], "powerup_types": [0, 1]}
    var events = MainScene.generate_random_events(42, config)
    var max_bound = 3840.0 * 0.5

    for spawn in events.powerup_spawns:
        assert_lte(spawn.pos.x, max_bound, "Powerup X should be within scaled arena")
        assert_lte(spawn.pos.y, max_bound, "Powerup Y should be within scaled arena")


func _test_stage0_nursery() -> void:
    # Verify stage 0 config from training_manager produces correct events
    var config = {"arena_scale": 0.25, "enemy_types": [0], "powerup_types": [0, 6]}
    var events = MainScene.generate_random_events(123, config)

    # All enemies should be pawns
    for spawn in events.enemy_spawns:
        assert_eq(spawn.type, 0, "Nursery should only have pawns")

    # All powerups should be type 0 or 6
    for spawn in events.powerup_spawns:
        assert_true(
            spawn.type == 0 or spawn.type == 6, "Nursery powerup type %d not in [0, 6]" % spawn.type
        )


func _test_stage4_final() -> void:
    # Final stage should allow all types
    var config = {
        "arena_scale": 1.0,
        "enemy_types": [0, 1, 2, 3, 4],
        "powerup_types": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    }
    var events = MainScene.generate_random_events(123, config)

    # Should have variety (with enough spawns, statistically should see multiple types)
    var enemy_types_seen = {}
    for spawn in events.enemy_spawns:
        enemy_types_seen[spawn.type] = true

    assert_gt(enemy_types_seen.size(), 1.0, "Final stage should have variety of enemy types")
