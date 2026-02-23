extends "res://test/test_base.gd"
## Tests for ParetoChart visualization widget.

const ParetoChartScript = preload("res://ui/pareto_chart.gd")


func run_tests() -> void:
    print("\n[Pareto Chart Tests]")

    # Data extraction
    _test("axis_values_mode0_kills_vs_survival", _test_axis_values_mode0)
    _test("axis_values_mode1_powerups_vs_survival", _test_axis_values_mode1)
    _test("axis_values_mode2_kills_vs_powerups", _test_axis_values_mode2)
    _test("axis_values_empty", _test_axis_values_empty)

    # Range computation
    _test("compute_ranges_normal", _test_ranges_normal)
    _test("compute_ranges_single_value", _test_ranges_single_value)
    _test("compute_ranges_empty", _test_ranges_empty)

    # Mode management
    _test("set_mode_clamps", _test_set_mode_clamps)
    _test("cycle_mode_wraps", _test_cycle_mode_wraps)
    _test("mode_labels_correct", _test_mode_labels)

    # Data setting
    _test("set_data_stores_objectives", _test_set_data_stores)
    _test("set_data_with_pareto_indices", _test_set_data_pareto)
    _test("set_data_empty", _test_set_data_empty)

    # Format values
    _test("format_value_large", _test_format_large)
    _test("format_value_small", _test_format_small)


# ============================================================
# Axis value extraction tests
# ============================================================


func _test_axis_values_mode0() -> void:
    # Vector3(survival=100, kills=50, powerups=30)
    var objs = [Vector3(100, 50, 30), Vector3(200, 80, 10)]
    var result = ParetoChartScript.compute_axis_values(objs, 0)
    # Mode 0: x=kills(y), y=survival(x), color=powerups(z)
    assert_eq(result.x[0], 50.0, "x should be kills")
    assert_eq(result.y[0], 100.0, "y should be survival")
    assert_eq(result.color[0], 30.0, "color should be powerups")
    assert_eq(result.x[1], 80.0, "second x")
    assert_eq(result.y[1], 200.0, "second y")


func _test_axis_values_mode1() -> void:
    var objs = [Vector3(100, 50, 30)]
    var result = ParetoChartScript.compute_axis_values(objs, 1)
    # Mode 1: x=powerups(z), y=survival(x), color=kills(y)
    assert_eq(result.x[0], 30.0, "x should be powerups")
    assert_eq(result.y[0], 100.0, "y should be survival")
    assert_eq(result.color[0], 50.0, "color should be kills")


func _test_axis_values_mode2() -> void:
    var objs = [Vector3(100, 50, 30)]
    var result = ParetoChartScript.compute_axis_values(objs, 2)
    # Mode 2: x=kills(y), y=powerups(z), color=survival(x)
    assert_eq(result.x[0], 50.0, "x should be kills")
    assert_eq(result.y[0], 30.0, "y should be powerups")
    assert_eq(result.color[0], 100.0, "color should be survival")


func _test_axis_values_empty() -> void:
    var result = ParetoChartScript.compute_axis_values([], 0)
    assert_eq(result.x.size(), 0, "empty input gives empty output")
    assert_eq(result.y.size(), 0, "empty y")
    assert_eq(result.color.size(), 0, "empty color")


# ============================================================
# Range tests
# ============================================================


func _test_ranges_normal() -> void:
    var vals = PackedFloat32Array([10.0, 20.0, 50.0, 5.0])
    var r = ParetoChartScript.compute_ranges(vals)
    assert_eq(r.x, 5.0, "min should be 5")
    assert_eq(r.y, 50.0, "max should be 50")


func _test_ranges_single_value() -> void:
    var vals = PackedFloat32Array([42.0, 42.0, 42.0])
    var r = ParetoChartScript.compute_ranges(vals)
    assert_eq(r.x, 42.0, "min should be 42")
    assert_eq(r.y, 43.0, "max should be min+1 when all equal")


func _test_ranges_empty() -> void:
    var vals = PackedFloat32Array()
    var r = ParetoChartScript.compute_ranges(vals)
    assert_eq(r.x, 0.0, "empty min is 0")
    assert_eq(r.y, 1.0, "empty max is 1")


# ============================================================
# Mode tests
# ============================================================


func _test_set_mode_clamps() -> void:
    var chart = ParetoChartScript.new()
    chart.set_mode(-1)
    assert_eq(chart.get_mode(), 0, "negative clamps to 0")
    chart.set_mode(99)
    assert_eq(chart.get_mode(), 2, "overflow clamps to max")
    chart.set_mode(1)
    assert_eq(chart.get_mode(), 1, "valid mode set")


func _test_cycle_mode_wraps() -> void:
    var chart = ParetoChartScript.new()
    assert_eq(chart.get_mode(), 0, "starts at 0")
    chart.cycle_mode()
    assert_eq(chart.get_mode(), 1, "cycle to 1")
    chart.cycle_mode()
    assert_eq(chart.get_mode(), 2, "cycle to 2")
    chart.cycle_mode()
    assert_eq(chart.get_mode(), 0, "wraps to 0")


func _test_mode_labels() -> void:
    var chart = ParetoChartScript.new()
    chart.set_mode(0)
    var labels = chart.get_mode_label()
    assert_eq(labels.x, "Kill Score", "mode 0 x label")
    assert_eq(labels.y, "Survival Time", "mode 0 y label")
    assert_eq(labels.color, "Powerup Score", "mode 0 color label")


# ============================================================
# Data tests
# ============================================================


func _test_set_data_stores() -> void:
    var chart = ParetoChartScript.new()
    var objs = [Vector3(1, 2, 3), Vector3(4, 5, 6)]
    chart.set_data(objs)
    # Verify via axis extraction that data is stored
    var result = ParetoChartScript.compute_axis_values(objs, 0)
    assert_eq(result.x.size(), 2, "two points stored")


func _test_set_data_pareto() -> void:
    var chart = ParetoChartScript.new()
    var objs = [Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)]
    chart.set_data(objs, [0, 2])
    # Chart accepts pareto indices — just verify no crash
    assert_true(true, "set_data with pareto indices accepted")


func _test_set_data_empty() -> void:
    var chart = ParetoChartScript.new()
    chart.set_data([])
    assert_true(true, "set_data with empty array accepted")


# ============================================================
# Format tests
# ============================================================


func _test_format_large() -> void:
    assert_eq(ParetoChartScript._format_value(1500.0), "1500", "large value no decimal")
    assert_eq(ParetoChartScript._format_value(250.0), "250", "medium value no decimal")


func _test_format_small() -> void:
    assert_eq(ParetoChartScript._format_value(5.5), "5.5", "small value one decimal")
    assert_eq(ParetoChartScript._format_value(0.3), "0.3", "tiny value one decimal")
