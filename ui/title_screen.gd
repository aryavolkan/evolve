extends Control

## Title screen and main menu for Evolve.
## Provides mode selection: Play (human), Watch AI, Train AI, Co-Evolution.

signal mode_selected(mode: String)

const TITLE_COLOR := Color(0.3, 0.9, 0.4, 1.0)
const SUBTITLE_COLOR := Color(0.6, 0.7, 0.8, 0.9)
const BUTTON_NORMAL := Color(0.15, 0.18, 0.25, 1.0)
const BUTTON_HOVER := Color(0.2, 0.28, 0.4, 1.0)
const BUTTON_TEXT := Color(0.9, 0.95, 1.0, 1.0)
const BUTTON_DESC := Color(0.6, 0.65, 0.7, 0.9)

var _buttons: Array = []  # [{rect: Rect2, mode: String, label: String, desc: String}]
var _hovered_index: int = -1
var _visible: bool = true

const MENU_ITEMS: Array = [
	{"mode": "play", "label": "PLAY", "desc": "Human control — arrow keys to move, WASD to shoot", "key": "1"},
	{"mode": "watch", "label": "WATCH AI", "desc": "Watch the best trained network play", "key": "2"},
	{"mode": "train", "label": "TRAIN AI", "desc": "Evolve neural networks across generations", "key": "3"},
	{"mode": "coevolution", "label": "CO-EVOLUTION", "desc": "Enemies and players co-evolve adversarially", "key": "4"},
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_menu() -> void:
	_visible = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func hide_menu() -> void:
	_visible = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
	if not _visible:
		return

	if event is InputEventMouseMotion:
		var new_hover := _get_button_at(event.position)
		if new_hover != _hovered_index:
			_hovered_index = new_hover
			queue_redraw()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _get_button_at(event.position)
		if idx >= 0 and idx < MENU_ITEMS.size():
			_select_mode(MENU_ITEMS[idx].mode)

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_mode("play")
			KEY_2:
				_select_mode("watch")
			KEY_3:
				_select_mode("train")
			KEY_4:
				_select_mode("coevolution")


func _select_mode(mode: String) -> void:
	hide_menu()
	mode_selected.emit(mode)


func _draw() -> void:
	if not _visible:
		return

	_buttons.clear()

	# Full background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.08, 1.0))

	var cx: float = size.x / 2.0
	var cy: float = size.y / 2.0

	# Title
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(cx - 120, cy - 180), "EVOLVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, TITLE_COLOR)

	# Subtitle
	draw_string(font, Vector2(cx - 180, cy - 140), "Neuroevolution Arcade Survival", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, SUBTITLE_COLOR)

	# Divider line
	draw_line(Vector2(cx - 200, cy - 115), Vector2(cx + 200, cy - 115), Color(0.3, 0.35, 0.45, 0.6), 1.0)

	# Menu buttons
	var btn_width: float = 420.0
	var btn_height: float = 60.0
	var btn_gap: float = 12.0
	var start_y: float = cy - 90

	for i in MENU_ITEMS.size():
		var item = MENU_ITEMS[i]
		var btn_x: float = cx - btn_width / 2.0
		var btn_y: float = start_y + i * (btn_height + btn_gap)
		var rect := Rect2(btn_x, btn_y, btn_width, btn_height)

		var bg_color: Color = BUTTON_HOVER if i == _hovered_index else BUTTON_NORMAL
		draw_rect(rect, bg_color)
		draw_rect(rect, Color(0.35, 0.4, 0.5, 0.5), false, 1.0)

		# Key hint
		draw_string(font, Vector2(btn_x + 15, btn_y + 28), "[%s]" % item.key, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.6, 0.3, 0.8))

		# Label
		draw_string(font, Vector2(btn_x + 55, btn_y + 28), item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, BUTTON_TEXT)

		# Description
		draw_string(font, Vector2(btn_x + 55, btn_y + 48), item.desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BUTTON_DESC)

		_buttons.append({"rect": rect, "mode": item.mode})

	# Footer
	draw_string(font, Vector2(cx - 100, size.y - 30), "Press 1-4 or click to select", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.45, 0.5, 0.7))


func _get_button_at(pos: Vector2) -> int:
	for i in _buttons.size():
		if _buttons[i].rect.has_point(pos):
			return i
	return -1
