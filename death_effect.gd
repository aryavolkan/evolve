extends Node2D

var effect_size: float = 40.0
var effect_color: Color = Color.WHITE

@onready var burst_particles: CPUParticles2D = $BurstParticles

func setup(pos: Vector2, size: float, color: Color, texture: Texture2D = null) -> void:
    global_position = pos
    effect_size = size
    effect_color = color
    if texture:
        $Sprite2D.texture = texture
        var tex_size = texture.get_size()
        var target_scale = size / tex_size.x
        $Sprite2D.scale = Vector2(target_scale, target_scale)
    else:
        $Sprite2D.visible = false
    $Sprite2D.modulate = color

func _ready() -> void:
    # Sprite scale-up + fade (existing behavior)
    var tween = create_tween()
    tween.set_parallel(true)
    tween.tween_property(self, "scale", Vector2(2, 2), 0.25).from(Vector2(1, 1))
    tween.tween_property($Sprite2D, "modulate:a", 0.0, 0.25)
    tween.set_parallel(false)

    # Particle burst for shatter effect
    if burst_particles:
        burst_particles.color = effect_color
        burst_particles.scale_amount_min = effect_size * 0.08
        burst_particles.scale_amount_max = effect_size * 0.2
        burst_particles.emitting = true

    # Wait for particles to finish, then free
    tween.tween_interval(0.5)
    tween.tween_callback(queue_free)
