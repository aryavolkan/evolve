extends TrainingModeBase
class_name ComparisonMode

## COMPARISON mode: side-by-side strategy comparison.

var strategies: Array = []


func enter(context) -> void:
	super.enter(context)
	ctx.playback_mgr.start_comparison(strategies)


func exit() -> void:
	ctx.playback_mgr.stop_comparison()


func process(delta: float) -> void:
	ctx.playback_mgr.process_comparison(delta)
