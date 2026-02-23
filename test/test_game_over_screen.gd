extends "res://test/test_base.gd"

## Tests for ui/game_over_screen.gd

var GameOverScript = preload("res://ui/game_over_screen.gd")


func _run_tests() -> void:
    print("[Game Over Screen Tests]")

    _test(
        "creates_without_error",
        func():
            var screen = GameOverScript.new()
            assert_not_null(screen)
    )

    _test(
        "signals_defined",
        func():
            var screen = GameOverScript.new()
            assert_true(
                screen.has_signal("restart_requested"), "Should have restart_requested signal"
            )
            assert_true(screen.has_signal("menu_requested"), "Should have menu_requested signal")
    )

    _test(
        "show_stats_sets_visible",
        func():
            var screen = GameOverScript.new()
            (
                screen
                . show_stats(
                    {
                        "score": 5000,
                        "kills": 10,
                        "powerups_collected": 3,
                        "survival_time": 45.0,
                        "score_from_kills": 3000,
                        "score_from_powerups": 1500,
                        "is_high_score": false,
                        "mode": "play",
                    }
                )
            )
            assert_true(screen.visible, "Should be visible after show_stats")
    )

    _test(
        "hide_screen",
        func():
            var screen = GameOverScript.new()
            screen.show_stats(
                {
                    "score": 100,
                    "kills": 0,
                    "powerups_collected": 0,
                    "survival_time": 5.0,
                    "score_from_kills": 0,
                    "score_from_powerups": 0,
                    "is_high_score": false,
                    "mode": "play"
                }
            )
            screen.hide_screen()
            assert_false(screen.visible, "Should be hidden after hide_screen")
    )

    _test(
        "stats_stored",
        func():
            var screen = GameOverScript.new()
            var data = {
                "score": 7500,
                "kills": 20,
                "powerups_collected": 5,
                "survival_time": 60.0,
                "score_from_kills": 5000,
                "score_from_powerups": 2000,
                "is_high_score": true,
                "mode": "watch"
            }
            screen.show_stats(data)
            assert_eq(screen.stats.score, 7500, "Should store score")
            assert_eq(screen.stats.kills, 20, "Should store kills")
            assert_true(screen.stats.is_high_score, "Should store high score flag")
    )

    _test(
        "format_time_seconds",
        func():
            var screen = GameOverScript.new()
            var result = screen._format_time(15.5)
            assert_eq(result, "15.5s", "Short times should show seconds")
    )

    _test(
        "format_time_minutes",
        func():
            var screen = GameOverScript.new()
            var result = screen._format_time(125.0)
            assert_eq(result, "2:05", "Long times should show minutes:seconds")
    )
