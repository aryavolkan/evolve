extends RefCounted
class_name ScoreManager

## Manages scoring, high scores, milestones, and power-up scoring effects.

# Bonus points constants
const POWERUP_COLLECT_BONUS: int = 5000
const SCREEN_CLEAR_BONUS: int = 8000
const KILL_MULTIPLIER: int = 1000
const SURVIVAL_MILESTONE_BONUS: int = 100
const SHOOT_TOWARD_ENEMY_BONUS: int = 50
const SHOOT_HIT_BONUS: int = 200
const MILESTONE_INTERVAL: float = 15.0

# High score constants
const MAX_HIGH_SCORES: int = 5
const SAVE_PATH: String = "user://highscores.save"

var high_scores: Array = []


func load_high_scores() -> void:
    if FileAccess.file_exists(SAVE_PATH):
        var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
        var data = file.get_var()
        if data is Array:
            high_scores = data
        file.close()


func save_high_scores() -> void:
    var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    file.store_var(high_scores)
    file.close()


func is_high_score(new_score: int) -> bool:
    if high_scores.size() < MAX_HIGH_SCORES:
        return true
    return new_score > high_scores[-1]["score"]


func submit_high_score(player_name: String, score: int) -> void:
    var entry = { "name": player_name.substr(0, 10), "score": score }
    high_scores.append(entry)
    high_scores.sort_custom(func(a, b): return a["score"] > b["score"])
    if high_scores.size() > MAX_HIGH_SCORES:
        high_scores.resize(MAX_HIGH_SCORES)
    save_high_scores()


func get_scoreboard_text() -> String:
    var text = "HIGH SCORES\n"
    for i in range(high_scores.size()):
        text += "%d. %s - %d\n" % [i + 1, high_scores[i]["name"], high_scores[i]["score"]]
    for i in range(high_scores.size(), MAX_HIGH_SCORES):
        text += "%d. ---\n" % [i + 1]
    return text


var _cached_powerups: Array = []
var _cached_powerups_frame: int = -1

func calculate_proximity_bonus(delta: float, player: CharacterBody2D, scene: Node2D) -> float:
    ## Reward AI for being close to powerups (continuous shaping signal).
    var bonus := 0.0
    var frame := Engine.get_physics_frames()
    if frame != _cached_powerups_frame:
        _cached_powerups = scene.get_tree().get_nodes_in_group("powerup")
        _cached_powerups_frame = frame
    var powerups := _cached_powerups
    var nearest_dist := 99999.0
    for powerup in powerups:
        if not is_instance_valid(powerup) or powerup.get_parent() != scene:
            continue
        var dist = player.position.distance_to(powerup.position)
        nearest_dist = minf(nearest_dist, dist)
    if nearest_dist < 1500:
        var proximity_factor = 1.0 - (nearest_dist / 1500.0)
        bonus = 100.0 * proximity_factor * delta
    return bonus
