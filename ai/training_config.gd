extends RefCounted
## Centralized training hyperparameters.
## Loads from sweep_config.json with typed defaults.
## Extracted from training_manager.gd to reduce its responsibility.

# Evolution parameters
var population_size: int = 150
var max_generations: int = 100
var evals_per_individual: int = 2
var hidden_size: int = 80
var elite_count: int = 20
var mutation_rate: float = 0.30
var mutation_strength: float = 0.09
var crossover_rate: float = 0.73

# Training parameters
var time_scale: float = 16.0
var parallel_count: int = 20

# Feature flags
var use_neat: bool = false
var use_nsga2: bool = false
var use_memory: bool = false
var use_map_elites: bool = true
var curriculum_enabled: bool = true
var map_elites_grid_size: int = 20

# Worker/sweep
var worker_id: String = ""

# Paths
const BEST_NETWORK_PATH := "user://best_network.nn"
const POPULATION_PATH := "user://population.evo"
const SWEEP_CONFIG_PATH := "user://sweep_config.json"
const METRICS_PATH := "user://metrics.json"
const ENEMY_POPULATION_PATH := "user://enemy_population.evo"
const ENEMY_HOF_PATH := "user://enemy_hof.evo"
const MIGRATION_POOL_DIR := "user://migration_pool/"

# Raw sweep dict (for any custom keys not covered above)
var _raw: Dictionary = {}


func load_from_sweep(fallback_pop_size: int = 150, fallback_max_gen: int = 100) -> void:
	## Load hyperparameters from sweep_config.json, applying fallbacks.
	_parse_worker_id()
	_raw = _load_json()

	population_size = maxi(1, int(_raw.get("population_size", fallback_pop_size)))
	max_generations = maxi(1, int(_raw.get("max_generations", fallback_max_gen)))
	evals_per_individual = maxi(1, int(_raw.get("evals_per_individual", evals_per_individual)))
	time_scale = maxf(0.1, float(_raw.get("time_scale", 16.0)))
	parallel_count = maxi(1, int(_raw.get("parallel_count", parallel_count)))
	hidden_size = maxi(1, int(_raw.get("hidden_size", hidden_size)))
	elite_count = maxi(0, int(_raw.get("elite_count", elite_count)))
	mutation_rate = clampf(float(_raw.get("mutation_rate", mutation_rate)), 0.0, 1.0)
	mutation_strength = maxf(0.0, float(_raw.get("mutation_strength", mutation_strength)))
	crossover_rate = clampf(float(_raw.get("crossover_rate", crossover_rate)), 0.0, 1.0)
	use_neat = bool(_raw.get("use_neat", use_neat))
	use_nsga2 = bool(_raw.get("use_nsga2", use_nsga2))
	use_memory = bool(_raw.get("use_memory", use_memory))
	use_map_elites = bool(_raw.get("use_map_elites", use_map_elites))
	curriculum_enabled = bool(_raw.get("curriculum_enabled", curriculum_enabled))
	map_elites_grid_size = maxi(1, int(_raw.get("map_elites_grid_size", map_elites_grid_size)))


func get_metrics_path() -> String:
	if worker_id != "":
		return "user://metrics_%s.json" % worker_id
	return METRICS_PATH


func get_raw(key: String, default = null):
	## Access raw sweep config for any custom keys.
	return _raw.get(key, default)


func _parse_worker_id() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--worker-id="):
			worker_id = arg.substr(12)
			break


func _load_json() -> Dictionary:
	var config_path = SWEEP_CONFIG_PATH
	if worker_id != "":
		var worker_path = "user://sweep_config_%s.json" % worker_id
		if FileAccess.file_exists(worker_path):
			config_path = worker_path
	if not FileAccess.file_exists(config_path):
		return {}
	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		return {}
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	if error != OK:
		push_error("Failed to parse JSON from %s" % config_path)
		return {}
	# Ensure json.data is a Dictionary
	if json.data is Dictionary:
		print("Loaded sweep config from %s: %s" % [config_path, json.data])
		return json.data
	else:
		push_error("Invalid JSON data type in %s: expected Dictionary" % config_path)
		return {}
