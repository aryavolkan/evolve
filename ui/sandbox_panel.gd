extends Control

## Sandbox mode configuration panel.
## Provides UI controls for customizing a single-arena sandbox:
##   - Enemy type checkboxes
##   - Spawn rate multiplier slider
##   - Power-up frequency slider
##   - Starting difficulty slider
##   - Network loading (best saved or from archive)

signal config_changed(config: Dictionary)
signal start_requested(config: Dictionary)
signal train_requested(config: Dictionary)
signal back_requested

const BG_COLOR := Color(0.06, 0.06, 0.1, 0.95)
const PANEL_COLOR := Color(0.1, 0.12, 0.18, 1.0)
const BORDER_COLOR := Color(0.25, 0.3, 0.4, 0.8)
const TITLE_COLOR := Color(0.3, 0.9, 0.4, 1.0)
const LABEL_COLOR := Color(0.75, 0.8, 0.85, 1.0)
const VALUE_COLOR := Color(1.0, 0.95, 0.6, 1.0)
const HINT_COLOR := Color(0.5, 0.55, 0.6, 0.7)

# Configuration state
var enemy_types_enabled: Dictionary = {
	0: true,   # Pawn
	1: true,   # Knight
	2: true,   # Bishop
	3: true,   # Rook
	4: false,  # Queen (off by default)
}
var spawn_rate_multiplier: float = 1.0   # 0.25 - 3.0
var powerup_frequency: float = 1.0       # 0.25 - 3.0
var starting_difficulty: float = 0.0     # 0.0 - 1.0
var network_source: String = "best"      # "best", "none" (human)
var training_network_source: String = "best"  # "best", "random", "generation"
var training_generation: int = 1

# UI elements
var _sliders: Dictionary = {}
var _checkboxes: Dictionary = {}
var _built: bool = false
var _training_generation_input: SpinBox = null
var _training_source_option: OptionButton = null

