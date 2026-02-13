## Handles keyboard input for training modes
extends RefCounted
class_name TrainingInputHandler

# References to main game systems
var main_game: Node2D
var training_manager: Node

# Input state tracking
var _pressed_keys: Dictionary = {}
var _speed_down_held: bool = false
var _speed_up_held: bool = false

func setup(p_main_game: Node2D, p_training_manager: Node) -> void:
	"""Initialize the training input handler with references to game systems."""
	main_game = p_main_game
	training_manager = p_training_manager

func handle_training_input() -> void:
	"""Handle all training-related keyboard input."""
	if not training_manager:
		return

	# T = Start/Stop Training
	if Input.is_action_just_pressed("ui_text_submit"):  # We'll use a different key
		pass

	if Input.is_key_pressed(KEY_T) and Input.is_action_just_pressed("ui_focus_next"):
		# Avoid accidental triggers
		pass

	# Check for key presses (using _unhandled_key_input would be cleaner but this works)
	if Input.is_physical_key_pressed(KEY_T) and not Input.is_physical_key_pressed(KEY_SHIFT):
		if not _key_just_pressed("train"):
			return
		if training_manager.get_mode() == training_manager.Mode.TRAINING:
			training_manager.stop_training()
		else:
			training_manager.start_training(100, 100)

	elif Input.is_physical_key_pressed(KEY_P):
		if not _key_just_pressed("playback"):
			return
		if training_manager.get_mode() == training_manager.Mode.PLAYBACK:
			training_manager.stop_playback()
		else:
			training_manager.start_playback()

	elif Input.is_physical_key_pressed(KEY_C) and not Input.is_physical_key_pressed(KEY_SHIFT):
		if not _key_just_pressed("coevo"):
			return
		if training_manager.get_mode() == training_manager.Mode.COEVOLUTION:
			training_manager.stop_coevolution_training()
		else:
			training_manager.start_coevolution_training(100, 100)

	elif Input.is_physical_key_pressed(KEY_H):
		if not _key_just_pressed("human"):
			return
		if training_manager.get_mode() == training_manager.Mode.TRAINING:
			training_manager.stop_training()
		elif training_manager.get_mode() == training_manager.Mode.COEVOLUTION:
			training_manager.stop_coevolution_training()
		elif training_manager.get_mode() == training_manager.Mode.PLAYBACK:
			training_manager.stop_playback()
		elif training_manager.get_mode() == training_manager.Mode.GENERATION_PLAYBACK:
			training_manager.stop_playback()
		elif training_manager.get_mode() == training_manager.Mode.SANDBOX:
			training_manager.stop_sandbox()
		elif training_manager.get_mode() == training_manager.Mode.COMPARISON:
			training_manager.stop_comparison()
		elif training_manager.get_mode() == training_manager.Mode.RTNEAT:
			training_manager.stop_rtneat()
		elif training_manager.get_mode() == training_manager.Mode.TEAMS:
			training_manager.stop_rtneat_teams()

	elif Input.is_physical_key_pressed(KEY_G):
		if not _key_just_pressed("gen_playback"):
			return
		if training_manager.get_mode() == training_manager.Mode.GENERATION_PLAYBACK:
			training_manager.stop_playback()
		else:
			training_manager.start_generation_playback()

	# SPACE to advance generation playback (only when game over)
	if training_manager.get_mode() == training_manager.Mode.GENERATION_PLAYBACK:
		if Input.is_action_just_pressed("ui_accept") and main_game.game_over:
			training_manager.advance_generation_playback()

	# Training mode controls (SPACE for pause is handled in training_manager._input)
	if training_manager.get_mode() == training_manager.Mode.TRAINING or training_manager.get_mode() == training_manager.Mode.COEVOLUTION:
		# Speed controls ([ and ] or - and =) - only when not paused
		if not training_manager.is_paused:
			var speed_down = Input.is_physical_key_pressed(KEY_BRACKETLEFT) or Input.is_physical_key_pressed(KEY_MINUS)
			var speed_up = Input.is_physical_key_pressed(KEY_BRACKETRIGHT) or Input.is_physical_key_pressed(KEY_EQUAL)

			if speed_down and not _speed_down_held:
				training_manager.adjust_speed(-1.0)
			if speed_up and not _speed_up_held:
				training_manager.adjust_speed(1.0)

			_speed_down_held = speed_down
			_speed_up_held = speed_up

	# rtNEAT speed controls
	if training_manager.get_mode() == training_manager.Mode.RTNEAT and training_manager.rtneat_mgr:
		var speed_down = Input.is_physical_key_pressed(KEY_BRACKETLEFT) or Input.is_physical_key_pressed(KEY_MINUS)
		var speed_up = Input.is_physical_key_pressed(KEY_BRACKETRIGHT) or Input.is_physical_key_pressed(KEY_EQUAL)

		if speed_down and not _speed_down_held:
			training_manager.rtneat_mgr.adjust_speed(-1.0)
		if speed_up and not _speed_up_held:
			training_manager.rtneat_mgr.adjust_speed(1.0)

		_speed_down_held = speed_down
		_speed_up_held = speed_up

	# Teams speed controls
	if training_manager.get_mode() == training_manager.Mode.TEAMS and training_manager.team_mgr:
		var speed_down = Input.is_physical_key_pressed(KEY_BRACKETLEFT) or Input.is_physical_key_pressed(KEY_MINUS)
		var speed_up = Input.is_physical_key_pressed(KEY_BRACKETRIGHT) or Input.is_physical_key_pressed(KEY_EQUAL)

		if speed_down and not _speed_down_held:
			training_manager.team_mgr.adjust_speed(-1.0)
		if speed_up and not _speed_up_held:
			training_manager.team_mgr.adjust_speed(1.0)

		_speed_down_held = speed_down
		_speed_up_held = speed_up

func _key_just_pressed(key_name: String) -> bool:
	"""Helper function to prevent key repeat for training mode switches."""
	if _pressed_keys.get(key_name, false):
		return false  # Already pressed
	_pressed_keys[key_name] = true
	# Reset after a short delay
	main_game.get_tree().create_timer(0.3).timeout.connect(func(): _pressed_keys[key_name] = false)
	return true