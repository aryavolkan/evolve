extends "res://test/test_base.gd"

## Tests for ui/comparison_panel.gd

var ComparisonPanelScript = preload("res://ui/comparison_panel.gd")


func run_tests() -> void:
    print("[Comparison Panel Tests]")

    _test(
        "creates_without_error",
        func():
            var panel = ComparisonPanelScript.new()
            assert_not_null(panel)
    )

    _test(
        "signals_defined",
        func():
            var panel = ComparisonPanelScript.new()
            assert_true(panel.has_signal("start_requested"), "Should have start_requested signal")
            assert_true(panel.has_signal("back_requested"), "Should have back_requested signal")
    )

    _test(
        "has_four_slots",
        func():
            var panel = ComparisonPanelScript.new()
            assert_eq(panel.strategy_slots.size(), 4, "Should have 4 strategy slots")
    )

    _test(
        "default_two_enabled",
        func():
            var panel = ComparisonPanelScript.new()
            assert_eq(panel.get_enabled_count(), 2, "Should have 2 enabled by default")
    )

    _test(
        "slots_have_source",
        func():
            var panel = ComparisonPanelScript.new()
            for slot in panel.strategy_slots:
                assert_true(slot.has("source"), "Each slot should have source key")
                assert_true(slot.has("label"), "Each slot should have label key")
                assert_true(slot.has("enabled"), "Each slot should have enabled key")
    )

    _test(
        "default_source_is_best",
        func():
            var panel = ComparisonPanelScript.new()
            for slot in panel.strategy_slots:
                assert_eq(slot.source, "best", "Default source should be 'best'")
    )
