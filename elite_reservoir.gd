extends RefCounted
class_name EliteReservoir

## Global reservoir for storing elite NEAT populations across runs.
## Allows injecting high-performing genomes into new training runs.

const RESERVOIR_DIR = "user://elite_reservoir"
const MAX_RESERVOIR_SIZE = 100
const TOP_PERCENT = 0.1  # Save top 10% of population

var reservoir_path: String


func _init() -> void:
    reservoir_path = RESERVOIR_DIR


func _get_reservoir_dir() -> String:
    return "user://elite_reservoir"


func save_elites(population: Array, best_fitness: float, run_id: String, metadata: Dictionary = {}) -> void:
    ## Save top performing genomes from a population to the reservoir.
    if population.is_empty():
        return

    # Sort by fitness (descending)
    var sorted := population.duplicate()
    sorted.sort_custom(func(a, b): return a.fitness > b.fitness)

    # Get top 10%
    var count := max(1, int(sorted.size() * TOP_PERCENT))
    var elites := sorted.slice(0, count)

    # Create elite entry
    var entry := {
        "id": run_id,
        "timestamp": Time.get_unix_time_from_system(),
        "best_fitness": best_fitness,
        "population_size": population.size(),
        "elite_count": elites.size(),
        "metadata": metadata,
        "genomes": [],
    }

    # Serialize genomes
    for genome in elites:
        entry.genomes.append(genome.serialize())

    # Save to reservoir
    _save_entry(entry)


func _save_entry(entry: Dictionary) -> void:
    # Ensure reservoir directory exists
    var dir := DirAccess.open("user://")
    if dir and not dir.dir_exists("elite_reservoir"):
        dir.make_dir("elite_reservoir")

    var path := "user://elite_reservoir/elite_%s.json" % entry.id
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(entry))
        file.close()
        _print("Saved elite entry: %s (fitness: %.1f)" % [entry.id, entry.best_fitness])

    # Enforce max size (FIFO)
    _enforce_max_size()


func _enforce_max_size() -> void:
    var dir := DirAccess.open("user://")
    if not dir or not dir.dir_exists("elite_reservoir"):
        return

    var files: Array = []
    dir.list_dir_begin()
    var f := dir.get_next()
    while f != "":
        if f.begins_with("elite_") and f.ends_with(".json"):
            files.append(f)
        f = dir.get_next()
    dir.list_dir_end()

    if files.size() > MAX_RESERVOIR_SIZE:
        # Sort by timestamp (oldest first)
        files.sort()
        var to_remove := files.size() - MAX_RESERVOIR_SIZE
        for i in range(to_remove):
            dir.remove("user://elite_reservoir/" + files[i])
        _print("Removed %d old elite entries" % to_remove)


func load_random_elites(count: int = 5) -> Array:
    ## Load random elites from the reservoir for injection (returns raw genome data).
    var dir := DirAccess.open("user://")
    if not dir or not dir.dir_exists("elite_reservoir"):
        _print("No elite reservoir directory")
        return []

    var files: Array = []
    dir.list_dir_begin()
    var f := dir.get_next()
    while f != "":
        if f.begins_with("elite_") and f.ends_with(".json"):
            files.append(f)
        f = dir.get_next()
    dir.list_dir_end()

    if files.is_empty():
        _print("No elites in reservoir")
        return []

    # Random selection
    files.shuffle()
    var selected := files.slice(0, min(count, files.size()))
    var elites: Array = []

    for elite_file in selected:
        var entry := _load_entry("user://elite_reservoir/" + elite_file)
        if entry and entry.has("genomes"):
            for genome_data in entry.genomes:
                elites.append(genome_data)

    _print("Loaded %d elite genomes from reservoir" % elites.size())
    return elites


func load_elites_as_genomes(count: int, config, innovation_tracker) -> Array:
    ## Load elites and deserialize as NeatGenome objects.
    ## Requires config and innovation_tracker for proper deserialization.
    var raw_elites := load_random_elites(count)
    var genomes: Array = []

    # Lazy import to avoid circular dependencies
    var NeatGenome = load("res://evolve-core/ai/neat/neat_genome.gd")

    for genome_data in raw_elites:
        var genome = NeatGenome.deserialize(genome_data, config, innovation_tracker)
        if genome:
            genomes.append(genome)

    _print("Deserialized %d elite genomes" % genomes.size())
    return genomes


func _load_entry(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return {}
    var json := JSON.new()
    var text := file.get_as_text()
    file.close()
    if json.parse(text) != OK:
        return {}
    return json.data


func get_reservoir_stats() -> Dictionary:
    var dir := DirAccess.open(_get_reservoir_dir())
    if not dir:
        return {"count": 0, "total_elites": 0}

    var count := 0
    var total_fitness := 0.0
    dir.list_dir_begin()
    var f := dir.get_next()
    while f != "":
        if f.begins_with("elite_") and f.ends_with(".json"):
            count += 1
            var entry := _load_entry(_get_reservoir_dir() + "/" + f)
            if entry.has("best_fitness"):
                total_fitness += entry.best_fitness
        f = dir.get_next()
    dir.list_dir_end()

    return {
        "count": count,
        "total_elites": count * 5,  # Approximate
        "avg_fitness": total_fitness / count if count > 0 else 0.0,
    }


func _print(msg: String) -> void:
    print("[EliteReservoir] ", msg)
