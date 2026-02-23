extends TrainingModeBase
class_name SandboxMode

## SANDBOX mode: configurable arena with custom settings.

var sandbox_cfg: Dictionary = {}


func enter(context) -> void:
    super.enter(context)
    ctx.playback_mgr.start_sandbox(sandbox_cfg)


func exit() -> void:
    ctx.playback_mgr.stop_sandbox()


func process(_delta: float) -> void:
    ctx.playback_mgr.process_sandbox()
