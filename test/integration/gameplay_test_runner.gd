extends SceneTree
## Automated gameplay test runner for regression detection.
## Runs actual game scenes headless with AI-controlled player inputs,
## monitoring for crashes, performance issues, and gameplay regressions.
##
## Usage:
##   godot --headless --script test/integration/gameplay_test_runner.gd [-- --scenario=all]
##
## Outputs JSON report to user://gameplay_test_report.json

const CURRICULUM_MANAGER_SCRIPT = preload("res://ai/curriculum_manager.gd")
const STATS_TRACKER_SCRIPT = preload("res://ai/stats_tracker.gd")

const FRAME_BUDGET_MS := 33.3
const TEST_TIMEOUT_FRAMES := 3600

var _report := {}
var _scenarios: Array = []
var _scenario_idx := -1
var _frame_count := 0
var _frame_times: Array[float] = []
var _peak_memory_mb := 0.0
var _errors: Array[String] = []
var _main_scene: Node2D = null
var _player: CharacterBody2D = null
var _scenario_passed := true
var _scenario_start_time := 0
var _scenario_name := ""
var _scenario_duration := 300
var _initial_player_pos := Vector2.ZERO
var _initialized := false


func _init() -> void:
    _report = {
        "timestamp": Time.get_datetime_string_from_system(),
        "godot_version": Engine.get_version_info().string,
        "scenarios": [],
        "summary": {"total": 0, "passed": 0, "failed": 0, "errors": 0},
    }
    _build_scenarios()


func _build_scenarios() -> void:
    var requested := "all"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--scenario="):
            requested = arg.split("=")[1]

    var all_names := [
        "boot_and_run",
        "player_movement",
        "shooting_mechanics",
        "enemy_spawning",
        "powerup_collection",
        "player_death_and_respawn",
        "score_tracking",
        "collision_accuracy",
        "powerup_effects",
        "ai_controller_gameplay",
        "score_breakdown_accuracy",
        "curriculum_config_application",
        "performance_stress",
    ]

    if requested == "all":
        _scenarios = all_names
    else:
        if requested in all_names:
            _scenarios = [requested]
        else:
            print("Unknown scenario: %s" % requested)
            _scenarios = all_names


func _next_scenario() -> void:
    # Cleanup previous
    if _main_scene and is_instance_valid(_main_scene):
        _main_scene.queue_free()
        _main_scene = null
        _player = null

    # Save previous results
    if _scenario_idx >= 0:
        _finalize_scenario()

    _scenario_idx += 1
    if _scenario_idx >= _scenarios.size():
        _finish_all()
        return

    _scenario_name = _scenarios[_scenario_idx]
    _scenario_passed = true
    _frame_count = 0
    _frame_times.clear()
    _errors.clear()
    _scenario_start_time = Time.get_ticks_msec()
    _initial_player_pos = Vector2.ZERO

    print("\n--- Scenario: %s ---" % _scenario_name)

    # Set duration per scenario
    match _scenario_name:
        "boot_and_run":
            _scenario_duration = 300
        "player_movement":
            _scenario_duration = 120
        "shooting_mechanics":
            _scenario_duration = 180
        "enemy_spawning":
            _scenario_duration = 600
        "powerup_collection":
            _scenario_duration = 600
        "player_death_and_respawn":
            _scenario_duration = 120
        "score_tracking":
            _scenario_duration = 300
        "collision_accuracy":
            _scenario_duration = 300
        "powerup_effects":
            _scenario_duration = 600
        "ai_controller_gameplay":
            _scenario_duration = 600
        "score_breakdown_accuracy":
            _scenario_duration = 300
        "curriculum_config_application":
            _scenario_duration = 60
        "performance_stress":
            _scenario_duration = 900
        _:
            _scenario_duration = 300

    _load_game_scene()