const ENEMY_NAMES: Dictionary = {
	0: "Pawn",
	1: "Knight",
	2: "Bishop",
	3: "Rook",
	4: "Queen",
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _exit_tree() -> void:
	# Clean up references to avoid potential issues
	_checkboxes.clear()
	_sliders.clear()
	_training_generation_input = null
	_training_source_option = null


func _build_ui() -> void:
	if _built:
		return
	_built = true

	# Background
	var bg = ColorRect.new()
	bg.name = "BG"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	add_child(bg)

	# Main panel (centered)
	var panel = Control.new()
	panel.name = "Panel"
	add_child(panel)

	var y: float = 30
	var panel_x: float = 60

	# Title
	var title = Label.new()
	title.text = "SANDBOX MODE"
	title.position = Vector2(panel_x, y)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	panel.add_child(title)
	y += 50

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Configure a custom arena with your own rules"
	subtitle.position = Vector2(panel_x, y)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", HINT_COLOR)
	panel.add_child(subtitle)
	y += 40

	# --- Enemy Types ---
	var enemy_label = Label.new()
	enemy_label.text = "Enemy Types"
	enemy_label.position = Vector2(panel_x, y)
	enemy_label.add_theme_font_size_override("font_size", 18)
	enemy_label.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(enemy_label)
	y += 28

	for type_id in ENEMY_NAMES:
		var cb = CheckBox.new()
		cb.text = ENEMY_NAMES[type_id]
		cb.button_pressed = enemy_types_enabled.get(type_id, false)
		cb.position = Vector2(panel_x + 20, y)
		cb.add_theme_font_size_override("font_size", 16)
		cb.toggled.connect(func(pressed: bool): _on_enemy_type_toggled(type_id, pressed))
		panel.add_child(cb)
		_checkboxes[type_id] = cb
		y += 28
	y += 10

	# --- Sliders ---
	y = _add_slider(panel, panel_x, y, "Spawn Rate", "spawn_rate", 0.25, 3.0, spawn_rate_multiplier, 0.25, "x")
	y = _add_slider(panel, panel_x, y, "Power-up Frequency", "powerup_freq", 0.25, 3.0, powerup_frequency, 0.25, "x")
	y = _add_slider(panel, panel_x, y, "Starting Difficulty", "difficulty", 0.0, 1.0, starting_difficulty, 0.1, "")
	y += 10

	# --- Network Source (sandbox run) ---
	var net_label = Label.new()
	net_label.text = "AI Network"
	net_label.position = Vector2(panel_x, y)
	net_label.add_theme_font_size_override("font_size", 18)
	net_label.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(net_label)
	y += 28

	var net_option = OptionButton.new()
	net_option.name = "NetworkOption"
	net_option.add_item("Best Saved Network", 0)
	net_option.add_item("Human Control", 1)
	net_option.position = Vector2(panel_x + 20, y)
	net_option.size = Vector2(250, 30)
	net_option.item_selected.connect(_on_network_source_changed)
	panel.add_child(net_option)
	y += 50

	# --- Training Seed Source ---
	var train_label = Label.new()
	train_label.text = "Training Seed"
	train_label.position = Vector2(panel_x, y)
	train_label.add_theme_font_size_override("font_size", 18)
	train_label.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(train_label)
	y += 28

	_training_source_option = OptionButton.new()
	_training_source_option.add_item("Start from Best Saved Network", 0)
	_training_source_option.add_item("Start from Fresh Random Population", 1)
	_training_source_option.add_item("Start from Specific Generation", 2)
	_training_source_option.position = Vector2(panel_x + 20, y)
	_training_source_option.size = Vector2(320, 30)
	_training_source_option.item_selected.connect(_on_training_source_changed)
	panel.add_child(_training_source_option)
	y += 35

	var gen_label = Label.new()
	gen_label.text = "Generation"
	gen_label.position = Vector2(panel_x + 20, y)
	gen_label.add_theme_font_size_override("font_size", 14)
	gen_label.add_theme_color_override("font_color", LABEL_COLOR)
	panel.add_child(gen_label)

	_training_generation_input = SpinBox.new()
	_training_generation_input.min_value = 1
	_training_generation_input.max_value = 999
	_training_generation_input.step = 1
	_training_generation_input.value = training_generation
	_training_generation_input.position = Vector2(panel_x + 150, y - 4)
	_training_generation_input.size = Vector2(120, 26)
	_training_generation_input.value_changed.connect(_on_training_generation_changed)
	panel.add_child(_training_generation_input)
	y += 40

	_update_training_generation_state()

	# --- Buttons ---
	var start_btn = Button.new()
	start_btn.text = "  START SANDBOX  "
	start_btn.position = Vector2(panel_x, y)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.pressed.connect(_on_start_pressed)
	panel.add_child(start_btn)

	var train_btn = Button.new()
	train_btn.text = "  TRAIN WITH CONFIG  "
	train_btn.position = Vector2(panel_x + 230, y)
	train_btn.add_theme_font_size_override("font_size", 20)
	train_btn.pressed.connect(_on_train_pressed)
	panel.add_child(train_btn)
	y += 50

	var back_btn = Button.new()
	back_btn.text = "  BACK  "
	back_btn.position = Vector2(panel_x, y)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(func(): back_requested.emit())
	panel.add_child(back_btn)
	y += 45

	# Key hint
	var hint = Label.new()
	hint.text = "[ESC] Back to menu"
	hint.position = Vector2(panel_x, y)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	panel.add_child(hint)


func _add_slider(parent: Control, px: float, y: float, label_text: String, key: String, min_val: float, max_val: float, default_val: float, step: float, suffix: String) -> float:
	var label = Label.new()
	label.text = label_text
	label.position = Vector2(px, y)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	parent.add_child(label)

	var value_label = Label.new()
	value_label.name = "Value_%s" % key
	value_label.position = Vector2(px + 280, y)
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", VALUE_COLOR)
	value_label.text = _format_slider_value(default_val, suffix)
	parent.add_child(value_label)
	y += 25

	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = default_val
	slider.position = Vector2(px + 20, y)
	slider.size = Vector2(320, 20)
	slider.value_changed.connect(func(val: float): _on_slider_changed(key, val, suffix, value_label))
	parent.add_child(slider)
	_sliders[key] = slider

	return y + 35


func _format_slider_value(val: float, suffix: String) -> String:
	if suffix == "x":
		return "%.2fx" % val
	return "%.1f" % val


func _on_slider_changed(key: String, val: float, suffix: String, label: Label) -> void:
	label.text = _format_slider_value(val, suffix)
	match key:
		"spawn_rate":
			spawn_rate_multiplier = val
		"powerup_freq":
			powerup_frequency = val
		"difficulty":
			starting_difficulty = val
	config_changed.emit(get_config())


func _on_enemy_type_toggled(type_id: int, pressed: bool) -> void:
	enemy_types_enabled[type_id] = pressed
	# Ensure at least one type is enabled
	var any_enabled := false
	for v in enemy_types_enabled.values():
		if v:
			any_enabled = true
			break
	if not any_enabled:
		enemy_types_enabled[0] = true  # Force pawn on
		if _checkboxes.has(0) and _checkboxes[0] != null:
			_checkboxes[0].button_pressed = true
	config_changed.emit(get_config())


func _on_network_source_changed(index: int) -> void:
	match index:
		0: network_source = "best"
		1: network_source = "none"
	config_changed.emit(get_config())


func _on_training_source_changed(index: int) -> void:
	match index:
		0:
			training_network_source = "best"
		1:
			training_network_source = "random"
		2:
			training_network_source = "generation"
	_update_training_generation_state()
	config_changed.emit(get_config())


func _update_training_generation_state() -> void:
	if not _training_generation_input:
		return
	var needs_generation := training_network_source == "generation"
	_training_generation_input.editable = needs_generation
	_training_generation_input.modulate = Color(1, 1, 1, 1) if needs_generation else Color(1, 1, 1, 0.5)


func _on_training_generation_changed(value: float) -> void:
	training_generation = int(round(value))
	config_changed.emit(get_config())


func _on_start_pressed() -> void:
	start_requested.emit(get_config())


func _on_train_pressed() -> void:
	train_requested.emit(get_config())


func get_config() -> Dictionary:
	## Return current sandbox configuration.
	var enabled_types: Array = []
	for type_id in enemy_types_enabled:
		if enemy_types_enabled[type_id]:
			enabled_types.append(type_id)
	enabled_types.sort()

	return {
		"enemy_types": enabled_types,
		"spawn_rate_multiplier": spawn_rate_multiplier,
		"powerup_frequency": powerup_frequency,
		"starting_difficulty": starting_difficulty,
		"network_source": network_source,
		"training_network_source": training_network_source,
		"training_generation": training_generation,
	}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
