extends RefCounted
class_name RtNeatPopulation

## Continuous replacement population manager for rtNEAT.
## Wraps existing NEAT components (NeatGenome, NeatNetwork, NeatSpecies, NeatInnovation, NeatConfig).
## No discrete generations — worst agent is periodically replaced by offspring of fittest.

# Configuration
var config: NeatConfig
var innovation_tracker: NeatInnovation
var pop_size: int = 30
var replacement_interval: float = 15.0  # Seconds between replacements
var min_lifetime: float = 10.0  # Minimum age before eligible for replacement

# Parallel arrays indexed by agent slot
var genomes: Array = []  # Array[NeatGenome]
var networks: Array = []  # Array[NeatNetwork]
var fitnesses: PackedFloat32Array
var ages: PackedFloat32Array
var alive: Array = []  # Array[bool]
var species_ids: PackedInt32Array

# Species management
var species_list: Array = []  # Array[NeatSpecies]
var _next_species_id: int = 0
var _replacements_since_respeciate: int = 0
const RESPECIATE_EVERY: int = 10  # Full respeciation every N replacements

# Stats
var total_replacements: int = 0
var all_time_best_fitness: float = 0.0
var all_time_best_genome: NeatGenome = null
var _replacement_timer: float = 0.0

# Lineage tracking (optional, set externally)
var lineage: RefCounted = null
var lineage_ids: PackedInt32Array  # Per-slot lineage IDs

# Species color palette (12 visually distinct colors)
const SPECIES_COLORS: Array = [
    Color(0.2, 0.6, 1.0),   # Blue
    Color(1.0, 0.3, 0.3),   # Red
    Color(0.3, 0.9, 0.3),   # Green
    Color(1.0, 0.7, 0.1),   # Gold
    Color(0.8, 0.3, 0.9),   # Purple
    Color(0.1, 0.9, 0.8),   # Teal
    Color(1.0, 0.5, 0.2),   # Orange
    Color(0.6, 0.8, 0.2),   # Lime
    Color(0.9, 0.2, 0.6),   # Pink
    Color(0.4, 0.4, 0.9),   # Indigo
    Color(0.9, 0.9, 0.2),   # Yellow
    Color(0.3, 0.7, 0.5),   # Sea green
]


func initialize(size: int, p_config: NeatConfig = null) -> void:
    ## Create initial random population and speciate.
    pop_size = size

    if p_config:
        config = p_config
    else:
        config = NeatConfig.new()
        config.input_count = 86
        config.output_count = 6
        config.population_size = size

    innovation_tracker = NeatInnovation.new(config.input_count + config.output_count + int(config.use_bias))

    # Create genomes and compile networks
    genomes.clear()
    networks.clear()
    alive.clear()
    fitnesses.resize(size)
    ages.resize(size)
    species_ids.resize(size)

    for i in size:
        var genome := NeatGenome.create(config, innovation_tracker)
        genome.create_basic()
        genomes.append(genome)
        networks.append(NeatNetwork.from_genome(genome))
        alive.append(true)
        fitnesses[i] = 0.0
        ages[i] = 0.0
        species_ids[i] = 0

    # Initial speciation
    _full_speciate()

    # Seed lineage if tracker is set
    if lineage:
        var ids = lineage.record_seed(0, pop_size)
        lineage_ids.resize(pop_size)
        for i in pop_size:
            lineage_ids[i] = ids[i]


func update_fitness(index: int, delta_fitness: float) -> void:
    ## Accumulate fitness for an agent.
    if index >= 0 and index < pop_size:
        fitnesses[index] += delta_fitness


func set_fitness(index: int, value: float) -> void:
    ## Set absolute fitness for an agent.
    if index >= 0 and index < pop_size:
        fitnesses[index] = value


func mark_dead(index: int) -> void:
    ## Flag agent as out of lives.
    if index >= 0 and index < pop_size:
        alive[index] = false


func tick(delta: float) -> int:
    ## Advance ages and check replacement timer.
    ## Returns index to replace, or -1 if no replacement this tick.
    for i in pop_size:
        if alive[i]:
            ages[i] += delta

    # Dead agents get replaced immediately (one per frame)
    for i in pop_size:
        if not alive[i]:
            return i

    _replacement_timer += delta
    if _replacement_timer < replacement_interval:
        return -1

    _replacement_timer = 0.0

    # Find the worst eligible living agent
    return _find_worst_eligible()


