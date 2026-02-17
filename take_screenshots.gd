extends SceneTree

var _frame = 0
var _stage = 0
var _main: Node = null

func _init():
	var packed = load("res://main.tscn")
	_main = packed.instantiate()
	get_root().add_child(_main)

func _process(delta):
	_frame += 1
	match _stage:
		0:
			if _frame == 90:
				_save("assets/title_screen.png")
				_stage = 1
				_frame = 0
		1:
			# Start play mode
			if _frame == 5:
				var ts = _main.get("title_screen")
				if ts:
					ts.call("hide_menu")
				_main.call("_on_title_mode_selected", "play")
			# Early game: ~5s in
			if _frame == 300:
				_save("assets/gameplay_early.png")
			# Mid game: ~30s in
			if _frame == 1800:
				_save("assets/gameplay_mid.png")
			# Chaos: ~90s in
			if _frame == 5400:
				_save("assets/gameplay.png")
				_stage = 2
				_frame = 0
		2:
			if _frame == 5:
				# Go back to title
				_main.set("game_started", false)
				var ts = _main.get("title_screen")
				if ts:
					ts.show()
			if _frame == 60:
				var ts2 = _main.get("title_screen")
				if ts2:
					ts2.call("hide_menu")
				_main.call("_on_title_mode_selected", "train")
			if _frame == 360:
				_save("assets/training.png")
				_stage = 3
		3:
			print("All done.")
			quit()

func _save(path: String):
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("Saved: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