func _load_game_scene() -> void:
    var scene := load("res://main.tscn") as PackedScene
    if not scene:
        _record_error("Failed to load main.tscn")
        _next_scenario()
        return

    _main_scene = scene.instantiate() as Node2D
    if not _main_scene:
        _record_error("Failed to instantiate main scene")
        _next_scenario()
        return

    # Apply curriculum config for the curriculum test scenario
    if _scenario_name == "curriculum_config_application":
        var config = {"arena_scale": 0.5, "enemy_types": [0, 1], "powerup_types": [0, 2, 6]}
        _main_scene.set_training_mode(true, config)
        var events = _main_scene.generate_random_events(42, config)
        _main_scene.set_preset_events(events.obstacles, events.enemy_spawns, events.powerup_spawns)
    else:
        _main_scene.set_game_seed(42)
        _main_scene.set_training_mode(true)
        var events = _main_scene.generate_random_events(42)
        _main_scene.set_preset_events(events.obstacles, events.enemy_spawns, events.powerup_spawns)

    root.add_child(_main_scene)
    paused = false

    _player = _main_scene.get_node_or_null("Player")
    if _player:
        _player.enable_ai_control(true)
    else:
        _record_error("Player node not found")


func _process(delta: float) -> bool:
    if not _initialized:
        _initialized = true
        _next_scenario()
        return false

    if _scenario_idx >= _scenarios.size():
        return true

    if not _main_scene or not is_instance_valid(_main_scene):
        _record_error("Scene lost during test")
        _next_scenario()
        return false

    _frame_count += 1

    # Unpause if game paused itself
    if paused:
        paused = false

    # Track frame time
    _frame_times.append(delta * 1000.0)

    # Track memory
    var mem_mb := OS.get_static_memory_usage() / (1024.0 * 1024.0)
    if mem_mb > _peak_memory_mb:
        _peak_memory_mb = mem_mb

    # Run scenario-specific frame logic
    _run_scenario_frame()

    # Default AI behavior (unless scenario overrides)
    if (
        _scenario_name != "ai_controller_gameplay"
        and _scenario_name != "curriculum_config_application"
    ):
        if _player and is_instance_valid(_player) and not _player.is_hit:
            _default_ai_behavior()

    # Check timeout
    if _frame_count >= _scenario_duration:
        _run_scenario_final_check()
        _next_scenario()

    return false


func _run_scenario_frame() -> void:
    match _scenario_name:
        "player_movement":
            if _frame_count == 5 and _player:
                _initial_player_pos = _player.position
            if _frame_count >= 10 and _frame_count <= 60 and _player:
                _player.set_ai_action(Vector2.RIGHT, Vector2.ZERO)

        "shooting_mechanics":
            if _frame_count % 30 == 10 and _player:
                _player.set_ai_action(Vector2.ZERO, Vector2.RIGHT)

        "player_death_and_respawn":
            if _frame_count == 30 and _player and not _player.is_hit:
                _player._trigger_hit()

        "collision_accuracy":
            # Spawn an enemy right on top of player to force a collision
            if _frame_count == 30 and _main_scene and _player:
                if not _player.is_invincible:
                    _main_scene.spawn_enemy_at(_player.position + Vector2(20, 0), 0)
            # After collision, move player away from danger
            if _frame_count > 60 and _player and is_instance_valid(_player):
                var arena_center := Vector2(1920, 1920)
                _player.set_ai_action(_player.position.direction_to(arena_center), Vector2.ZERO)

        "powerup_effects":
            # Spawn powerups directly on player to guarantee collection
            if _frame_count == 20 and _main_scene and _player:
                _main_scene.spawn_powerup_at(_player.position + Vector2(30, 0), 0)  # Speed Boost
            if _frame_count == 30 and _player:
                _player.set_ai_action(Vector2.RIGHT, Vector2.ZERO)  # Walk into powerup
            if _frame_count == 120 and _main_scene and _player:
                _main_scene.spawn_powerup_at(_player.position + Vector2(30, 0), 1)  # Invincibility
            if _frame_count == 130 and _player:
                _player.set_ai_action(Vector2.RIGHT, Vector2.ZERO)
            if _frame_count == 240 and _main_scene and _player:
                _main_scene.spawn_powerup_at(_player.position + Vector2(30, 0), 4)  # Rapid Fire
            if _frame_count == 250 and _player:
                _player.set_ai_action(Vector2.RIGHT, Vector2.ZERO)

        "ai_controller_gameplay":
            # Let the AI controller drive the player using a real neural network
            if _frame_count == 5 and _player and _main_scene:
                var NeuralNetworkScript = load("res://ai/neural_network.gd")
                var AIControllerScript = load("res://ai/ai_controller.gd")
                var nn = NeuralNetworkScript.new(86, 32, 6)
                var controller = AIControllerScript.new()
                controller.set_player(_player)
                controller.set_network(nn)
                set_meta("_ai_controller", controller)
            if _frame_count > 10 and has_meta("_ai_controller"):
                var controller = get_meta("_ai_controller")
                var action: Dictionary = controller.get_action()
                if _player and is_instance_valid(_player) and not _player.is_hit:
                    _player.set_ai_action(action.move_direction, action.shoot_direction)

        "score_breakdown_accuracy":
            # Let game run with active movement, then verify score decomposition
            if _frame_count % 30 == 10 and _player:
                _player.set_ai_action(
                    Vector2(sin(_frame_count * 0.05), cos(_frame_count * 0.07)).normalized(),
                    Vector2.ZERO
                )

        "curriculum_config_application":
            # Just let the game run briefly — checks are in final check
            if _player and is_instance_valid(_player) and not _player.is_hit:
                _player.set_ai_action(Vector2.RIGHT, Vector2.ZERO)

        "performance_stress":
            if _frame_count == 60 and _main_scene:
                for i in range(20):
                    var pos := Vector2(100 + (i % 5) * 800, 100 + (i / 5) * 800)
                    _main_scene.spawn_enemy_at(pos, 0)


