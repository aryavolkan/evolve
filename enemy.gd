extends CharacterBody2D

# Chess piece types with their point values
enum Type { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

@export var speed: float = 150.0
@export var type: Type = Type.PAWN

var player: CharacterBody2D
var point_value: int = 1

# Movement state
var move_timer: float = 0.0
var move_cooldown: float = 0.8
var is_moving: bool = false
var move_target: Vector2
var move_start: Vector2
var move_progress: float = 0.0
const MOVE_DURATION: float = 0.3

# Chess piece textures
var PIECE_TEXTURES = {
	Type.PAWN: preload("res://assets/pawn_icon.svg"),
	Type.KNIGHT: preload("res://assets/knight_icon.svg"),
	Type.BISHOP: preload("res://assets/bishop_icon.svg"),
	Type.ROOK: preload("res://assets/rook_icon.svg"),
	Type.QUEEN: preload("res://assets/queen_icon.svg")
}

# Chess piece config: points, size, speed multiplier, move cooldown
const TYPE_CONFIG = {
	Type.PAWN: { "points": 1, "size": 28.0, "speed_mult": 1.0, "cooldown": 1.0 },
	Type.KNIGHT: { "points": 3, "size": 32.0, "speed_mult": 1.2, "cooldown": 1.2 },
	Type.BISHOP: { "points": 3, "size": 32.0, "speed_mult": 1.3, "cooldown": 0.9 },
	Type.ROOK: { "points": 5, "size": 36.0, "speed_mult": 1.1, "cooldown": 1.1 },
	Type.QUEEN: { "points": 9, "size": 40.0, "speed_mult": 1.4, "cooldown": 0.7 }
}

const TILE_SIZE: float = 50.0  # Virtual grid size for chess-like movement

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	apply_type_config()
	move_timer = randf() * move_cooldown  # Stagger initial moves

func apply_type_config() -> void:
	var config = TYPE_CONFIG[type]
	point_value = config["points"]
	move_cooldown = config["cooldown"]
	speed *= config["speed_mult"]

	# Update collision shape (duplicate to avoid sharing between instances)
	var new_shape = RectangleShape2D.new()
	new_shape.size = Vector2(config["size"], config["size"])
	$CollisionShape2D.shape = new_shape

	# Update sprite texture and scale
	$Sprite2D.texture = PIECE_TEXTURES[type]
	var texture_size = $Sprite2D.texture.get_size()
	var target_scale = config["size"] / texture_size.x
	$Sprite2D.scale = Vector2(target_scale, target_scale)

func _physics_process(delta: float) -> void:
	if not player:
		return

	if is_moving:
		# Animate the move
		move_progress += delta / MOVE_DURATION
		if move_progress >= 1.0:
			position = move_target
			is_moving = false
			move_progress = 0.0
		else:
			# Smooth interpolation with slight arc for knight
			var t = ease(move_progress, 0.5)  # Ease in-out
			position = move_start.lerp(move_target, t)
			if type == Type.KNIGHT:
				# Add a hop effect for knight
				var hop_height = 20.0 * sin(move_progress * PI)
				position.y -= hop_height
	else:
		# Wait for next move
		move_timer += delta
		if move_timer >= move_cooldown:
			move_timer = 0.0
			calculate_next_move()

	# Still use move_and_slide for collision detection
	velocity = Vector2.ZERO
	if is_moving:
		velocity = (move_target - position).normalized() * speed * 3
	move_and_slide()

	# Check if we hit the player
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider.is_in_group("player"):
			player.on_enemy_collision(self)
			return

func calculate_next_move() -> void:
	var to_player = player.global_position - global_position
	var move_offset: Vector2

	match type:
		Type.PAWN:
			# Pawn: moves one square toward player (straight lines only)
			move_offset = get_pawn_move(to_player)

		Type.KNIGHT:
			# Knight: L-shaped move (2+1 squares)
			move_offset = get_knight_move(to_player)

		Type.BISHOP:
			# Bishop: diagonal movement only
			move_offset = get_bishop_move(to_player)

		Type.ROOK:
			# Rook: straight lines (horizontal/vertical)
			move_offset = get_rook_move(to_player)

		Type.QUEEN:
			# Queen: can move like bishop or rook
			move_offset = get_queen_move(to_player)

	if move_offset != Vector2.ZERO:
		move_start = position
		move_target = position + move_offset
		is_moving = true

func get_pawn_move(to_player: Vector2) -> Vector2:
	# Move one tile in the dominant direction toward player
	if abs(to_player.x) > abs(to_player.y):
		return Vector2(sign(to_player.x) * TILE_SIZE, 0)
	else:
		return Vector2(0, sign(to_player.y) * TILE_SIZE)

func get_knight_move(to_player: Vector2) -> Vector2:
	# L-shaped: 2 squares in one direction, 1 in perpendicular
	var moves = [
		Vector2(2, 1), Vector2(2, -1), Vector2(-2, 1), Vector2(-2, -1),
		Vector2(1, 2), Vector2(1, -2), Vector2(-1, 2), Vector2(-1, -2)
	]

	# Find the L-move that gets closest to player
	var best_move = moves[0]
	var best_dist = INF
	for move in moves:
		var new_pos = position + move * TILE_SIZE
		var dist = new_pos.distance_to(player.global_position)
		if dist < best_dist:
			best_dist = dist
			best_move = move

	return best_move * TILE_SIZE

func get_bishop_move(to_player: Vector2) -> Vector2:
	# Diagonal movement: pick the diagonal direction closest to player
	var dx = sign(to_player.x) if to_player.x != 0 else 1
	var dy = sign(to_player.y) if to_player.y != 0 else 1

	# Move 1-2 tiles diagonally
	var tiles = 1 + randi() % 2
	return Vector2(dx, dy) * TILE_SIZE * tiles

func get_rook_move(to_player: Vector2) -> Vector2:
	# Straight line movement: pick dominant axis
	var tiles = 1 + randi() % 3  # 1-3 tiles

	if abs(to_player.x) > abs(to_player.y):
		return Vector2(sign(to_player.x) * TILE_SIZE * tiles, 0)
	else:
		return Vector2(0, sign(to_player.y) * TILE_SIZE * tiles)

func get_queen_move(to_player: Vector2) -> Vector2:
	# Queen can move like bishop or rook - pick whichever gets closer
	var bishop_move = get_bishop_move(to_player)
	var rook_move = get_rook_move(to_player)

	var bishop_dist = (position + bishop_move).distance_to(player.global_position)
	var rook_dist = (position + rook_move).distance_to(player.global_position)

	if bishop_dist < rook_dist:
		return bishop_move
	else:
		return rook_move

func get_point_value() -> int:
	return point_value
