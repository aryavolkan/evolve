extends RefCounted
## Island model migration for NEAT multi-worker training.
## Extracted from training_manager.gd to reduce its responsibility.

const IMPORT_INTERVAL: int = 5          # Import every N generations
const MAX_IMMIGRANTS: int = 2           # Per normal import cycle
const STAGNATION_THRESHOLD: int = 3     # Trigger early import
const STAGNATION_IMMIGRANTS: int = 3    # More aggressive when stuck

var _imported_migrations: Dictionary = {}  # {"worker_id:generation": true}
var _generations_since_import: int = 0


func export_best(evolution, worker_id: String, generation: int, pool_dir: String) -> void:
	## Write best genome to migration pool so other workers can import it.
	if worker_id == "" or not evolution:
		return
	if not evolution.all_time_best_genome:
		return

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(pool_dir)
	)

	var data := {
		"worker_id": worker_id,
		"generation": generation,
		"fitness": evolution.all_time_best_fitness,
		"genome": evolution.all_time_best_genome.serialize(),
	}
	var path: String = pool_dir + worker_id + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


func try_import(evolution, worker_id: String, generation: int,
				generations_without_improvement: int, pool_dir: String) -> void:
	## Scan migration pool for foreign genomes and inject into population.
	if worker_id == "" or not evolution:
		return

	_generations_since_import += 1

	var stagnation_triggered := generations_without_improvement >= STAGNATION_THRESHOLD
	var interval_triggered := _generations_since_import >= IMPORT_INTERVAL

	if not stagnation_triggered and not interval_triggered:
		return

	var max_immigrants := MAX_IMMIGRANTS
	if stagnation_triggered:
		max_immigrants = STAGNATION_IMMIGRANTS

	var dir := DirAccess.open(pool_dir)
	if not dir:
		return

	var imported_count := 0
	var imported_from: Array[String] = []
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "" and imported_count < max_immigrants:
		if filename.ends_with(".json") and not filename.begins_with(worker_id):
			var path := pool_dir + filename
			var immigrant := _try_load_immigrant(path, evolution)
			if immigrant:
				evolution.inject_immigrant(immigrant)
				imported_count += 1
				imported_from.append(filename.get_basename())
		filename = dir.get_next()
	dir.list_dir_end()

	if imported_count > 0:
		_generations_since_import = 0
		var trigger := "stagnation" if stagnation_triggered else "interval"
		print("Migration [%s]: Imported %d immigrant(s) from workers %s" % [
			trigger, imported_count, imported_from
		])


func _try_load_immigrant(path: String, evolution) -> NeatGenome:
	## Try to load a foreign genome from a migration pool file.
	## Returns null if the file is invalid, already imported, or not worth it.
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return null
	file.close()

	var data: Dictionary = json.data
	var foreign_worker: String = str(data.get("worker_id", ""))
	var foreign_gen: int = int(data.get("generation", 0))
	var foreign_fitness: float = float(data.get("fitness", 0.0))

	# Skip if already imported this exact snapshot
	var import_key := "%s:%d" % [foreign_worker, foreign_gen]
	if _imported_migrations.has(import_key):
		return null
	_imported_migrations[import_key] = true

	# Skip if fitness is below our worst (not worth importing)
	var worst_fitness := INF
	for genome in evolution.population:
		worst_fitness = minf(worst_fitness, genome.fitness)
	if foreign_fitness <= worst_fitness:
		return null

	var genome_data = data.get("genome")
	if not genome_data or not genome_data is Dictionary:
		return null

	return NeatGenome.deserialize(genome_data, evolution.config, evolution.innovation_tracker)
