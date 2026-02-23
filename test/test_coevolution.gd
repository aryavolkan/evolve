extends "res://test/test_base.gd"
## Tests for the co-evolution coordinator.
## Verifies dual-population management, network architecture, and lifecycle.

var CoevolutionScript = preload("res://ai/coevolution.gd")
var NeuralNetworkScript = preload("res://ai/neural_network.gd")


func _run_tests() -> void:
    print("\n[CoEvolution Tests]")

    _test("initialization_creates_both_populations", _test_initialization_creates_both_populations)
    _test("enemy_network_architecture", _test_enemy_network_architecture)
    _test("player_network_architecture", _test_player_network_architecture)
    _test("set_and_evolve_players", _test_set_and_evolve_players)
    _test("set_and_evolve_enemies", _test_set_and_evolve_enemies)
    _test("evolve_both_advances_generation", _test_evolve_both_advances_generation)
    _test("get_stats_returns_both", _test_get_stats_returns_both)
    _test("signal_emitted_on_evolve", _test_signal_emitted_on_evolve)
    _test("independent_populations", _test_independent_populations)
    _test("custom_population_sizes", _test_custom_population_sizes)
    _test("enemy_constants", _test_enemy_constants)


# ============================================================
# Helpers
# ============================================================


func _make_coevo(player_pop: int = 20, enemy_pop: int = 20):
    return CoevolutionScript.new(
        player_pop, 86, 32, 6, enemy_pop, 3, 0.15, 0.3, 0.7
    )


func _set_all_fitness(coevo, pop_size: int, is_player: bool) -> void:
    for i in pop_size:
        var fitness := float(i + 1) * 10.0
        if is_player:
            coevo.set_player_fitness(i, fitness)
        else:
            coevo.set_enemy_fitness(i, fitness)


# ============================================================
# Tests
# ============================================================


func _test_initialization_creates_both_populations() -> void:
    var coevo = _make_coevo(20, 15)

    assert_not_null(coevo.player_evolution, "Player evolution should exist")
    assert_not_null(coevo.enemy_evolution, "Enemy evolution should exist")
    assert_eq(coevo.get_player_population_size(), 20, "Player pop size")
    assert_eq(coevo.get_enemy_population_size(), 15, "Enemy pop size")


func _test_enemy_network_architecture() -> void:
    var coevo = _make_coevo()
    var enemy_net = coevo.get_enemy_network(0)

    assert_not_null(enemy_net, "Should get enemy network")
    assert_eq(enemy_net.input_size, 16, "Enemy input size should be 16")
    assert_eq(enemy_net.hidden_size, 16, "Enemy hidden size should be 16")
    assert_eq(enemy_net.output_size, 8, "Enemy output size should be 8")


func _test_player_network_architecture() -> void:
    var coevo = _make_coevo()
    var player_net = coevo.get_player_network(0)

    assert_not_null(player_net, "Should get player network")
    assert_eq(player_net.input_size, 86, "Player input size should be 86")
    assert_eq(player_net.hidden_size, 32, "Player hidden size should be 32")
    assert_eq(player_net.output_size, 6, "Player output size should be 6")


func _test_set_and_evolve_players() -> void:
    var coevo = _make_coevo()
    _set_all_fitness(coevo, 20, true)
    coevo.evolve_players()

    assert_eq(coevo.player_evolution.get_generation(), 1, "Player should be gen 1")
    assert_eq(coevo.enemy_evolution.get_generation(), 0, "Enemy should still be gen 0")


func _test_set_and_evolve_enemies() -> void:
    var coevo = _make_coevo()
    _set_all_fitness(coevo, 20, false)
    coevo.evolve_enemies()

    assert_eq(coevo.enemy_evolution.get_generation(), 1, "Enemy should be gen 1")
    assert_eq(coevo.player_evolution.get_generation(), 0, "Player should still be gen 0")


func _test_evolve_both_advances_generation() -> void:
    var coevo = _make_coevo()
    _set_all_fitness(coevo, 20, true)
    _set_all_fitness(coevo, 20, false)
    coevo.evolve_both()

    assert_eq(coevo.get_generation(), 1, "Generation should be 1 after evolve_both")
    assert_eq(coevo.player_evolution.get_generation(), 1, "Player gen should be 1")
    assert_eq(coevo.enemy_evolution.get_generation(), 1, "Enemy gen should be 1")


func _test_get_stats_returns_both() -> void:
    var coevo = _make_coevo()
    var stats := coevo.get_stats()

    assert_true(stats.has("generation"), "Stats should have generation")
    assert_true(stats.has("player"), "Stats should have player stats")
    assert_true(stats.has("enemy"), "Stats should have enemy stats")
    assert_true(stats.player.has("population_size"), "Player stats should have population_size")
    assert_true(stats.enemy.has("population_size"), "Enemy stats should have population_size")


func _test_signal_emitted_on_evolve() -> void:
    var coevo = _make_coevo()
    _set_all_fitness(coevo, 20, true)
    _set_all_fitness(coevo, 20, false)

    # Create a helper object to capture signal emission
    var signal_tracker = SignalTracker.new()
    coevo.generation_complete.connect(signal_tracker.on_generation_complete)

    coevo.evolve_both()

    assert_true(signal_tracker.was_called, "generation_complete signal should be emitted")
    assert_eq(signal_tracker.generation, 1, "Signal should report generation 1")


# Helper class to track signal emissions
class SignalTracker:
    extends RefCounted
    var was_called := false
    var generation := -1
    var player_best := -1.0
    var enemy_best := -1.0

    func on_generation_complete(gen: int, p_best: float, e_best: float) -> void:
        was_called = true
        generation = gen
        player_best = p_best
        enemy_best = e_best


func _test_independent_populations() -> void:
    var coevo = _make_coevo()

    # Set different fitness for player and enemy
    for i in 20:
        coevo.set_player_fitness(i, float(i) * 100.0)
        coevo.set_enemy_fitness(i, float(20 - i) * 50.0)

    # Get networks before evolution — they should be different objects
    var player_net_0 = coevo.get_player_network(0)
    var enemy_net_0 = coevo.get_enemy_network(0)

    # Different architectures confirm independence
    assert_ne(
        player_net_0.input_size,
        enemy_net_0.input_size,
        "Player and enemy networks should have different architectures"
    )


func _test_custom_population_sizes() -> void:
    var coevo = CoevolutionScript.new(50, 86, 32, 6, 30, 5, 0.2, 0.4, 0.8)  # 50 players  # 30 enemies

    assert_eq(coevo.get_player_population_size(), 50, "Player pop should be 50")
    assert_eq(coevo.get_enemy_population_size(), 30, "Enemy pop should be 30")


func _test_enemy_constants() -> void:
    # Verify the architecture constants match the spec
    assert_eq(CoevolutionScript.ENEMY_INPUT_SIZE, 16, "Enemy inputs should be 16")
    assert_eq(CoevolutionScript.ENEMY_HIDDEN_SIZE, 16, "Enemy hidden should be 16")
    assert_eq(CoevolutionScript.ENEMY_OUTPUT_SIZE, 8, "Enemy outputs should be 8")
