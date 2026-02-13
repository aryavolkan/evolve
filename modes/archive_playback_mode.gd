extends TrainingModeBase
class_name ArchivePlaybackMode

## ARCHIVE_PLAYBACK mode: play back a MAP-Elites archive cell.

var cell: Vector2i = Vector2i.ZERO


func enter(context) -> void:
	super.enter(context)
	ctx.playback_mgr.map_elites_archive = ctx.map_elites_archive
	ctx.playback_mgr.start_archive_playback(cell)


func exit() -> void:
	ctx.playback_mgr.stop_archive_playback()


func process(_delta: float) -> void:
	ctx.playback_mgr.process_archive_playback()
