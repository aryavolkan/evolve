extends RefCounted
## W&B JSON metrics serialization and MAP-Elites archive updates.
## Extracted from training_manager.gd to reduce its responsibility.


func write_wandb_metrics(state: Dictionary, metrics_path: String) -> void:
    ## Write metrics to JSON for W&B Python bridge to read.
    ## state contains all scalar values needed for the metrics dict.
    var file = FileAccess.open(metrics_path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(state))
        file.close()


func update_map_elites_archive(archive: MapElites, evolution,
                                stats_tracker: RefCounted, population_size: int,
                                use_neat: bool) -> void:
    ## Add current generation's individuals to the MAP-Elites archive.
    ## Called after fitness is set but before evolve() mutates the population.
    for idx in population_size:
        var avg_beh = stats_tracker.get_avg_behavior(idx)
        if avg_beh.is_empty():
            continue

        var behavior: Vector2 = MapElites.calculate_behavior(avg_beh)
        var avg_fitness: float = stats_tracker.get_avg_fitness(idx)

        # Clone the solution before evolution mutates it
        var solution
        if use_neat:
            solution = evolution.get_individual(idx).copy()
        else:
            solution = evolution.get_individual(idx).clone()

        archive.add(solution, behavior, avg_fitness)
