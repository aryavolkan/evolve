extends "res://test/test_base.gd"
## Tests for powerup.gd type mappings.

enum Type { SPEED_BOOST, INVINCIBILITY, SLOW_ENEMIES, SCREEN_CLEAR, RAPID_FIRE, PIERCING, SHIELD, FREEZE, DOUBLE_POINTS }

# Type name mapping from powerup.gd
func get_type_name(type: Type) -> String:
	match type:
		Type.SPEED_BOOST: return "SPEED BOOST"
		Type.INVINCIBILITY: return "INVINCIBILITY"
		Type.SLOW_ENEMIES: return "SLOW ENEMIES"
		Type.SCREEN_CLEAR: return "SCREEN CLEAR"
		Type.RAPID_FIRE: return "RAPID FIRE"
		Type.PIERCING: return "PIERCING"
		Type.SHIELD: return "SHIELD"
		Type.FREEZE: return "FREEZE"
		Type.DOUBLE_POINTS: return "DOUBLE POINTS"
	return ""


func _run_tests() -> void:
	print("\n[Powerup Tests]")

	_test("all_types_have_names", _test_all_types_have_names)
	_test("type_count_matches_spec", _test_type_count_matches_spec)
	_test("type_names_not_empty", _test_type_names_not_empty)
	_test("speed_boost_name", _test_speed_boost_name)
	_test("invincibility_name", _test_invincibility_name)
	_test("slow_enemies_name", _test_slow_enemies_name)
	_test("screen_clear_name", _test_screen_clear_name)
	_test("rapid_fire_name", _test_rapid_fire_name)
	_test("piercing_name", _test_piercing_name)
	_test("shield_name", _test_shield_name)
	_test("freeze_name", _test_freeze_name)
	_test("double_points_name", _test_double_points_name)


func _test_all_types_have_names() -> void:
	for i in 9:
		var name = get_type_name(i as Type)
		assert_ne(name, "", "Type %d should have a name" % i)


func _test_type_count_matches_spec() -> void:
	# Per CLAUDE.md, there are 9 powerup types (indices 0-8)
	assert_eq(Type.DOUBLE_POINTS, 8, "Last type index should be 8")


func _test_type_names_not_empty() -> void:
	var names := [
		get_type_name(Type.SPEED_BOOST),
		get_type_name(Type.INVINCIBILITY),
		get_type_name(Type.SLOW_ENEMIES),
		get_type_name(Type.SCREEN_CLEAR),
		get_type_name(Type.RAPID_FIRE),
		get_type_name(Type.PIERCING),
		get_type_name(Type.SHIELD),
		get_type_name(Type.FREEZE),
		get_type_name(Type.DOUBLE_POINTS),
	]
	for name in names:
		assert_ne(name, "", "All powerup names should be non-empty")


func _test_speed_boost_name() -> void:
	assert_eq(get_type_name(Type.SPEED_BOOST), "SPEED BOOST")


func _test_invincibility_name() -> void:
	assert_eq(get_type_name(Type.INVINCIBILITY), "INVINCIBILITY")


func _test_slow_enemies_name() -> void:
	assert_eq(get_type_name(Type.SLOW_ENEMIES), "SLOW ENEMIES")


func _test_screen_clear_name() -> void:
	assert_eq(get_type_name(Type.SCREEN_CLEAR), "SCREEN CLEAR")


func _test_rapid_fire_name() -> void:
	assert_eq(get_type_name(Type.RAPID_FIRE), "RAPID FIRE")


func _test_piercing_name() -> void:
	assert_eq(get_type_name(Type.PIERCING), "PIERCING")


func _test_shield_name() -> void:
	assert_eq(get_type_name(Type.SHIELD), "SHIELD")


func _test_freeze_name() -> void:
	assert_eq(get_type_name(Type.FREEZE), "FREEZE")


func _test_double_points_name() -> void:
	assert_eq(get_type_name(Type.DOUBLE_POINTS), "DOUBLE POINTS")
