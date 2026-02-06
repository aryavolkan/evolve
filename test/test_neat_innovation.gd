extends "res://test/test_base.gd"

## Tests for NeatInnovation — global innovation number tracker.


func _run_tests() -> void:
	_test("innovation_starts_at_zero", test_starts_at_zero)
	_test("innovation_sequential_allocation", test_sequential_allocation)
	_test("innovation_dedup_same_connection", test_dedup_same_connection)
	_test("innovation_different_connections_differ", test_different_connections_differ)
	_test("innovation_node_id_allocation", test_node_id_allocation)
	_test("innovation_node_id_initial_offset", test_node_id_initial_offset)
	_test("innovation_reset_cache", test_reset_cache)
	_test("innovation_reset_preserves_counter", test_reset_preserves_counter)
	_test("innovation_many_connections", test_many_connections)


func test_starts_at_zero() -> void:
	var tracker := NeatInnovation.new()
	assert_eq(tracker.get_next_innovation(), 0)
	assert_eq(tracker.get_next_node_id(), 0)


func test_sequential_allocation() -> void:
	var tracker := NeatInnovation.new()
	var i0 := tracker.get_innovation(0, 3)
	var i1 := tracker.get_innovation(1, 3)
	var i2 := tracker.get_innovation(2, 3)
	assert_eq(i0, 0)
	assert_eq(i1, 1)
	assert_eq(i2, 2)
	assert_eq(tracker.get_next_innovation(), 3)


func test_dedup_same_connection() -> void:
	var tracker := NeatInnovation.new()
	var first := tracker.get_innovation(0, 5)
	var second := tracker.get_innovation(0, 5)
	assert_eq(first, second, "Same connection should get same innovation")
	assert_eq(tracker.get_next_innovation(), 1, "Counter should only advance once")


func test_different_connections_differ() -> void:
	var tracker := NeatInnovation.new()
	var i_a := tracker.get_innovation(0, 3)
	var i_b := tracker.get_innovation(3, 0)  # Reversed direction
	assert_ne(i_a, i_b, "Different directions should get different innovations")


func test_node_id_allocation() -> void:
	var tracker := NeatInnovation.new()
	var n0 := tracker.allocate_node_id()
	var n1 := tracker.allocate_node_id()
	var n2 := tracker.allocate_node_id()
	assert_eq(n0, 0)
	assert_eq(n1, 1)
	assert_eq(n2, 2)


func test_node_id_initial_offset() -> void:
	var tracker := NeatInnovation.new(10)
	var n0 := tracker.allocate_node_id()
	assert_eq(n0, 10)
	assert_eq(tracker.get_next_node_id(), 11)


func test_reset_cache() -> void:
	var tracker := NeatInnovation.new()
	var first := tracker.get_innovation(0, 3)
	assert_eq(first, 0)
	tracker.reset_generation_cache()
	# Same connection after reset gets a NEW innovation number
	var after_reset := tracker.get_innovation(0, 3)
	assert_eq(after_reset, 1, "After reset, same connection should get new innovation")


func test_reset_preserves_counter() -> void:
	var tracker := NeatInnovation.new()
	tracker.get_innovation(0, 1)
	tracker.get_innovation(1, 2)
	assert_eq(tracker.get_next_innovation(), 2)
	tracker.reset_generation_cache()
	# Counter should not reset, only cache
	assert_eq(tracker.get_next_innovation(), 2)
	var new_innov := tracker.get_innovation(5, 6)
	assert_eq(new_innov, 2, "Should continue from where counter left off")


func test_many_connections() -> void:
	var tracker := NeatInnovation.new()
	var seen: Dictionary = {}
	for i in 50:
		var innov := tracker.get_innovation(i, i + 100)
		assert_false(seen.has(innov), "Innovation numbers must be unique")
		seen[innov] = true
	assert_eq(tracker.get_next_innovation(), 50)
