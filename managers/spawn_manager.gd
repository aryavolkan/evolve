extends RefCounted
class_name SpawnManager

## Handles enemy spawning logic extracted from main.gd

# Chess piece spawn scenes
var pawn_scene: PackedScene = preload("res://pawn.tscn")
var knight_scene: PackedScene = preload("res://knight.tscn") 
var bishop_scene: PackedScene = preload("res://bishop.tscn")
var rook_scene: PackedScene = preload("res://rook.tscn")
var queen_scene: PackedScene = preload("res://queen.tscn")

# Object pools for enemies
var enemy_pools: Dictionary = {
	"pawn": null,
	"knight": null,
	"bishop": null,
	"rook": null,
	"queen": null
}

# Spawn configuration
var next_spawn_score: float = 50.0
var spawn_interval_decay: float = 0.98
const MIN_SPAWN_INTERVAL: float = 0.5
const SPAWN_DISTANCE_FROM_PLAYER: float = 600.0
const MIN_SPAWN_SEPARATION: float = 200.0

# References
var main_scene: Node2D
var player: CharacterBody2D
var object_pool_script: Script

# Current spawn state
var current_spawn_interval: float = 3.0
var time_since_last_spawn: float = 0.0
var spawned_positions: Array = []


func setup(p_main_scene: Node2D, p_player: CharacterBody2D, p_object_pool_script: Script) -> void:
	main_scene = p_main_scene
	player = p_player
	object_pool_script = p_object_pool_script
	
	# Initialize enemy object pools
	for enemy_type in enemy_pools:
		enemy_pools[enemy_type] = object_pool_script.new()
	
	enemy_pools.pawn.initialize(pawn_scene, 30)
	enemy_pools.knight.initialize(knight_scene, 20)
	enemy_pools.bishop.initialize(bishop_scene, 15)
	enemy_pools.rook.initialize(rook_scene, 10)
	enemy_pools.queen.initialize(queen_scene, 5)


func update_spawning(delta: float, score: float, training_mode: bool = false) -> void:
	time_since_last_spawn += delta
	
	# Score-based spawning
	if score >= next_spawn_score:
		next_spawn_score += 50.0 * (1.0 + score / 1000.0)
		spawn_random_enemy(training_mode)
		current_spawn_interval *= spawn_interval_decay
		current_spawn_interval = maxf(current_spawn_interval, MIN_SPAWN_INTERVAL)
	
	# Time-based spawning
	if time_since_last_spawn >= current_spawn_interval:
		spawn_random_enemy(training_mode)
		time_since_last_spawn = 0.0


func spawn_random_enemy(training_mode: bool = false) -> void:
	if not is_instance_valid(player):
		return
		
	var spawn_position := get_spawn_position()
	if spawn_position == Vector2.ZERO:
		return
		
	# Weighted spawn probabilities
	var weights := [50, 25, 15, 8, 2]  # pawn, knight, bishop, rook, queen
	var total_weight := 0
	for w in weights:
		total_weight += w
	
	var random_value := randi() % total_weight
	var accumulated := 0
	var enemy_type: String = "pawn"
	var types := ["pawn", "knight", "bishop", "rook", "queen"]
	
	for i in weights.size():
		accumulated += weights[i]
		if random_value < accumulated:
			enemy_type = types[i]
			break
	
	spawn_enemy(enemy_type, spawn_position)


func spawn_enemy(enemy_type: String, position: Vector2) -> Node2D:
	var enemy: Node2D
	
	if enemy_pools.has(enemy_type) and enemy_pools[enemy_type]:
		enemy = enemy_pools[enemy_type].acquire()
		if enemy.has_method("reset"):
			enemy.reset(position)
		else:
			enemy.position = position
	else:
		# Fallback to direct instantiation
		var scene: PackedScene
		match enemy_type:
			"knight": scene = knight_scene
			"bishop": scene = bishop_scene
			"rook": scene = rook_scene
			"queen": scene = queen_scene
			_: scene = pawn_scene
		
		enemy = scene.instantiate()
		enemy.position = position
		main_scene.add_child(enemy)
	
	# Track spawn position
	spawned_positions.append(position)
	if spawned_positions.size() > 20:
		spawned_positions.pop_front()
	
	return enemy


func get_spawn_position() -> Vector2:
	if not is_instance_valid(player):
		return Vector2.ZERO
		
	var attempts := 0
	var spawn_pos: Vector2
	var valid_spawn := false
	
	while not valid_spawn and attempts < 20:
		attempts += 1
		
		# Random position within arena bounds
		spawn_pos = Vector2(
			randf_range(100, main_scene.effective_arena_width - 100),
			randf_range(100, main_scene.effective_arena_height - 100)
		)
		
		# Check distance from player
		var dist_to_player := spawn_pos.distance_to(player.position)
		if dist_to_player < SPAWN_DISTANCE_FROM_PLAYER:
			continue
			
		# Check distance from other recent spawns
		valid_spawn = true
		for pos in spawned_positions:
			if spawn_pos.distance_to(pos) < MIN_SPAWN_SEPARATION:
				valid_spawn = false
				break
	
	return spawn_pos if valid_spawn else Vector2.ZERO


func spawn_specific_enemy_at(enemy_type: String, position: Vector2) -> Node2D:
	## Spawn a specific enemy type at exact position (for testing/training)
	return spawn_enemy(enemy_type, position)


func clear_all_enemies() -> void:
	## Remove all enemies from the scene
	for enemy in main_scene.get_tree().get_nodes_in_group("enemy"):
		if enemy.has_method("_recycle"):
			enemy._recycle()
		else:
			enemy.queue_free()
	spawned_positions.clear()


func reset() -> void:
	## Reset spawn manager state
	next_spawn_score = 50.0
	current_spawn_interval = 3.0
	time_since_last_spawn = 0.0
	spawned_positions.clear()
	clear_all_enemies()