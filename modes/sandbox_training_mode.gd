extends "res://modes/standard_training_mode.gd"
class_name SandboxTrainingMode

## SANDBOX TRAINING: reuse standard training pipeline but honor sandbox config overrides.

var sandbox_cfg: Dictionary = {}


func enter(context) -> void:
	super.enter(context)


func exit() -> void:
	if ctx and ctx.has_method("clear_training_overrides"):
		ctx.clear_training_overrides()
	super.exit()


func _on_training_ready() -> void:
	ctx.set_training_overrides(_build_training_overrides())
	_seed_population_if_requested()


func _build_training_overrides() -> Dictionary:
	var overrides: Dictionary = {}
	var enemy_types: Array = sandbox_cfg.get("enemy_types", [])
	if enemy_types.size() > 0:
		overrides["enemy_types"] = enemy_types.duplicate()
	overrides["spawn_rate_multiplier"] = clampf(sandbox_cfg.get("spawn_rate_multiplier", 1.0), 0.25, 3.0)
	overrides["powerup_frequency"] = clampf(sandbox_cfg.get("powerup_frequency", 1.0), 0.25, 3.0)
	overrides["starting_difficulty"] = clampf(sandbox_cfg.get("starting_difficulty", 0.0), 0.0, 1.0)
	return overrides


func _seed_population_if_requested() -> void:
	var source: String = sandbox_cfg.get("training_network_source", "random")
	if source == "random":
		return
	if ctx.use_neat:
		push_warning("Sandbox training seed is not supported for NEAT runs; falling back to random population")
		return
	var network = _load_seed_network(source)
	if not network:
		return
	_seed_population_from_network(network)


func _load_seed_network(source: String):
	var path: String = ctx.BEST_NETWORK_PATH
	if source == "best":
		path = ctx.BEST_NETWORK_PATH
	elif source == "generation":
		var gen_index: int = maxi(1, int(sandbox_cfg.get("training_generation", 1)))
		path = ctx.BEST_NETWORK_PATH.replace(".nn", "_gen_%03d.nn" % gen_index)
	else:
		return null
	var network = ctx.NeuralNetworkScript.load_from_file(path)
	if not network:
		push_warning("Failed to load sandbox training seed network from %s" % path)
	return network


func _seed_population_from_network(network) -> void:
	if not ctx or not ctx.evolution:
		return
	if not network or not network.has_method("get_weights"):
		return
		
	var base_weights = network.get_weights()
	var pop_size = ctx.population_size if ctx.get("population_size") != null else 0
	
	for i in pop_size:
		var individual = ctx.evolution.get_individual(i)
		if individual == null:
			continue
		if individual.has_method("set_weights"):
			individual.set_weights(base_weights)
		if individual.has_method("reset_memory"):
			individual.reset_memory()
		if i > 0 and individual.has_method("mutate"):
			individual.mutate(ctx.config.mutation_rate, ctx.config.mutation_strength)
