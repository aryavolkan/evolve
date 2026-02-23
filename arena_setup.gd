class_name ArenaSetup
extends RefCounted

## Handles arena initialization: walls, floor, camera, obstacle placement.

const ARENA_WALL_THICKNESS: float = 40.0


func setup_arena(
    scene: Node2D,
    player: CharacterBody2D,
    arena_width: float,
    arena_height: float
) -> Camera2D:
    ## Create the arena with walls and a static camera. Returns the arena camera.
    var arena_center = Vector2(arena_width / 2, arena_height / 2)

    # Disable player's camera
    var player_camera = player.get_node_or_null("Camera2D")
    if player_camera:
        player_camera.enabled = false

    # Position player at arena center
    player.position = arena_center

    # Create arena walls and floor
    _create_arena_walls(scene, arena_width, arena_height)
    _create_arena_floor(scene, arena_width, arena_height)

    # Create static camera centered on arena
    var arena_camera = Camera2D.new()
    arena_camera.position = arena_center
    scene.add_child(arena_camera)
    arena_camera.make_current()

    return arena_camera


static func update_camera_zoom(
    arena_camera: Camera2D,
    arena_width: float,
    arena_height: float
) -> void:
    ## Update camera zoom to fit arena in current viewport.
    if not arena_camera:
        return
    var viewport_size = arena_camera.get_viewport().get_visible_rect().size
    var zoom_x = viewport_size.x / arena_width
    var zoom_y = viewport_size.y / arena_height
    var zoom_level = min(zoom_x, zoom_y)
    arena_camera.zoom = Vector2(zoom_level, zoom_level)


static func get_arena_bounds(arena_width: float, arena_height: float) -> Rect2:
    ## Return the playable arena bounds (inside the walls).
    var wall_inner = ARENA_WALL_THICKNESS
    return Rect2(wall_inner, wall_inner,
                arena_width - wall_inner * 2,
                arena_height - wall_inner * 2)


func _create_arena_walls(scene: Node2D, arena_width: float, arena_height: float) -> void:
    var wall_thickness = ARENA_WALL_THICKNESS
    var wall_positions = [
        {"pos": Vector2(arena_width / 2, wall_thickness / 2),
        "size": Vector2(arena_width, wall_thickness)},
        {"pos": Vector2(arena_width / 2, arena_height - wall_thickness / 2),
        "size": Vector2(arena_width, wall_thickness)},
        {"pos": Vector2(wall_thickness / 2, arena_height / 2),
        "size": Vector2(wall_thickness, arena_height - wall_thickness * 2)},
        {"pos": Vector2(arena_width - wall_thickness / 2, arena_height / 2),
        "size": Vector2(wall_thickness, arena_height - wall_thickness * 2)}
    ]

    for wall_data in wall_positions:
        var wall = StaticBody2D.new()
        wall.position = wall_data.pos
        wall.collision_layer = 4
        wall.collision_mask = 0

        var collision = CollisionShape2D.new()
        collision.position = Vector2.ZERO
        var shape = RectangleShape2D.new()
        shape.size = wall_data.size
        collision.shape = shape
        wall.add_child(collision)

        var rect = ColorRect.new()
        rect.size = wall_data.size
        rect.position = -wall_data.size / 2
        rect.color = Color(0.25, 0.3, 0.45, 1)
        rect.z_index = 5
        wall.add_child(rect)

        var inner_size = wall_data.size - Vector2(6, 6)
        if inner_size.x > 0 and inner_size.y > 0:
            var highlight = ColorRect.new()
            highlight.size = inner_size
            highlight.position = -inner_size / 2
            highlight.color = Color(0.35, 0.4, 0.55, 1)
            highlight.z_index = 6
            wall.add_child(highlight)

        wall.add_to_group("wall")
        scene.add_child(wall)


func _create_arena_floor(scene: Node2D, arena_width: float, arena_height: float) -> void:
    var floor_rect = ColorRect.new()
    floor_rect.position = Vector2(0, 0)
    floor_rect.size = Vector2(arena_width, arena_height)
    floor_rect.color = Color(0.08, 0.08, 0.12, 1)
    floor_rect.z_index = -10
    scene.add_child(floor_rect)

    var grid_size = 160.0
    for x in range(int(arena_width / grid_size) + 1):
        var line = ColorRect.new()
        line.position = Vector2(x * grid_size - 1, 0)
        line.size = Vector2(2, arena_height)
        line.color = Color(0.12, 0.12, 0.18, 0.5)
        line.z_index = -9
        scene.add_child(line)

    for y in range(int(arena_height / grid_size) + 1):
        var line = ColorRect.new()
        line.position = Vector2(0, y * grid_size - 1)
        line.size = Vector2(arena_width, 2)
        line.color = Color(0.12, 0.12, 0.18, 0.5)
        line.z_index = -9
        scene.add_child(line)
