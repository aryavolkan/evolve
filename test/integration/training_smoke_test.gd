extends SceneTree
## Training mode smoke test — verifies the AI training loop completes
## at least 2 generations without crashing.
##
## Usage:
##   godot --headless --script test/integration/training_smoke_test.gd

var _main_scene: Node2D = null
var _training_mgr = null
var _frame_count := 0
var _started := false
var _passed := false
var _checks_done := false
var _errors: Array[String] = []
const MAX_FRAMES := 18000  # ~5 min at 60fps; should be enough for 2 gens


func _init() -> void:
    print("\n========================================")
    print("  TRAINING SMOKE TEST")
    print("========================================\n")


func _process(delta: float) -> bool:
    if not _started:
        _started = true
        _boot()
        return false

    _frame_count += 1

    if _frame_count % 600 == 0:
        _print_status()

    # Check completion conditions
    if _training_mgr and not _checks_done:
        var stats: Dictionary = _training_mgr.get_stats()
        var gen: int = stats.get("generation", 0)

        # Success: completed at least 2 generations
        if gen >= 2:
            _passed = true
            _checks_done = true
            print("  PASS: Training completed %d generations" % gen)
            print("  PASS: Best fitness = %.1f" % stats.get("all_time_best", 0.0))
            print("  PASS: Curriculum stage = %d" % stats.get("curriculum_stage", 0))
            _finish()
            return true

    # Timeout
    if _frame_count >= MAX_FRAMES:
        if not _checks_done:
            _errors.append(
                "Timeout: training did not complete 2 generations in %d frames" % MAX_FRAMES
            )
            _finish()
        return true

    return false


func _boot() -> void:
    # Load and instantiate main scene
    var scene_packed := load("res://main.tscn") as PackedScene
    if not scene_packed:
        _errors.append("Failed to load main.tscn")
        _finish()
        return

    _main_scene = scene_packed.instantiate() as Node2D
    if not _main_scene:
        _errors.append("Failed to instantiate main scene")
        _finish()
        return

    root.add_child(_main_scene)
    paused = false

    # Wait a frame for _ready to complete, then find training manager
    call_deferred("_start_training")


func _start_training() -> void:
    # Find the training manager (added as child in main._ready)
    for child in _main_scene.get_children():
        if child.has_method("start_training"):
            _training_mgr = child
            break

    if not _training_mgr:
        _errors.append("Training manager not found on main scene")
        _finish()
        return

    # Clear any sweep config that might override our small test settings
    var sweep_paths := ["user://sweep_config.json"]
    for path in sweep_paths:
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)

    print("  Starting training (pop=20, max_gen=5, parallel=4)...")
    # Use small population for speed — set BEFORE calling start_training
    # start_training reads _sweep_config internally, so we pass args
    _training_mgr.stagnation_limit = 100  # Don't early stop during smoke test
    Engine.time_scale = 16.0
    _training_mgr.start_training(20, 5)
    # Override settings that start_training may have loaded from sweep config
    _training_mgr.population_size = 20
    _training_mgr.parallel_count = 4
    _training_mgr.evals_per_individual = 1
    print("  Training started")


func _print_status() -> void:
    if not _training_mgr:
        return
    var stats: Dictionary = _training_mgr.get_stats()
    print(
        (
            "  Frame %d | Gen %d | Eval %d/%d | Best %.0f"
            % [
                _frame_count,
                stats.get("generation", 0),
                stats.get("evaluated_count", 0),
                stats.get("population_size", 0),
                stats.get("all_time_best", 0.0),
            ]
        )
    )


func _finish() -> void:
    _checks_done = true
    Engine.time_scale = 1.0

    print("\n========================================")
    print("  TRAINING SMOKE TEST RESULT")
    print("========================================")

    if _errors.size() > 0:
        print("  FAILED")
        for e in _errors:
            print("    ✗ %s" % e)
        quit(1)
    elif _passed:
        print("  PASSED")
        quit(0)
    else:
        print("  INCONCLUSIVE")
        quit(1)
