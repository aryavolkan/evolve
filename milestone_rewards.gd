extends RefCounted
class_name MilestoneRewards

## Milestone rewards system that scales player abilities based on fitness achievements.
## Tracks milestone tiers and emits signals when the tier changes.

signal tier_changed(new_tier: int, tier_name: String)

# Milestone tiers based on fitness thresholds
const MILESTONE_TIERS = [
    {"threshold": 50000, "name": "Emerging", "tier": 1},
    {"threshold": 100000, "name": "Advanced", "tier": 2},
    {"threshold": 150000, "name": "Elite", "tier": 3},
    {"threshold": 175000, "name": "Legendary", "tier": 4},
]

# Reward multipliers per tier (index 0 = no milestone, 1-4 = tiers 1-4)
const SPEED_MULTIPLIERS = [1.0, 1.0, 1.05, 1.1, 1.15]
const SIZE_SCALES = [1.0, 1.0, 1.05, 1.1, 1.15]
const COOLDOWN_MULTIPLIERS = [1.0, 1.0, 0.95, 0.9, 0.85]  # Lower = faster shooting

# Visual colors per tier
const TIER_COLORS = [
    Color(1.0, 1.0, 1.0),       # Tier 0: Normal (white)
    Color(0.8, 0.9, 1.0),       # Tier 1: Emerging (slight blue tint)
    Color(1.0, 0.9, 0.6),       # Tier 2: Advanced (gold tint)
    Color(1.0, 0.85, 0.3),      # Tier 3: Elite (bright gold)
    Color(1.0, 1.0, 1.0),       # Tier 4: Legendary (rainbow shimmer, base white)
]

var current_tier: int = 0
var current_tier_name: String = "None"
var current_fitness: float = 0.0

# For legendary rainbow effect
var rainbow_time: float = 0.0


func update_fitness(fitness: float) -> void:
    ## Update the current fitness and check for tier changes.
    current_fitness = fitness
    var new_tier = get_tier_for_fitness(fitness)

    if new_tier != current_tier:
        current_tier = new_tier
        current_tier_name = get_tier_name(new_tier)
        tier_changed.emit(new_tier, current_tier_name)


func get_tier_for_fitness(fitness: float) -> int:
    ## Get the milestone tier for a given fitness score.
    var tier = 0
    for milestone in MILESTONE_TIERS:
        if fitness >= milestone.threshold:
            tier = milestone.tier
        else:
            break
    return tier


func get_tier_name(tier: int) -> String:
    ## Get the name of a milestone tier.
    if tier <= 0:
        return "None"
    for milestone in MILESTONE_TIERS:
        if milestone.tier == tier:
            return milestone.name
    return "Unknown"


func get_speed_multiplier() -> float:
    ## Get the speed multiplier for the current tier.
    return SPEED_MULTIPLIERS[current_tier]


func get_size_scale() -> float:
    ## Get the size scale for the current tier.
    return SIZE_SCALES[current_tier]


func get_cooldown_multiplier() -> float:
    ## Get the shoot cooldown multiplier for the current tier.
    return COOLDOWN_MULTIPLIERS[current_tier]


func get_tier_color(delta: float = 0.0) -> Color:
    ## Get the visual color for the current tier.
    ## For legendary tier, returns an animated rainbow color.
    if current_tier < 4:
        return TIER_COLORS[current_tier]

    # Legendary tier: rainbow shimmer effect
    rainbow_time += delta * 2.0  # Speed of color cycling
    var hue = fmod(rainbow_time, 1.0)
    return Color.from_hsv(hue, 0.7, 1.0)


func get_tier_info() -> Dictionary:
    ## Get comprehensive information about the current tier.
    return {
        "tier": current_tier,
        "name": current_tier_name,
        "fitness": current_fitness,
        "speed_mult": get_speed_multiplier(),
        "size_scale": get_size_scale(),
        "cooldown_mult": get_cooldown_multiplier(),
        "color": TIER_COLORS[min(current_tier, TIER_COLORS.size() - 1)],
    }


func reset() -> void:
    ## Reset the milestone system to default state.
    current_tier = 0
    current_tier_name = "None"
    current_fitness = 0.0
    rainbow_time = 0.0