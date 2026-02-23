extends CharacterBody2D
class_name Enemy

# Chess piece types with their point values
enum Type { PAWN, KNIGHT, BISHOP, ROOK, QUEEN }

@export var speed: float = 150.0
@export var type: Type = Type.PAWN

var player: CharacterBody2D
var point_value: int = 1
var rng: RandomNumberGenerator  # Per-arena RNG passed from Main scene

# AI-controlled enemy support (co-evolution Track A)
var ai_controlled: bool = false
var ai_network = null  # NeuralNetwork assigned by co-evolution
var _ai_controller = null  # EnemyAIController (created lazily)

# Movement state
var move_timer: float = 0.0
var move_cooldown: float = 0.8
var base_move_cooldown: float = 0.8  # Store original cooldown for slow effect
var is_moving: bool = false
var move_target: Vector2
var move_start: Vector2
var move_progress: float = 0.0
var move_duration: float = 0.3  # Changed from const to allow slowing
var base_move_duration: float = 0.3  # Store original for slow effect

# Chess piece textures
var death_effect_scene: PackedScene = preload("res://death_effect.tscn")

const PIECE_TEXTURES = {
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
    # Find nearest target in our local scene (handles multi-agent + SubViewport)
    player = find_nearest_target()
    apply_type_config()
    if rng:
        move_timer = rng.randf() * move_cooldown  # Stagger initial moves
    else:
        move_timer = randf() * move_cooldown  # Fallback for tests/standalone


func find_nearest_target() -> CharacterBody2D:
    ## Find the nearest "player" group member within our scene hierarchy.
    ## Works with single player, multi-agent rtNEAT, and SubViewport isolation.

    # Walk up to find the Main scene (our root)
    var main_node: Node = null
    var current = get_parent()
    while current:
        if current.name == "Main":
            main_node = current
            break
        current = current.get_parent()

    if main_node:
        # Find nearest player-group member that is a child of this Main scene
        var nearest: CharacterBody2D = null
        var nearest_dist: float = INF
        for child in main_node.get_children():
            if child is CharacterBody2D and child.is_in_group("player"):
                # Skip dead agents
                if child.get("is_dead") and child.is_dead:
                    continue
                var dist = global_position.distance_to(child.global_position)
                if dist < nearest_dist:
                    nearest_dist = dist
                    nearest = child
        if nearest:
            return nearest

    # Fallback to global search if not in a Main scene
    return get_tree().get_first_node_in_group("player")

func apply_type_config() -> void:
    var config = TYPE_CONFIG[type]
    point_value = config["points"]
    move_cooldown = config["cooldown"]
    base_move_cooldown = move_cooldown  # Store original
    speed *= config["speed_mult"]

    # Update collision shape (duplicate to avoid sharing between instances)
    var new_shape = RectangleShape2D.new()
    new_shape.size = Vector2(config["size"], config["size"])
    $CollisionShape2D.shape = new_shape

    # Update sprite texture and scale
    var texture: Texture2D = PIECE_TEXTURES.get(type)
    if texture:
        $Sprite2D.texture = texture
        var texture_size = texture.get_size()
        if texture_size.x > 0.0:
            var target_scale = config["size"] / texture_size.x
            $Sprite2D.scale = Vector2(target_scale, target_scale)

func _physics_process(delta: float) -> void:
    if not player:
        return

    # Frozen enemies don't move at all
    if is_frozen:
        velocity = Vector2.ZERO
        move_and_slide()
        return

    if is_moving:
        # Animate the move
        move_progress += delta / move_duration
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

    # Check if we hit a player via slide collision (use collider, not stored ref)
    for i in get_slide_collision_count():
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()
        if collider and collider.is_in_group("player") and collider.has_method("on_enemy_collision"):
            collider.on_enemy_collision(self)
            return

    # Backup: distance-based collision check (handles high time scales and tunneling)
    # Use cached player reference instead of find_nearest_target() every frame
    if player and is_instance_valid(player):
        var my_size: float = TYPE_CONFIG[type]["size"] * 0.5
        var player_size: float = 20.0  # Player half-size
        var collision_dist: float = my_size + player_size
        if global_position.distance_to(player.global_position) < collision_dist:
            player.on_enemy_collision(self)
            return

func setup_ai(network) -> void:
    ## Enable AI control with the given neural network.
    ## Creates an EnemyAIController with sensor and wires it up.
    var EnemyAIControllerScript = preload("res://ai/enemy_ai_controller.gd")
    ai_controlled = true
    ai_network = network
    _ai_controller = EnemyAIControllerScript.new(network)
    _ai_controller.set_enemy(self)


func calculate_next_move() -> void:
    # AI-controlled path: delegate to neural network controller
    if ai_controlled and _ai_controller:
        var move_offset: Vector2 = _ai_controller.get_move()
        if move_offset != Vector2.ZERO:
            move_start = position
            move_target = position + move_offset
            is_moving = true
        return

    # Retarget to nearest player each move cycle (supports multi-agent)
    player = find_nearest_target()
    if not player:
        return

    # Original hardcoded logic
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
    var tiles = 1 + (rng.randi() if rng else randi()) % 2
    return Vector2(dx, dy) * TILE_SIZE * tiles

func get_rook_move(to_player: Vector2) -> Vector2:
    # Straight line movement: pick dominant axis
    var tiles = 1 + (rng.randi() if rng else randi()) % 3  # 1-3 tiles

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


func die() -> void:
    if is_inside_tree():
        var effect = death_effect_scene.instantiate()
        effect.setup(global_position, TYPE_CONFIG[type]["size"], $Sprite2D.modulate, $Sprite2D.texture)
        get_parent().add_child(effect)
    queue_free()


func apply_slow(multiplier: float) -> void:
    ## Apply slow effect - increases cooldown and move duration (slower movement)
    move_cooldown = base_move_cooldown / multiplier  # Higher cooldown = slower
    move_duration = base_move_duration / multiplier  # Longer animation = slower
    speed *= multiplier


func remove_slow(multiplier: float) -> void:
    ## Remove slow effect - restore original timing
    move_cooldown = base_move_cooldown
    move_duration = base_move_duration
    speed /= multiplier


var is_frozen: bool = false
var frozen_speed: float = 0.0

func apply_freeze() -> void:
    ## Freeze enemy completely - stops all movement
    if not is_frozen:
        is_frozen = true
        frozen_speed = speed
        speed = 0.0
        # Visual feedback - turn enemy blue/white
        $Sprite2D.modulate = Color(0.7, 0.9, 1.0, 0.8)


func remove_freeze() -> void:
    ## Unfreeze enemy - restore movement
    if is_frozen:
        is_frozen = false
        speed = frozen_speed
        $Sprite2D.modulate = Color(1, 1, 1, 1)
