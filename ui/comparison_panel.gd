extends Control

## Side-by-side comparison setup panel.
## Select 2-4 strategies and run them in parallel arenas with identical seeds.

signal start_requested(strategies: Array)
signal back_requested

const BG_COLOR := Color(0.06, 0.06, 0.1, 0.95)
const TITLE_COLOR := Color(0.3, 0.7, 0.9, 1.0)
const LABEL_COLOR := Color(0.75, 0.8, 0.85, 1.0)
const VALUE_COLOR := Color(1.0, 0.95, 0.6, 1.0)
const HINT_COLOR := Color(0.5, 0.55, 0.6, 0.7)

# Each strategy slot: {source: "best"|"file", label: String, enabled: bool}
var strategy_slots: Array = [
	{"source": "best", "label": "Best Network", "enabled": true},
	{"source": "best", "label": "Best Network", "enabled": true},
	{"source": "best", "label": "Best Network", "enabled": false},
	{"source": "best", "label": "Best Network", "enabled": false},
]

var _built: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	add_child(bg)

	var panel = Control.new()
	panel.name = "Panel"
	add_child(panel)

	var y: float = 30
	var px: float = 60

	var title = Label.new()
	title.text = "SIDE-BY-SIDE COMPARISON"
	title.position = Vector2(px, y)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	panel.add_child(title)
	y += 45

	var subtitle = Label.new()
	subtitle.text = "Run 2-4 strategies in parallel arenas with identical seeds"
	subtitle.position = Vector2(px, y)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", HINT_COLOR)
	panel.add_child(subtitle)
	y += 40

	# Strategy slots
	for i in 4:
		y = _build_slot(panel, px, y, i)
		y += 5

	y += 15

	var start_btn = Button.new()
	start_btn.text = "  START COMPARISON  "
	start_btn.position = Vector2(px, y)
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.pressed.connect(_on_start_pressed)
	panel.add_child(start_btn)

	var back_btn = Button.new()
	back_btn.text = "  BACK  "
	back_btn.position = Vector2(px + 300, y)
	back_btn.add_theme_font_size_override("font_size", 20)
	back_btn.pressed.connect(func(): back_requested.emit())
	panel.add_child(back_btn)
	y += 50

	var hint = Label.new()
	hint.text = "[ESC] Back to menu  |  Enable 2-4 slots for comparison"
	hint.position = Vector2(px, y)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", HINT_COLOR)
	panel.add_child(hint)


func _build_slot(parent: Control, px: float, y: float, index: int) -> float:
	var slot_label = Label.new()
	slot_label.text = "Strategy %d" % (index + 1)
	slot_label.position = Vector2(px, y)
	slot_label.add_theme_font_size_override("font_size", 18)
	slot_label.add_theme_color_override("font_color", LABEL_COLOR)
	parent.add_child(slot_label)

	var cb = CheckBox.new()
	cb.text = "Enabled"
	cb.button_pressed = strategy_slots[index].enabled
	cb.position = Vector2(px + 150, y - 2)
	cb.toggled.connect(func(pressed: bool): strategy_slots[index].enabled = pressed)
	parent.add_child(cb)

	var option = OptionButton.new()
	option.add_item("Best Saved Network", 0)
	option.add_item("Human Control", 1)
	option.position = Vector2(px + 280, y - 2)
	option.size = Vector2(220, 28)
	option.item_selected.connect(func(idx: int):
		match idx:
			0: strategy_slots[index].source = "best"
			1: strategy_slots[index].source = "human"
		strategy_slots[index].label = option.get_item_text(idx)
	)
	parent.add_child(option)

	return y + 35


func _on_start_pressed() -> void:
	var strategies: Array = []
	for slot in strategy_slots:
		if slot.enabled:
			strategies.append(slot.duplicate())
	if strategies.size() < 2:
		# Need at least 2
		return
	start_requested.emit(strategies)


func get_enabled_count() -> int:
	var count := 0
	for slot in strategy_slots:
		if slot.enabled:
			count += 1
	return count


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()