func _find_worst_eligible() -> int:
    ## Find the agent with lowest adjusted fitness that is eligible for replacement.
    ## Dead agents are always eligible. Living agents need age >= min_lifetime.
    var worst_idx: int = -1
    var worst_score: float = INF

    # Compute species sizes for adjusted fitness
    var species_sizes: Dictionary = {}
    for i in pop_size:
        var sid: int = species_ids[i]
        species_sizes[sid] = species_sizes.get(sid, 0) + 1

    for i in pop_size:
        var eligible: bool = false
        if not alive[i]:
            eligible = true  # Dead agents always eligible
        elif ages[i] >= min_lifetime:
            eligible = true

        if not eligible:
            continue

        # Adjusted fitness = fitness / species_size (fitness sharing)
        var sp_size: int = species_sizes.get(species_ids[i], 1)
        var adjusted: float = fitnesses[i] / float(sp_size)

        # Dead agents get penalty to prioritize their replacement
        if not alive[i]:
            adjusted = -1.0

        if adjusted < worst_score:
            worst_score = adjusted
            worst_idx = i

    return worst_idx


func do_replacement(index: int) -> Dictionary:
    ## Replace agent at index with offspring. Returns {genome, network, species_color}.
    # Tournament select two parents (best of 3 random)
    var parent_a_idx: int = _tournament_select(3)
    var parent_b_idx: int = _tournament_select(3)
    # Ensure different parents
    var attempts: int = 0
    while parent_b_idx == parent_a_idx and attempts < 5:
        parent_b_idx = _tournament_select(3)
        attempts += 1

    # Crossover + mutate
    var child: NeatGenome
    if randf() < config.crossover_rate and parent_a_idx != parent_b_idx:
        child = NeatGenome.crossover(genomes[parent_a_idx], genomes[parent_b_idx])
    else:
        child = genomes[parent_a_idx].copy()

    child.mutate(config)

    # Track all-time best before replacing
    if fitnesses[index] > all_time_best_fitness or (all_time_best_genome == null and fitnesses[index] > 0):
        # Don't track the one we're replacing as best; check all
        pass
    _update_all_time_best()

    # Record lineage before installing
    if lineage and lineage_ids.size() > 0:
        var lid_a: int = lineage_ids[parent_a_idx] if parent_a_idx < lineage_ids.size() else -1
        var lid_b: int = lineage_ids[parent_b_idx] if parent_b_idx < lineage_ids.size() else -1
        var origin: String = "crossover" if parent_a_idx != parent_b_idx and randf() < config.crossover_rate else "mutation"
        var gen: int = total_replacements  # Use replacement count as pseudo-generation
        lineage_ids[index] = lineage.record_birth(gen, lid_a, lid_b, 0.0, origin)

    # Install new genome
    genomes[index] = child
    networks[index] = NeatNetwork.from_genome(child)
    fitnesses[index] = 0.0
    ages[index] = 0.0
    alive[index] = true

    # Incremental speciation for the new genome
    _speciate_single(index)

    total_replacements += 1
    _replacements_since_respeciate += 1

    # Full respeciation periodically to prevent drift
    if _replacements_since_respeciate >= RESPECIATE_EVERY:
        _full_speciate()
        _replacements_since_respeciate = 0

    return {
        "genome": child,
        "network": networks[index],
        "species_color": get_species_color(index),
        "parent_a": parent_a_idx,
        "parent_b": parent_b_idx,
    }


func _tournament_select(k: int) -> int:
    ## Select the fittest of k random agents.
    var best_idx: int = randi() % pop_size
    var best_fit: float = fitnesses[best_idx]
    for i in range(1, k):
        var idx: int = randi() % pop_size
        if fitnesses[idx] > best_fit:
            best_fit = fitnesses[idx]
            best_idx = idx
    return best_idx


func _speciate_single(index: int) -> void:
    ## Assign a single genome to an existing species, or create a new one.
    var genome: NeatGenome = genomes[index]
    for species in species_list:
        if species.representative:
            var dist: float = genome.compatibility(species.representative, config)
            if dist < config.compatibility_threshold:
                species_ids[index] = species.id
                return

    # No compatible species found — create new one
    var new_species := NeatSpecies.new(_next_species_id, genome)
    species_list.append(new_species)
    species_ids[index] = _next_species_id
    _next_species_id += 1