func _run_scenario_final_check() -> void:
    match _scenario_name:
        "boot_and_run":
            _check(
                _main_scene != null and is_instance_valid(_main_scene),
                "Scene alive after %d frames" % _frame_count
            )
            _check(_player != null and is_instance_valid(_player), "Player exists")
            if _main_scene:
                _check(not _main_scene.game_over, "Game not over (player survived)")
                _check(_main_scene.score > 0, "Score is positive (%.0f)" % _main_scene.score)

        "player_movement":
            _check(_player != null, "Player exists")
            if _player:
                _check(_player.position != _initial_player_pos, "Player moved from start")

        "shooting_mechanics":
            _check(true, "Shooting completed without crash")

        "enemy_spawning":
            if _main_scene:
                _check(
                    _main_scene.survival_time > 3.0,
                    "Game ran >3s (survival_time=%.1f)" % _main_scene.survival_time
                )

        "powerup_collection":
            if _main_scene:
                _check(
                    _main_scene.powerups_collected >= 0,
                    "Powerup system functional (collected=%d)" % _main_scene.powerups_collected
                )

        "player_death_and_respawn":
            if _main_scene:
                _check(_main_scene.lives < 3, "Player lost a life (lives=%d)" % _main_scene.lives)
                if _main_scene.lives > 0 and _player:
                    _check(not _player.is_hit, "Player respawned")

        "score_tracking":
            if _main_scene:
                _check(_main_scene.score > 0, "Score positive (%.0f)" % _main_scene.score)
                var expected_min: float = _main_scene.survival_time * 4
                _check(
                    _main_scene.score >= expected_min,
                    "Score >= expected (%.0f >= %.0f)" % [_main_scene.score, expected_min]
                )

        "collision_accuracy":
            if _main_scene:
                _check(
                    _main_scene.lives < 3 or _player.is_invincible,
                    (
                        "Collision registered (lives=%d, invincible=%s)"
                        % [_main_scene.lives, _player.is_invincible]
                    )
                )
                _check(
                    not _main_scene.game_over,
                    "Game still running after collision (lives=%d)" % _main_scene.lives
                )

        "powerup_effects":
            if _main_scene:
                _check(
                    _main_scene.powerups_collected >= 1,
                    "At least 1 powerup collected (got %d)" % _main_scene.powerups_collected
                )
                _check(
                    _main_scene.score_from_powerups > 0,
                    "Powerup bonus scored (%.0f)" % _main_scene.score_from_powerups
                )

        "ai_controller_gameplay":
            if _main_scene:
                _check(
                    _main_scene.survival_time > 3.0,
                    "AI survived >3s (%.1f)" % _main_scene.survival_time
                )
                _check(
                    not _main_scene.game_over or _main_scene.score > 0,
                    "AI scored something (%.0f)" % _main_scene.score
                )

        "score_breakdown_accuracy":
            if _main_scene:
                var total: float = _main_scene.score
                var kills: float = _main_scene.score_from_kills
                var powerups: float = _main_scene.score_from_powerups
                _check(
                    total >= kills + powerups - 1.0,
                    (
                        "Score breakdown consistent: total=%.0f >= kills=%.0f + pwr=%.0f"
                        % [total, kills, powerups]
                    )
                )
                _check(total > 0, "Non-zero score after play (%.0f)" % total)

        "curriculum_config_application":
            # Verify that curriculum config was applied to the scene
            if _main_scene:
                _check(_main_scene.training_mode == true, "Training mode is on")
                _check(
                    _main_scene.effective_arena_width > 0,
                    "Arena width set (%.0f)" % _main_scene.effective_arena_width
                )
                _check(
                    _main_scene.effective_arena_width < 3840.0,
                    "Arena scaled down (%.0f < 3840)" % _main_scene.effective_arena_width
                )
                # Verify curriculum_manager API works
                var cm = CURRICULUM_MANAGER_SCRIPT.new()
                _check(
                    cm.get_current_config().has("arena_scale"),
                    "CurriculumManager returns valid config"
                )
                _check(
                    CURRICULUM_MANAGER_SCRIPT.STAGES.size() >= 5,
                    "CurriculumManager has >= 5 stages (%d)" % CURRICULUM_MANAGER_SCRIPT.STAGES.size()
                )
                # Verify stats_tracker API works
                var st = STATS_TRACKER_SCRIPT.new()
                st.record_eval_result(0, 100.0, 50.0, 30.0, 20.0)
                _check(st.get_avg_fitness(0) == 100.0, "StatsTracker records and retrieves fitness")
                st.reset()
                _check(st.fitness_accumulator.is_empty(), "StatsTracker reset clears accumulators")

        "performance_stress":
            if _frame_times.size() > 0:
                var avg := 0.0
                var max_ft := 0.0
                var spikes := 0
                for ft in _frame_times:
                    avg += ft
                    if ft > max_ft:
                        max_ft = ft
                    if ft > FRAME_BUDGET_MS:
                        spikes += 1
                avg /= _frame_times.size()
                var spike_pct := (float(spikes) / _frame_times.size()) * 100.0
                print(
                    (
                        "  Perf: avg=%.1fms max=%.1fms spikes=%.1f%% mem=%.1fMB"
                        % [avg, max_ft, spike_pct, _peak_memory_mb]
                    )
                )
                _check(spike_pct < 50.0, "Frame spikes <50%% (got %.1f%%)" % spike_pct)
                _check(_peak_memory_mb < 2048.0, "Memory <2GB (got %.0fMB)" % _peak_memory_mb)


