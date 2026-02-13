extends RefCounted

## Tracks parent-child lineage across generations for phylogenetic visualization.
## External to neural network / genome objects — records birth events at reproduction time.

const MAX_GENERATIONS: int = 50

# {id: {generation, parent_a_id, parent_b_id, fitness, origin}}
var records: Dictionary = {}
var _next_id: int = 0
var _generation_index: Dictionary = {}  # {generation: [id1, id2, ...]}


func record_birth(generation: int, parent_a_id: int, parent_b_id: int, fitness: float, origin: String) -> int:
	## Record a new individual born via reproduction. Returns assigned ID.
	var id := _next_id
	_next_id += 1
	records[id] = {
		"generation": generation,
		"parent_a_id": parent_a_id,
		"parent_b_id": parent_b_id,
		"fitness": fitness,
		"origin": origin,
	}
	if not _generation_index.has(generation):
		_generation_index[generation] = []
	_generation_index[generation].append(id)
	return id


func record_seed(generation: int, count: int) -> Array[int]:
	## Batch-register initial population (no parents). Returns array of IDs.
	var ids: Array[int] = []
	for i in count:
		var id := record_birth(generation, -1, -1, 0.0, "seed")
		ids.append(id)
	return ids


func update_fitness(id: int, fitness: float) -> void:
	## Update fitness after evaluation.
	if records.has(id):
		records[id].fitness = fitness


func get_ancestry(id: int, max_depth: int = 20) -> Dictionary:
	## BFS backward from id, returns {nodes: [{id, generation, fitness, origin}], edges: [{from_id, to_id}]}.
	var nodes: Array = []
	var edges: Array = []
	var visited: Dictionary = {}
	var queue: Array = [id]
	var depth_map: Dictionary = {id: 0}

	while not queue.is_empty():
		var current: int = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true

		if not records.has(current):
			continue

		var rec: Dictionary = records[current]
		nodes.append({
			"id": current,
			"generation": rec.generation,
			"fitness": rec.fitness,
			"origin": rec.origin,
		})

		var current_depth: int = depth_map.get(current, 0)
		if current_depth >= max_depth:
			continue

		# Trace parent_a
		if rec.parent_a_id >= 0 and records.has(rec.parent_a_id):
			edges.append({"from_id": rec.parent_a_id, "to_id": current})
			if not visited.has(rec.parent_a_id):
				queue.append(rec.parent_a_id)
				depth_map[rec.parent_a_id] = current_depth + 1

		# Trace parent_b
		if rec.parent_b_id >= 0 and records.has(rec.parent_b_id):
			edges.append({"from_id": rec.parent_b_id, "to_id": current})
			if not visited.has(rec.parent_b_id):
				queue.append(rec.parent_b_id)
				depth_map[rec.parent_b_id] = current_depth + 1

	return {"nodes": nodes, "edges": edges}


func get_generation_ids(generation: int) -> Array:
	## All IDs born in that generation.
	return _generation_index.get(generation, [])


func get_best_id(generation: int) -> int:
	## Highest fitness individual in a generation. Returns -1 if none.
	var ids: Array = get_generation_ids(generation)
	if ids.is_empty():
		return -1
	var best_id: int = -1
	var best_fit: float = -INF
	for id in ids:
		if records.has(id) and records[id].fitness > best_fit:
			best_fit = records[id].fitness
			best_id = id
	return best_id


func prune_old(current_generation: int) -> void:
	## Remove records older than MAX_GENERATIONS.
	var cutoff: int = current_generation - MAX_GENERATIONS
	var gens_to_remove: Array = []
	for gen in _generation_index:
		if gen < cutoff:
			gens_to_remove.append(gen)
	for gen in gens_to_remove:
		for id in _generation_index[gen]:
			records.erase(id)
		_generation_index.erase(gen)


func clear() -> void:
	## Reset all data.
	records.clear()
	_generation_index.clear()
	_next_id = 0


func get_record(id: int) -> Dictionary:
	## Single record lookup.
	return records.get(id, {})


func get_stats() -> Dictionary:
	## Summary stats.
	var oldest: int = 999999
	for gen in _generation_index:
		oldest = mini(oldest, gen)
	if oldest == 999999:
		oldest = 0
	return {
		"total_records": records.size(),
		"generations_tracked": _generation_index.size(),
		"oldest_generation": oldest,
	}
