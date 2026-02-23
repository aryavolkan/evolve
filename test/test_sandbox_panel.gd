extends "res://test/test_base.gd"

## Tests for ui/sandbox_panel.gd

var SandboxPanelScript = preload("res://ui/sandbox_panel.gd")


func _run_tests() -> void:
    print("[Sandbox Panel Tests]")

    _test(
        "creates_without_error",
        func():
            var panel = SandboxPanelScript.new()
            assert_not_null(panel)
    )

    _test(
        "signals_defined",
        func():
            var panel = SandboxPanelScript.new()
            assert_true(panel.has_signal("config_changed"), "Should have config_changed signal")
            assert_true(panel.has_signal("start_requested"), "Should have start_requested signal")
            assert_true(panel.has_signal("train_requested"), "Should have train_requested signal")
            assert_true(panel.has_signal("back_requested"), "Should have back_requested signal")
    )

    _test(
        "default_config",
        func():
            var panel = SandboxPanelScript.new()
            var config = panel.get_config()
            assert_true(config.has("enemy_types"), "Config should have enemy_types")
            assert_true(
                config.has("spawn_rate_multiplier"), "Config should have spawn_rate_multiplier"
            )
            assert_true(config.has("powerup_frequency"), "Config should have powerup_frequency")
            assert_true(config.has("starting_difficulty"), "Config should have starting_difficulty")
            assert_true(config.has("network_source"), "Config should have network_source")
            assert_true(
                config.has("training_network_source"), "Config should have training_network_source"
            )
            assert_true(config.has("training_generation"), "Config should have training_generation")
    )

    _test(
        "default_enemy_types",
        func():
            var panel = SandboxPanelScript.new()
            var config = panel.get_config()
            # Pawn, Knight, Bishop, Rook enabled by default; Queen disabled
            assert_true(0 in config.enemy_types, "Pawn should be enabled")
            assert_true(1 in config.enemy_types, "Knight should be enabled")
            assert_true(2 in config.enemy_types, "Bishop should be enabled")
            assert_true(3 in config.enemy_types, "Rook should be enabled")
            assert_false(4 in config.enemy_types, "Queen should be disabled by default")
    )

    _test(
        "default_spawn_rate",
        func():
            var panel = SandboxPanelScript.new()
            var config = panel.get_config()
            assert_approx(
                config.spawn_rate_multiplier, 1.0, 0.01, "Default spawn rate should be 1.0"
            )
    )

    _test(
        "default_network_source",
        func():
            var panel = SandboxPanelScript.new()
            var config = panel.get_config()
            assert_eq(config.network_source, "best", "Default network source should be 'best'")
    )

    _test(
        "default_training_seed_config",
        func():
            var panel = SandboxPanelScript.new()
            var config = panel.get_config()
            assert_eq(
                config.training_network_source,
                "best",
                "Default training network source should be 'best'"
            )
            assert_eq(
                config.training_generation, 1, "Default training generation should start at 1"
            )
    )

    _test(
        "enemy_type_toggle",
        func():
            var panel = SandboxPanelScript.new()
            panel.enemy_types_enabled[4] = true  # Enable queen
            var config = panel.get_config()
            assert_true(4 in config.enemy_types, "Queen should be enabled after toggle")
    )

    _test(
        "at_least_one_enemy_type",
        func():
            var panel = SandboxPanelScript.new()
            # Disable all
            for key in panel.enemy_types_enabled:
                panel.enemy_types_enabled[key] = false
            # Trigger the toggle handler on the last one (it should force pawn on)
            panel._on_enemy_type_toggled(4, false)
            var config = panel.get_config()
            assert_true(config.enemy_types.size() > 0, "At least one enemy type must be enabled")
    )

    _test(
        "enemy_names_match_types",
        func():
            var panel = SandboxPanelScript.new()
            assert_eq(panel.ENEMY_NAMES.size(), 5, "Should have 5 enemy type names")
            assert_eq(panel.ENEMY_NAMES[0], "Pawn")
            assert_eq(panel.ENEMY_NAMES[4], "Queen")
    )
