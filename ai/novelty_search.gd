extends RefCounted
class_name NoveltySearch

## Novelty search module for rtNEAT.
## Computes behavioral novelty scores based on how different an agent's
## behavior characterization is from its k-nearest neighbors in the archive
## and current population.

# Behavior archive — stores characteristic vectors of past agents
var archive: Array[PackedFloat32Array] = []
var max_archive_size: int = 500
var archive_add_threshold: float = 20.0  # Min novelty to enter archive

# Configuration
var k_nearest: int = 15  # Number of neighbors for novelty calculation
var novelty_weight: float = 0.5  # Blend: 0.0 = pure fitness, 1.0 = pure novelty

# Behavior characterization dimensions:
#   [0] final_x normalized
#   [1] final_y normalized
#   [2] distance_traveled normalized
#   [3] enemies_killed normalized
#   [4] powerups_collected normalized
#   [5] movement_entropy (how varied the movement directions were)
#   [6] avg_distance_to_center normalized
#   [7] time_alive normalized
const BC_SIZE: int = 8


static func characterize(agent_data: Dictionary, arena_width: float = 3840.0, arena_height: float = 3840.0) -> PackedFloat32Array:
    ## Build a behavior characterization vector from agent lifetime data.
    var bc := PackedFloat32Array()
    bc.resize(BC_SIZE)

    bc[0] = agent_data.get("final_x", 0.0) / arena_width
    bc[1] = agent_data.get("final_y", 0.0) / arena_height
    bc[2] = clampf(agent_data.get("distance_traveled", 0.0) / 5000.0, 0.0, 1.0)
    bc[3] = clampf(agent_data.get("enemies_killed", 0.0) / 20.0, 0.0, 1.0)
    bc[4] = clampf(agent_data.get("powerups_collected", 0.0) / 10.0, 0.0, 1.0)
    bc[5] = clampf(agent_data.get("movement_entropy", 0.0), 0.0, 1.0)
    bc[6] = clampf(agent_data.get("avg_center_distance", 0.0) / (arena_width * 0.5), 0.0, 1.0)
    bc[7] = clampf(agent_data.get("time_alive", 0.0) / 120.0, 0.0, 1.0)

    return bc


func compute_novelty(bc: PackedFloat32Array, population_bcs: Array[PackedFloat32Array]) -> float:
    ## Compute novelty as mean distance to k-nearest neighbors
    ## across both the archive and current population behaviors.
    var all_bcs: Array[PackedFloat32Array] = []
    all_bcs.append_array(archive)
    all_bcs.append_array(population_bcs)

    if all_bcs.size() == 0:
        return 0.0

    # Compute distances to all points
    var distances: Array[float] = []
    for other_bc in all_bcs:
        distances.append(_bc_distance(bc, other_bc))

    # Sort and take k-nearest
    distances.sort()
    var k: int = mini(k_nearest, distances.size())
    var total: float = 0.0
    for i in k:
        total += distances[i]

    return total / float(k) if k > 0 else 0.0


func maybe_add_to_archive(bc: PackedFloat32Array, novelty_score: float) -> bool:
    ## Add behavior to archive if sufficiently novel.
    if novelty_score >= archive_add_threshold:
        archive.append(bc)
        # Trim archive if too large (remove oldest)
        while archive.size() > max_archive_size:
            archive.remove_at(0)
        return true
    return false


func blend_fitness(raw_fitness: float, novelty_score: float) -> float:
    ## Blend raw fitness with novelty score.
    ## Both should be normalized or on comparable scales.
    return (1.0 - novelty_weight) * raw_fitness + novelty_weight * novelty_score


func _bc_distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
    ## Euclidean distance between two behavior characterizations.
    var sum_sq: float = 0.0
    for i in BC_SIZE:
        var diff: float = a[i] - b[i]
        sum_sq += diff * diff
    return sqrt(sum_sq)


func get_stats() -> Dictionary:
    return {
        "archive_size": archive.size(),
        "archive_threshold": archive_add_threshold,
        "novelty_weight": novelty_weight,
        "k_nearest": k_nearest,
    }
