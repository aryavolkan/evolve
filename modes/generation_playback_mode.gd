extends TrainingModeBase
class_name GenerationPlaybackMode

## GENERATION_PLAYBACK mode: replay saved generations sequentially.


func enter(context) -> void:
	super.enter(context)
	ctx.playback_mgr.start_generation_playback()


func exit() -> void:
	ctx.playback_mgr.stop_playback()


func process(_delta: float) -> void:
	ctx.playback_mgr.process_generation_playback()
