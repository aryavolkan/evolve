extends "res://test/test_base.gd"

## Tests for ai/lineage_tracker.gd

var TrackerScript = preload("res://ai/lineage_tracker.gd")


func run_tests() -> void:
    print("\n[Lineage Tracker Tests]")

    _test(
        "creates_without_error",
        func():
            var tracker = TrackerScript.new()
            assert_not_null(tracker)
    )

    _test(
        "record_seed_assigns_ids",
        func():
            var tracker = TrackerScript.new()
            var ids: Array[int] = tracker.record_seed(0, 5)
            assert_eq(ids.size(), 5, "Should return 5 IDs")
            assert_eq(ids[0], 0, "First ID should be 0")
            assert_eq(ids[4], 4, "Last ID should be 4")
            # All should have origin "seed" and no parents
            var rec = tracker.get_record(0)
            assert_eq(rec.origin, "seed")
            assert_eq(rec.parent_a_id, -1)
            assert_eq(rec.parent_b_id, -1)
    )

    _test(
        "record_birth_increments_id",
        func():
            var tracker = TrackerScript.new()
            var id1 = tracker.record_birth(0, -1, -1, 0.0, "seed")
            var id2 = tracker.record_birth(0, -1, -1, 0.0, "seed")
            var id3 = tracker.record_birth(1, id1, id2, 0.0, "crossover")
            assert_eq(id1, 0)
            assert_eq(id2, 1)
            assert_eq(id3, 2)
    )

    _test(
        "record_birth_stores_parents",
        func():
            var tracker = TrackerScript.new()
            var ids = tracker.record_seed(0, 3)
            var child_id = tracker.record_birth(1, ids[0], ids[1], 50.0, "crossover")
            var rec = tracker.get_record(child_id)
            assert_eq(rec.parent_a_id, ids[0], "Parent A should match")
            assert_eq(rec.parent_b_id, ids[1], "Parent B should match")
            assert_eq(rec.generation, 1, "Generation should be 1")
            assert_eq(rec.origin, "crossover")
    )

    _test(
        "update_fitness_modifies_record",
        func():
            var tracker = TrackerScript.new()
            var ids = tracker.record_seed(0, 3)
            assert_approx(tracker.get_record(ids[1]).fitness, 0.0, 0.01)
            tracker.update_fitness(ids[1], 123.5)
            assert_approx(tracker.get_record(ids[1]).fitness, 123.5, 0.01)
    )

    _test(
        "get_ancestry_traces_parents",
        func():
            var tracker = TrackerScript.new()
            # Gen 0: seeds
            var gen0 = tracker.record_seed(0, 2)
            # Gen 1: child of gen0[0]
            var gen1_id = tracker.record_birth(1, gen0[0], -1, 10.0, "mutation")
            # Gen 2: child of gen1
            var gen2_id = tracker.record_birth(2, gen1_id, -1, 20.0, "mutation")

            var ancestry = tracker.get_ancestry(gen2_id)
            assert_eq(ancestry.nodes.size(), 3, "Should trace 3 nodes")
            assert_eq(ancestry.edges.size(), 2, "Should have 2 edges")
    )

    _test(
        "get_ancestry_handles_crossover",
        func():
            var tracker = TrackerScript.new()
            var gen0 = tracker.record_seed(0, 3)
            # Crossover from two parents
            var child_id = tracker.record_birth(1, gen0[0], gen0[1], 15.0, "crossover")
            var ancestry = tracker.get_ancestry(child_id)
            # child + 2 parents = 3 nodes
            assert_eq(ancestry.nodes.size(), 3, "Should include child and both parents")
            # 2 edges (parent_a -> child, parent_b -> child)
            assert_eq(ancestry.edges.size(), 2, "Should have 2 edges for crossover")
    )

    _test(
        "get_ancestry_respects_depth",
        func():
            var tracker = TrackerScript.new()
            # Build a chain: gen0 -> gen1 -> gen2 -> gen3
            var prev_id: int = tracker.record_birth(0, -1, -1, 0.0, "seed")
            for i in range(1, 4):
                prev_id = tracker.record_birth(i, prev_id, -1, float(i), "mutation")
            # Trace from gen3 with max_depth=1 — should only get gen3 + gen2
            var ancestry = tracker.get_ancestry(prev_id, 1)
            assert_eq(ancestry.nodes.size(), 2, "Depth 1 should get 2 nodes")
    )

    _test(
        "prune_old_removes_generations",
        func():
            var tracker = TrackerScript.new()
            # Create records across many generations
            for gen in range(60):
                tracker.record_birth(gen, -1, -1, float(gen), "seed")
            assert_gt(tracker.get_stats().total_records, 50.0)
            # Prune with current gen = 55
            tracker.prune_old(55)
            var stats = tracker.get_stats()
            # Should only keep generations >= 55 - MAX_GENERATIONS = 5
            assert_true(stats.oldest_generation >= 5, "Oldest should be >= 5 after prune")
            # Records from gen 0-4 should be gone
            assert_eq(tracker.get_generation_ids(0).size(), 0, "Gen 0 should be pruned")
            assert_eq(tracker.get_generation_ids(4).size(), 0, "Gen 4 should be pruned")
    )

    _test(
        "get_best_id_returns_highest_fitness",
        func():
            var tracker = TrackerScript.new()
            var ids = tracker.record_seed(0, 5)
            tracker.update_fitness(ids[0], 10.0)
            tracker.update_fitness(ids[1], 50.0)
            tracker.update_fitness(ids[2], 30.0)
            tracker.update_fitness(ids[3], 50.1)
            tracker.update_fitness(ids[4], 5.0)
            var best = tracker.get_best_id(0)
            assert_eq(best, ids[3], "Should return ID with highest fitness")
    )