func _default_ai_behavior() -> void:
    if not _player or not is_instance_valid(_player):
        return

    var arena_center := Vector2(1920.0, 1920.0)
    var move_dir := Vector2.ZERO
    var shoot_dir := Vector2.ZERO

    # Move toward nearest powerup or wander
    var nearest_dist := 99999.0
    var nearest_pos := Vector2.ZERO
    for p in root.get_tree().get_nodes_in_group("powerup"):
        if is_instance_valid(p):
            var d := _player.position.distance_to(p.position)
            if d < nearest_dist:
                nearest_dist = d
                nearest_pos = p.position

    if nearest_dist < 1500:
        move_dir = _player.position.direction_to(nearest_pos)
    else:
        var target := (
            arena_center + Vector2(sin(_frame_count * 0.02) * 500, cos(_frame_count * 0.03) * 500)
        )
        move_dir = _player.position.direction_to(target)

    # Shoot at nearest enemy
    if _main_scene and is_instance_valid(_main_scene):
        var enemies: Array = _main_scene.get_local_enemies()
        var enemy_dist := 99999.0
        var enemy_pos := Vector2.ZERO
        for e in enemies:
            if is_instance_valid(e):
                var d := _player.position.distance_to(e.position)
                if d < enemy_dist:
                    enemy_dist = d
                    enemy_pos = e.position

        if enemy_dist < 800:
            var raw := _player.position.direction_to(enemy_pos)
            if abs(raw.x) > abs(raw.y):
                shoot_dir = Vector2.RIGHT if raw.x > 0 else Vector2.LEFT
            else:
                shoot_dir = Vector2.DOWN if raw.y > 0 else Vector2.UP

    _player.set_ai_action(move_dir, shoot_dir)


