extends RefCounted
## TUI Bridge — writes arena states for the external terminal UI every 0.5s,
## and polls for commands written back by the TUI every physics tick.

var _arena_states_path: String = ""
var _tui_commands_path: String = ""
var _write_timer: float = 0.0
const WRITE_INTERVAL: float = 0.5

var _log_buffer: Array = []  # Array of {"ts": float, "msg": String}
const MAX_LOG_ENTRIES: int = 20

# Map training_manager Mode enum int → display string
const _MODE_NAMES: Dictionary = {
    0: "IDLE",        # Mode.HUMAN
    1: "TRAINING",    # Mode.TRAINING
    2: "PLAYBACK",    # Mode.PLAYBACK
    3: "PLAYBACK",    # Mode.GENERATION_PLAYBACK
    4: "PLAYBACK",    # Mode.ARCHIVE_PLAYBACK
    5: "COEVOLUTION", # Mode.COEVOLUTION
    6: "SANDBOX",     # Mode.SANDBOX
    7: "COMPARISON",  # Mode.COMPARISON
    8: "RTNEAT",      # Mode.RTNEAT
    9: "TEAMS",       # Mode.TEAMS
}


func setup() -> void:
    var user_dir: String = OS.get_user_data_dir()
    _arena_states_path = user_dir + "/arena_states.json"
    _tui_commands_path = user_dir + "/tui_commands.json"


## Called every physics frame from training_manager.
## Writes arena_states.json every WRITE_INTERVAL seconds.
## Returns a command dict (or null) if tui_commands.json was found.
func tick(delta: float, ctx, eval_states: Array):
    # Poll for commands first (every tick for low latency)
    var cmd = _poll_command()

    _write_timer += delta
    if _write_timer >= WRITE_INTERVAL:
        _write_timer = 0.0
        _write_state(ctx, eval_states)

    return cmd


func _write_state(ctx, eval_states: Array) -> void:
    var avg_fitness: float = ctx.history_avg_fitness[-1] if ctx.history_avg_fitness.size() > 0 else 0.0
    var min_fitness: float = ctx.history_min_fitness[-1] if ctx.history_min_fitness.size() > 0 else 0.0

    var neat_species_count: int = 0
    if ctx.use_neat and ctx.evolution != null:
        neat_species_count = ctx.evolution.get_stats().species_count

    var mode_str: String = _MODE_NAMES.get(int(ctx.current_mode), "IDLE")

    var state: Dictionary = {
        "timestamp": Time.get_unix_time_from_system(),
        "mode": mode_str,
        "generation": ctx.generation,
        "best_fitness": ctx.best_fitness,
        "all_time_best": ctx.all_time_best,
        "avg_fitness": avg_fitness,
        "min_fitness": min_fitness,
        "population_size": ctx.population_size,
        "time_scale": ctx.time_scale,
        "curriculum_stage": ctx.curriculum_stage,
        "curriculum_label": ctx.get_curriculum_label(),
        "use_neat": ctx.use_neat,
        "neat_species_count": neat_species_count,
        "generations_without_improvement": ctx.generations_without_improvement,
        "arenas": eval_states,
        "history_best": ctx.history_best_fitness.slice(-20),
        "history_avg": ctx.history_avg_fitness.slice(-20),
        "log": _log_buffer.duplicate(),
    }

    var json_text: String = JSON.stringify(state)
    var file = FileAccess.open(_arena_states_path, FileAccess.WRITE)
    if file:
        file.store_string(json_text)
        file.close()


func _poll_command():
    if not FileAccess.file_exists(_tui_commands_path):
        return null

    var file = FileAccess.open(_tui_commands_path, FileAccess.READ)
    if not file:
        return null

    var text: String = file.get_as_text()
    file.close()

    # Delete command file after reading so it is only processed once
    DirAccess.remove_absolute(_tui_commands_path)

    var cmd = JSON.parse_string(text)
    return cmd


## Add a message to the rolling log buffer (max MAX_LOG_ENTRIES).
func log_event(msg: String) -> void:
    _log_buffer.append({
        "ts": Time.get_unix_time_from_system(),
        "msg": msg,
    })
    if _log_buffer.size() > MAX_LOG_ENTRIES:
        _log_buffer = _log_buffer.slice(-MAX_LOG_ENTRIES)
