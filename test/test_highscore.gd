extends "res://test/test_base.gd"
## Tests for high score system logic.
## These test the core sorting and qualification logic without scene instantiation.

const MAX_HIGH_SCORES: int = 5
const TEST_SAVE_PATH: String = "user://test_highscores.save"


func _run_tests() -> void:
    print("\n[High Score Tests]")

    _test("empty_list_qualifies_any_score", _test_empty_list_qualifies_any_score)
    _test("partial_list_qualifies_any_score", _test_partial_list_qualifies_any_score)
    _test("full_list_rejects_lower_score", _test_full_list_rejects_lower_score)
    _test("full_list_accepts_higher_score", _test_full_list_accepts_higher_score)
    _test("scores_sorted_descending", _test_scores_sorted_descending)
    _test("list_capped_at_max", _test_list_capped_at_max)
    _test("name_truncated_to_10_chars", _test_name_truncated_to_10_chars)
    _test("save_and_load_roundtrip", _test_save_and_load_roundtrip)
    _test("tie_scores_handled", _test_tie_scores_handled)


# ============================================================
# Helper functions mirroring main.gd logic
# ============================================================


func is_high_score(high_scores: Array, new_score: int) -> bool:
    if high_scores.size() < MAX_HIGH_SCORES:
        return true
    return new_score > high_scores[-1]["score"]


func add_high_score(high_scores: Array, player_name: String, new_score: int) -> Array:
    var entry = {"name": player_name.substr(0, 10), "score": new_score}
    high_scores.append(entry)
    high_scores.sort_custom(func(a, b): return a["score"] > b["score"])
    if high_scores.size() > MAX_HIGH_SCORES:
        high_scores.resize(MAX_HIGH_SCORES)
    return high_scores


func save_high_scores(path: String, high_scores: Array) -> void:
    var file = FileAccess.open(path, FileAccess.WRITE)
    file.store_var(high_scores)
    file.close()


func load_high_scores(path: String) -> Array:
    if not FileAccess.file_exists(path):
        return []
    var file = FileAccess.open(path, FileAccess.READ)
    var data = file.get_var()
    file.close()
    if data is Array:
        return data
    return []


# ============================================================
# Qualification Tests
# ============================================================


func _test_empty_list_qualifies_any_score() -> void:
    var scores: Array = []
    assert_true(is_high_score(scores, 0), "Score 0 should qualify for empty list")
    assert_true(is_high_score(scores, 100), "Score 100 should qualify for empty list")


func _test_partial_list_qualifies_any_score() -> void:
    var scores: Array = [
        {"name": "AAA", "score": 1000},
        {"name": "BBB", "score": 500},
    ]
    assert_true(is_high_score(scores, 1), "Any score should qualify when list has room")
    assert_true(is_high_score(scores, 0), "Zero should qualify when list has room")


func _test_full_list_rejects_lower_score() -> void:
    var scores: Array = [
        {"name": "AAA", "score": 1000},
        {"name": "BBB", "score": 800},
        {"name": "CCC", "score": 600},
        {"name": "DDD", "score": 400},
        {"name": "EEE", "score": 200},
    ]
    assert_false(is_high_score(scores, 100), "Score below lowest should not qualify")
    assert_false(is_high_score(scores, 200), "Score equal to lowest should not qualify")


func _test_full_list_accepts_higher_score() -> void:
    var scores: Array = [
        {"name": "AAA", "score": 1000},
        {"name": "BBB", "score": 800},
        {"name": "CCC", "score": 600},
        {"name": "DDD", "score": 400},
        {"name": "EEE", "score": 200},
    ]
    assert_true(is_high_score(scores, 201), "Score above lowest should qualify")
    assert_true(is_high_score(scores, 999), "Score in middle should qualify")
    assert_true(is_high_score(scores, 2000), "Score above highest should qualify")


# ============================================================
# Sorting and Capping Tests
# ============================================================


func _test_scores_sorted_descending() -> void:
    var scores: Array = []
    scores = add_high_score(scores, "Low", 100)
    scores = add_high_score(scores, "High", 500)
    scores = add_high_score(scores, "Mid", 300)

    assert_eq(scores.size(), 3)
    assert_eq(scores[0]["score"], 500, "First should be highest")
    assert_eq(scores[1]["score"], 300, "Second should be middle")
    assert_eq(scores[2]["score"], 100, "Third should be lowest")


func _test_list_capped_at_max() -> void:
    var scores: Array = []
    for i in 10:
        scores = add_high_score(scores, "Player%d" % i, (i + 1) * 100)

    assert_eq(scores.size(), MAX_HIGH_SCORES, "List should be capped at %d" % MAX_HIGH_SCORES)
    assert_eq(scores[0]["score"], 1000, "Highest score should be first")
    assert_eq(scores[-1]["score"], 600, "Lowest kept score should be 6th highest")


func _test_name_truncated_to_10_chars() -> void:
    var scores: Array = []
    scores = add_high_score(scores, "ThisIsAVeryLongPlayerName", 100)

    assert_eq(scores[0]["name"], "ThisIsAVer", "Name should be truncated to 10 chars")
    assert_eq(scores[0]["name"].length(), 10)


func _test_tie_scores_handled() -> void:
    var scores: Array = []
    scores = add_high_score(scores, "First", 500)
    scores = add_high_score(scores, "Second", 500)
    scores = add_high_score(scores, "Third", 500)

    assert_eq(scores.size(), 3)
    # All three should be present with same score
    for entry in scores:
        assert_eq(entry["score"], 500)


# ============================================================
# Persistence Tests
# ============================================================


func _test_save_and_load_roundtrip() -> void:
    var original: Array = [
        {"name": "Alice", "score": 1000},
        {"name": "Bob", "score": 750},
        {"name": "Charlie", "score": 500},
    ]

    save_high_scores(TEST_SAVE_PATH, original)
    var loaded = load_high_scores(TEST_SAVE_PATH)

    assert_eq(loaded.size(), original.size(), "Loaded size should match")
    for i in original.size():
        assert_eq(loaded[i]["name"], original[i]["name"], "Name %d should match" % i)
        assert_eq(loaded[i]["score"], original[i]["score"], "Score %d should match" % i)

    # Cleanup
    DirAccess.remove_absolute(TEST_SAVE_PATH)
