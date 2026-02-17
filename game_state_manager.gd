extends RefCounted
class_name GameStateManager

## Manages core game state: score, lives, kills, survival time, and game-over flow.

signal game_over_triggered(final_score: float)
signal life_lost(remaining: int)

var score: float = 0.0
var lives: int = 3
var game_over: bool = false
var kills: int = 0
var powerups_collected: int = 0
var score_from_kills: float = 0.0
var score_from_powerups: float = 0.0
var survival_time: float = 0.0
var last_milestone: int = 0
var entering_name: bool = false

const RESPAWN_INVINCIBILITY: float = 2.0


func reset() -> void:
	score = 0.0
	lives = 3
	game_over = false
	kills = 0
	powerups_collected = 0
	score_from_kills = 0.0
	score_from_powerups = 0.0
	survival_time = 0.0
	last_milestone = 0
	entering_name = false


func add_score(amount: float) -> void:
	score += amount


func add_kill(points: int, multiplier: float, kill_multiplier: int) -> float:
	## Record a kill and return the bonus score awarded.
	kills += 1
	var bonus: float = points * kill_multiplier * multiplier
	score += bonus
	score_from_kills += bonus
	return bonus


func update_survival(delta: float, milestone_interval: float, milestone_bonus: int) -> void:
	## Advance survival timer and award milestone bonuses.
	survival_time += delta
	var current_milestone := int(survival_time / milestone_interval)
	if current_milestone > last_milestone:
		var bonus: float = milestone_bonus * current_milestone
		score += bonus
		last_milestone = current_milestone


func take_hit() -> void:
	## Process a player hit. Emits life_lost or game_over_triggered.
	lives -= 1
	if lives <= 0:
		game_over = true
		game_over_triggered.emit(score)
	else:
		life_lost.emit(lives)


func get_stats() -> Dictionary:
	return {
		"score": score,
		"kills": kills,
		"powerups_collected": powerups_collected,
		"survival_time": survival_time,
		"score_from_kills": score_from_kills,
		"score_from_powerups": score_from_powerups,
	}
