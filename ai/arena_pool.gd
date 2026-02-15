extends RefCounted
## Manages a grid of SubViewport containers for parallel arena display.
## Handles viewport creation, grid layout, fullscreen toggle, and resize.
## Does NOT know about AI controllers, evolution, or game logic.
## Extracted from training_manager.gd to reduce its responsibility.

# Visual layer
var canvas_layer: CanvasLayer = null
var container: Control = null       # Root Control holding background + stats + slots
var stats_label: Label = null

# Slots: each is {container: SubViewportContainer, viewport: SubViewport, index: int}
var slots: Array = []
var fullscreen_index: int = -1      # -1 = grid view

# Layout config
var parallel_count: int = 20
var _tree: SceneTree = null
var _resize_connected: bool = false


func setup(tree: SceneTree, count: int, layer_name: String = "TrainingCanvasLayer", stats_color: Color = Color.YELLOW) -> void:
	## Create the CanvasLayer, background, and stats label.
	## Must be called before creating any slots.
	_tree = tree
	parallel_count = count

	canvas_layer = CanvasLayer.new()
	canvas_layer.name = layer_name
	canvas_layer.layer = 100  # On top of everything
	tree.root.add_child(canvas_layer)

	container = Control.new()
	container.name = "Container"
	canvas_layer.add_child(container)

	# Background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.05, 0.05, 0.08, 1)
	container.add_child(bg)

	# Stats label at top
	stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.position = Vector2(10, 8)
	stats_label.add_theme_font_size_override("font_size", 20)
	stats_label.add_theme_color_override("font_color", stats_color)
	container.add_child(stats_label)

	# Set initial size
	_update_container_size()

	# Connect to window resize
	tree.root.size_changed.connect(_on_window_resized)
	_resize_connected = true


func create_slot() -> Dictionary:
	## Create a new SubViewportContainer + SubViewport at the next grid position.
	## Returns {container: SubViewportContainer, viewport: SubViewport, index: int}.
	var idx := slots.size()
	var grid = get_grid_dimensions()
	var grid_x: int = idx % grid.cols
	var grid_y: int = idx / grid.cols

	var svc = SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_PASS
	container.add_child(svc)

	# Position immediately
	var win_size = get_window_size()
	var gap = 4
	var top_margin = 40
	var arena_w = (win_size.x - gap * (grid.cols + 1)) / grid.cols
	var arena_h = (win_size.y - top_margin - gap * (grid.rows + 1)) / grid.rows
	var x = gap + grid_x * (arena_w + gap)
	var y = top_margin + gap + grid_y * (arena_h + gap)
	svc.position = Vector2(x, y)
	svc.size = Vector2(arena_w, arena_h)

	var viewport = SubViewport.new()
	viewport.size = Vector2(640, 360)  # Reduced from 1280×720 — training grid renders tiny
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	svc.add_child(viewport)

	var slot := {"container": svc, "viewport": viewport, "index": idx}
	slots.append(slot)

	# Handle fullscreen state for new slots
	if fullscreen_index >= 0 and idx != fullscreen_index:
		svc.visible = false

	return slot


func get_viewport(slot_index: int) -> SubViewport:
	## Get the viewport for a slot (to add game scenes to).
	if slot_index < 0 or slot_index >= slots.size():
		return null
	return slots[slot_index].viewport


func replace_slot(slot_index: int) -> Dictionary:
	## Destroy the old container at slot_index, create a new one at the same grid position.
	## Returns the new {container, viewport, index}.
	if slot_index < 0 or slot_index >= slots.size():
		return {}

	var grid = get_grid_dimensions()
	var grid_x: int = slot_index % grid.cols
	var grid_y: int = slot_index / grid.cols

	# Remove old
	var old = slots[slot_index]
	if is_instance_valid(old.container):
		old.container.queue_free()

	# Create new
	var svc = SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_PASS
	container.add_child(svc)

	var win_size = get_window_size()
	var gap = 4
	var top_margin = 40
	var arena_w = (win_size.x - gap * (grid.cols + 1)) / grid.cols
	var arena_h = (win_size.y - top_margin - gap * (grid.rows + 1)) / grid.rows
	var x = gap + grid_x * (arena_w + gap)
	var y = top_margin + gap + grid_y * (arena_h + gap)
	svc.position = Vector2(x, y)
	svc.size = Vector2(arena_w, arena_h)

	var viewport = SubViewport.new()
	viewport.size = Vector2(640, 360)  # Reduced from 1280×720 — training grid renders tiny
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = false
	svc.add_child(viewport)

	var slot := {"container": svc, "viewport": viewport, "index": slot_index}
	slots[slot_index] = slot

	# Handle fullscreen state
	if fullscreen_index >= 0:
		if slot_index == fullscreen_index:
			_apply_fullscreen_layout()
		else:
			svc.visible = false

	return slot


