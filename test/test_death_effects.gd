extends "res://test/test_base.gd"
## Tests for death animation effects.

var DeathEffectScene = preload("res://death_effect.tscn")
var EnemyScript = preload("res://enemy.gd")


func _run_tests() -> void:
	print("\n[Death Effects Tests]")

	_test("death_effect_instantiates", _test_instantiates)
	_test("death_effect_setup_stores_position", _test_setup_position)
	_test("death_effect_setup_stores_color", _test_setup_color)
	_test("death_effect_setup_with_texture", _test_setup_texture)
	_test("enemy_has_die_method", _test_enemy_has_die)
	_test("enemy_type_config_sizes_valid", _test_type_config_sizes)
	_test("player_has_death_effect_scene", _test_player_has_effect)
	_test("agent_has_death_effect_scene", _test_agent_has_effect)


func _test_instantiates() -> void:
	var effect = DeathEffectScene.instantiate()
	assert_not_null(effect, "DeathEffect should instantiate")
	effect.free()


func _test_setup_position() -> void:
	var effect = DeathEffectScene.instantiate()
	var pos = Vector2(100, 200)
	effect.setup(pos, 30.0, Color.RED)
	assert_eq(effect.global_position, pos, "Position should be set by setup()")
	effect.free()


func _test_setup_color() -> void:
	var effect = DeathEffectScene.instantiate()
	effect.setup(Vector2.ZERO, 30.0, Color.BLUE)
	assert_eq(effect.effect_color, Color.BLUE, "Color should be stored")
	effect.free()


func _test_setup_texture() -> void:
	var effect = DeathEffectScene.instantiate()
	var tex = preload("res://assets/pawn_icon.svg")
	effect.setup(Vector2.ZERO, 28.0, Color.WHITE, tex)
	assert_eq(effect.get_node("Sprite2D").texture, tex, "Texture should be set when provided")
	effect.free()


func _test_enemy_has_die() -> void:
	var EnemyScene = preload("res://enemy.tscn")
	var enemy = EnemyScene.instantiate()
	assert_true(enemy.has_method("die"), "Enemy should have die() method")
	enemy.free()


func _test_type_config_sizes() -> void:
	# Verify all TYPE_CONFIG entries have a valid size field
	for type_key in EnemyScript.TYPE_CONFIG:
		var config = EnemyScript.TYPE_CONFIG[type_key]
		assert_gt(config["size"], 0.0, "Type %s should have positive size" % type_key)


func _test_player_has_effect() -> void:
	var PlayerScene = preload("res://player.tscn")
	var player = PlayerScene.instantiate()
	assert_not_null(player.death_effect_scene, "Player should preload death_effect_scene")
	player.free()


func _test_agent_has_effect() -> void:
	var AgentScene = preload("res://agent.tscn")
	var agent = AgentScene.instantiate()
	assert_not_null(agent.death_effect_scene, "Agent should preload death_effect_scene")
	agent.free()
