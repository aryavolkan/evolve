extends RefCounted
## Base class for test suites with assertion helpers.

var runner = null  # Set by test_runner.gd
var _current_test_failed := false


func run_tests() -> void:
    ## Override in subclass. Call _test() for each test method.
    pass


func _test(name: String, callable: Callable) -> void:
    ## Run a single test with the given name.
    _runner._start_test(name)
    _current_test_failed = false

    callable.call()

    if not _current_test_failed:
        _runner._pass_test()


# ============================================================
# ASSERTIONS
# ============================================================


func assert_true(condition: bool, message: String = "Expected true") -> void:
    if not condition:
        _fail(message)


func assert_false(condition: bool, message: String = "Expected false") -> void:
    if condition:
        _fail(message)


func assert_eq(actual, expected, message: String = "") -> void:
    ## Assert equality with helpful error message.
    if actual != expected:
        var msg := message if message else "Expected %s but got %s" % [expected, actual]
        _fail(msg)


func assert_ne(actual, not_expected, message: String = "") -> void:
    ## Assert inequality.
    if actual == not_expected:
        var msg: String = message if message else "Expected value to not equal %s" % [not_expected]
        _fail(msg)


func assert_gt(actual: float, expected: float, message: String = "") -> void:
    ## Assert greater than.
    if actual <= expected:
        var msg := message if message else "Expected %s > %s" % [actual, expected]
        _fail(msg)


func assert_gte(actual: float, expected: float, message: String = "") -> void:
    ## Assert greater than or equal.
    if actual < expected:
        var msg := message if message else "Expected %s >= %s" % [actual, expected]
        _fail(msg)


func assert_lt(actual: float, expected: float, message: String = "") -> void:
    ## Assert less than.
    if actual >= expected:
        var msg := message if message else "Expected %s < %s" % [actual, expected]
        _fail(msg)


func assert_lte(actual: float, expected: float, message: String = "") -> void:
    ## Assert less than or equal.
    if actual > expected:
        var msg := message if message else "Expected %s <= %s" % [actual, expected]
        _fail(msg)


func assert_approx(
    actual: float, expected: float, epsilon: float = 0.0001, message: String = ""
) -> void:
    ## Assert approximate equality for floats.
    if abs(actual - expected) > epsilon:
        var msg := (
            message
            if message
            else "Expected %s to be approximately %s (epsilon=%s)" % [actual, expected, epsilon]
        )
        _fail(msg)


func assert_in_range(value: float, min_val: float, max_val: float, message: String = "") -> void:
    ## Assert value is within range [min_val, max_val].
    if value < min_val or value > max_val:
        var msg := (
            message
            if message
            else "Expected %s to be in range [%s, %s]" % [value, min_val, max_val]
        )
        _fail(msg)


func assert_array_eq(actual: Array, expected: Array, message: String = "") -> void:
    ## Assert arrays are equal element-by-element.
    if actual.size() != expected.size():
        var msg := (
            message
            if message
            else "Array size mismatch: %d vs %d" % [actual.size(), expected.size()]
        )
        _fail(msg)
        return

    for i in actual.size():
        if actual[i] != expected[i]:
            var msg := (
                message
                if message
                else "Array mismatch at index %d: %s vs %s" % [i, actual[i], expected[i]]
            )
            _fail(msg)
            return


func assert_not_null(value, message: String = "Expected non-null value") -> void:
    if value == null:
        _fail(message)


func assert_null(value, message: String = "Expected null value") -> void:
    if value != null:
        _fail(message)


func _fail(message: String) -> void:
    ## Mark current test as failed.
    if not _current_test_failed:
        _current_test_failed = true
        _runner._fail_test(message)
