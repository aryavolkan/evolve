extends TrainingModeBase
class_name PlaybackMode

## PLAYBACK mode: watch the best saved AI play.


func enter(context) -> void:
	super.enter(context)
	ctx.playback_mgr.start_playback()


func exit() -> void:
	ctx.playback_mgr.stop_playback()


func process(_delta: float) -> void:
	ctx.playback_mgr.process_playback()