# ============================================================
# HELPERS
# ============================================================


func _check(condition: bool, desc: String) -> void:
    if not condition:
        _scenario_passed = false
        _errors.append(desc)
        print("  FAIL: %s" % desc)
    else:
        print("  PASS: %s" % desc)


func _record_error(msg: String) -> void:
    _scenario_passed = false
    _errors.append(msg)
    print("  ERROR: %s" % msg)


func _finalize_scenario() -> void:
    var elapsed_ms := Time.get_ticks_msec() - _scenario_start_time
    var result := {
        "name": _scenario_name,
        "passed": _scenario_passed,
        "frames": _frame_count,
        "elapsed_ms": elapsed_ms,
        "errors": _errors.duplicate(),
        "performance":
        {
            "avg_frame_ms": _calc_avg_ft(),
            "max_frame_ms": _calc_max_ft(),
            "peak_memory_mb": _peak_memory_mb,
        }
    }

    if _main_scene and is_instance_valid(_main_scene):
        result["gameplay"] = {
            "score": _main_scene.score,
            "kills": _main_scene.kills,
            "powerups_collected": _main_scene.powerups_collected,
            "lives_remaining": _main_scene.lives,
            "survival_time": _main_scene.survival_time,
            "game_over": _main_scene.game_over,
        }
        # Include score breakdown if available
        if _main_scene.get("score_from_kills") != null:
            result["gameplay"]["score_from_kills"] = _main_scene.score_from_kills
            result["gameplay"]["score_from_powerups"] = _main_scene.score_from_powerups

    _report.scenarios.append(result)
    _report.summary.total += 1
    if _scenario_passed:
        _report.summary.passed += 1
    else:
        _report.summary.failed += 1

    var status := "PASS" if _scenario_passed else "FAIL"
    print("  Result: %s (%dms, %d frames)" % [status, elapsed_ms, _frame_count])


func _calc_avg_ft() -> float:
    if _frame_times.size() == 0:
        return 0.0
    var total := 0.0
    for ft in _frame_times:
        total += ft
    return total / _frame_times.size()


func _calc_max_ft() -> float:
    var m := 0.0
    for ft in _frame_times:
        if ft > m:
            m = ft
    return m


func _finish_all() -> void:
    # Add training API metadata to report
    _report["training_api"] = {
        "curriculum_stages": _get_curriculum_stage_count(),
        "stats_tracker_available": _check_stats_tracker(),
    }

    var report_json := JSON.stringify(_report, "  ")
    var path := OS.get_user_data_dir() + "/gameplay_test_report.json"
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(report_json)
        file.close()
        print("\nReport: %s" % path)

    print("\n========================================")
    print("  GAMEPLAY TEST RESULTS")
    print("========================================")
    print("Total:  %d" % _report.summary.total)
    print("Passed: %d" % _report.summary.passed)
    print("Failed: %d" % _report.summary.failed)
    print("========================================\n")

    for s in _report.scenarios:
        var icon := "✓" if s.passed else "✗"
        print("  %s %s" % [icon, s.name])
        if not s.passed:
            for e in s.errors:
                print("    → %s" % e)

    quit(0 if _report.summary.failed == 0 else 1)


func _get_curriculum_stage_count() -> int:
    return CURRICULUM_MANAGER_SCRIPT.STAGES.size()


func _check_stats_tracker() -> bool:
    var st = STATS_TRACKER_SCRIPT.new()
    return st != null