func _full_speciate() -> void:
    ## Full respeciation of entire population.
    var result: Dictionary = NeatSpecies.speciate(genomes, species_list, config, _next_species_id)
    species_list = result.species
    _next_species_id = result.next_id

    # Update species_ids array from species membership
    # Build genome → species_id map
    var genome_to_species: Dictionary = {}
    for species in species_list:
        for member in species.members:
            genome_to_species[member] = species.id

    for i in pop_size:
        species_ids[i] = genome_to_species.get(genomes[i], 0)


func _update_all_time_best() -> void:
    for i in pop_size:
        if fitnesses[i] > all_time_best_fitness:
            all_time_best_fitness = fitnesses[i]
            all_time_best_genome = genomes[i].copy()


func get_species_color(index: int) -> Color:
    ## Deterministic color by species ID.
    if index < 0 or index >= pop_size:
        return Color.WHITE
    var sid: int = species_ids[index]
    return SPECIES_COLORS[sid % SPECIES_COLORS.size()]


func get_species_count() -> int:
    return species_list.size()


func get_stats() -> Dictionary:
    var best_fit: float = 0.0
    var total_fit: float = 0.0
    var alive_count: int = 0
    for i in pop_size:
        if fitnesses[i] > best_fit:
            best_fit = fitnesses[i]
        total_fit += fitnesses[i]
        if alive[i]:
            alive_count += 1

    _update_all_time_best()

    # Species member counts
    var species_counts: Dictionary = {}
    for i in pop_size:
        var sid: int = species_ids[i]
        species_counts[sid] = species_counts.get(sid, 0) + 1

    return {
        "agent_count": pop_size,
        "alive_count": alive_count,
        "species_count": get_species_count(),
        "species_counts": species_counts,
        "best_fitness": best_fit,
        "all_time_best": all_time_best_fitness,
        "avg_fitness": total_fit / pop_size if pop_size > 0 else 0.0,
        "total_replacements": total_replacements,
    }


func save_best(path: String) -> void:
    _update_all_time_best()
    if not all_time_best_genome:
        return
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(all_time_best_genome.serialize()))
        file.close()


func save_population(path: String) -> void:
    var genome_data: Array = []
    for i in pop_size:
        genome_data.append({
            "genome": genomes[i].serialize(),
            "fitness": fitnesses[i],
            "age": ages[i],
            "alive": alive[i],
            "species_id": species_ids[i],
        })
    var data := {
        "pop_size": pop_size,
        "total_replacements": total_replacements,
        "all_time_best_fitness": all_time_best_fitness,
        "all_time_best_genome": all_time_best_genome.serialize() if all_time_best_genome else null,
        "agents": genome_data,
    }
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))
        file.close()


func load_population(path: String) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return false
    var json := JSON.new()
    if json.parse(file.get_as_text()) != OK:
        file.close()
        return false
    file.close()
    var data: Dictionary = json.data

    pop_size = int(data.get("pop_size", 30))
    total_replacements = int(data.get("total_replacements", 0))
    all_time_best_fitness = float(data.get("all_time_best_fitness", 0.0))

    var atb_data = data.get("all_time_best_genome")
    if atb_data and atb_data is Dictionary:
        all_time_best_genome = NeatGenome.deserialize(atb_data, config, innovation_tracker)

    genomes.clear()
    networks.clear()
    alive.clear()
    fitnesses.resize(pop_size)
    ages.resize(pop_size)
    species_ids.resize(pop_size)

    var agents: Array = data.get("agents", [])
    for i in mini(agents.size(), pop_size):
        var agent_data: Dictionary = agents[i]
        var genome := NeatGenome.deserialize(agent_data.get("genome", {}), config, innovation_tracker)
        genomes.append(genome)
        networks.append(NeatNetwork.from_genome(genome))
        fitnesses[i] = float(agent_data.get("fitness", 0.0))
        ages[i] = float(agent_data.get("age", 0.0))
        alive.append(bool(agent_data.get("alive", true)))
        species_ids[i] = int(agent_data.get("species_id", 0))

    # Fill remaining if file had fewer agents
    while genomes.size() < pop_size:
        var idx: int = genomes.size()
        var genome := NeatGenome.create(config, innovation_tracker)
        genome.create_basic()
        genomes.append(genome)
        networks.append(NeatNetwork.from_genome(genome))
        alive.append(true)
        fitnesses[idx] = 0.0
        ages[idx] = 0.0
        species_ids[idx] = 0

    _full_speciate()
    return true
