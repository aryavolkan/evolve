extends RefCounted
class_name DifficultyScaler

## Computes difficulty-dependent values: enemy speed, spawn intervals, etc.

const BASE_ENEMY_SPEED: float = 150.0
const MAX_ENEMY_SPEED: float = 450.0  # Must exceed player speed (300) so enemies can threaten at high difficulty
const BASE_SPAWN_INTERVAL: float = 50.0
const MIN_SPAWN_INTERVAL: float = 20.0
const DIFFICULTY_SCALE_SCORE: float = 500.0  # Score at which difficulty is maxed


func get_difficulty_factor(score: float) -> float:
	return clampf(score / DIFFICULTY_SCALE_SCORE, 0.0, 1.0)


func get_scaled_enemy_speed(score: float) -> float:
	var factor := get_difficulty_factor(score)
	return lerpf(BASE_ENEMY_SPEED, MAX_ENEMY_SPEED, factor)


func get_scaled_spawn_interval(score: float, sandbox_spawn_rate_multiplier: float = 1.0, sandbox_overrides_active: bool = false) -> float:
	var factor := get_difficulty_factor(score)
	var interval := lerpf(BASE_SPAWN_INTERVAL, MIN_SPAWN_INTERVAL, factor)
	if sandbox_overrides_active:
		interval = interval / maxf(sandbox_spawn_rate_multiplier, 0.1)
	return interval