func remove_slot(slot_index: int) -> void:
	## Destroy a single slot's container.
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot = slots[slot_index]
	if is_instance_valid(slot.container):
		slot.container.queue_free()


func cleanup_all() -> void:
	## Destroy all SubViewportContainers but keep the canvas layer.
	for slot in slots:
		if is_instance_valid(slot.container):
			slot.container.queue_free()
	slots.clear()
	fullscreen_index = -1


func destroy() -> void:
	## Tear down everything: slots + canvas layer. Call on mode exit.
	cleanup_all()
	if _resize_connected and _tree and _tree.root.size_changed.is_connected(_on_window_resized):
		_tree.root.size_changed.disconnect(_on_window_resized)
		_resize_connected = false
	if canvas_layer:
		canvas_layer.queue_free()
		canvas_layer = null
	container = null
	stats_label = null


func set_stats_text(text: String) -> void:
	## Update the top stats bar label.
	if stats_label:
		stats_label.text = text


func enter_fullscreen(slot_index: int) -> void:
	## Expand the arena at slot_index to fullscreen.
	if slot_index < 0 or slot_index >= slots.size():
		return

	fullscreen_index = slot_index

	# Hide all other arena containers
	for i in slots.size():
		if i != slot_index and is_instance_valid(slots[i].container):
			slots[i].container.visible = false

	_apply_fullscreen_layout()


func exit_fullscreen() -> void:
	## Return from fullscreen to grid view.
	fullscreen_index = -1

	# Show all arena containers
	for i in slots.size():
		if is_instance_valid(slots[i].container):
			slots[i].container.visible = true

	update_layout()


func get_slot_at_position(pos: Vector2) -> int:
	## Hit-test: returns slot index at screen position, or -1.
	for i in slots.size():
		var svc = slots[i].container
		if not is_instance_valid(svc):
			continue
		var rect = Rect2(svc.position, svc.size)
		if rect.has_point(pos):
			return i
	return -1


func update_layout() -> void:
	## Recalculate all slot positions/sizes for current window.
	if slots.is_empty():
		return

	_update_container_size()

	if fullscreen_index >= 0:
		_apply_fullscreen_layout()
		return

	var win_size = get_window_size()
	var grid = get_grid_dimensions()
	var gap = 4
	var top_margin = 40

	var arena_w = (win_size.x - gap * (grid.cols + 1)) / grid.cols
	var arena_h = (win_size.y - top_margin - gap * (grid.rows + 1)) / grid.rows

	for i in slots.size():
		if not is_instance_valid(slots[i].container):
			continue
		var col: int = i % grid.cols
		var row: int = int(i / grid.cols)
		var x = gap + col * (arena_w + gap)
		var y = top_margin + gap + row * (arena_h + gap)
		slots[i].container.position = Vector2(x, y)
		slots[i].container.size = Vector2(arena_w, arena_h)


func get_grid_dimensions() -> Dictionary:
	## Returns {cols: int, rows: int} based on parallel_count.
	var clamped_count: int = maxi(parallel_count, 1)
	var cols: int = mini(clamped_count, 5)
	var rows: int = ceili(float(clamped_count) / cols)
	return {"cols": cols, "rows": rows}


func get_window_size() -> Vector2:
	## Get current window size reliably.
	if _tree:
		return _tree.root.get_visible_rect().size
	return Vector2(1280, 720)


# Internal

func _on_window_resized() -> void:
	update_layout()


func _apply_fullscreen_layout() -> void:
	## Position the fullscreen arena to fill the screen below the stats bar.
	if fullscreen_index < 0 or fullscreen_index >= slots.size():
		return

	var svc = slots[fullscreen_index].container
	if not is_instance_valid(svc):
		return

	_update_container_size()

	var win_size = get_window_size()
	var top_margin = 40
	var gap = 4

	svc.position = Vector2(gap, top_margin + gap)
	svc.size = Vector2(win_size.x - gap * 2, win_size.y - top_margin - gap * 2)


func _update_container_size() -> void:
	if not container:
		return
	var win_size = get_window_size()
	container.position = Vector2.ZERO
	container.size = win_size
	var bg = container.get_node_or_null("Background")
	if bg:
		bg.position = Vector2.ZERO
		bg.size = win_size
