# Refined sweep config based on best results from x0cst76l
# Best performer: comfy-sweep-22 (fitness 147,672)
#   pop=120, hidden=80, elite=20, mut_rate=0.270, mut_str=0.110, crossover=0.704

sweep_config = {
    'method': 'bayes',
    'metric': {'name': 'all_time_best', 'goal': 'maximize'},
    'parameters': {
        # Population - narrow range around best (120)
        'population_size': {'values': [100, 120, 150]},

        # Selection - keep best performers
        'elite_count': {'values': [15, 20, 25]},

        # Mutation - tighten around optimal values
        'mutation_rate': {'distribution': 'uniform', 'min': 0.2, 'max': 0.35},
        'mutation_strength': {'distribution': 'uniform', 'min': 0.08, 'max': 0.15},

        # Crossover - narrow around 0.7
        'crossover_rate': {'distribution': 'uniform', 'min': 0.65, 'max': 0.80},

        # Network architecture - ADD 80 (was missing!) and explore around it
        'hidden_size': {'values': [64, 80, 96]},

        # Training
        'max_generations': {'value': 50},
        'evals_per_individual': {'values': [2, 3]},  # Skip 1, focus on stable estimates
        'time_scale': {'value': 16.0},
        'parallel_count': {'value': 10},
    }
}

# Alternative: EXPLOITATION sweep (even tighter, for quick wins)
sweep_config_exploit = {
    'method': 'grid',  # Grid search for thoroughness
    'metric': {'name': 'all_time_best', 'goal': 'maximize'},
    'parameters': {
        'population_size': {'values': [120, 140]},
        'elite_count': {'values': [20, 25]},
        'mutation_rate': {'values': [0.25, 0.27, 0.30]},
        'mutation_strength': {'values': [0.10, 0.11, 0.12]},
        'crossover_rate': {'values': [0.70, 0.75]},
        'hidden_size': {'values': [80, 96]},
        'max_generations': {'value': 50},
        'evals_per_individual': {'value': 3},
        'time_scale': {'value': 16.0},
        'parallel_count': {'value': 10},
    }
}

# Alternative: EXPLORATION sweep (wider ranges, test new territory)
sweep_config_explore = {
    'method': 'bayes',
    'metric': {'name': 'all_time_best', 'goal': 'maximize'},
    'parameters': {
        'population_size': {'values': [120, 180, 240]},  # Test larger pops
        'elite_count': {'values': [20, 30, 40]},  # Scale elites with pop
        'mutation_rate': {'distribution': 'uniform', 'min': 0.15, 'max': 0.40},
        'mutation_strength': {'distribution': 'uniform', 'min': 0.05, 'max': 0.20},
        'crossover_rate': {'distribution': 'uniform', 'min': 0.60, 'max': 0.85},
        'hidden_size': {'values': [80, 96, 112]},  # Explore larger networks
        'max_generations': {'value': 50},
        'evals_per_individual': {'values': [2, 3, 4]},  # Test more stable evals
        'time_scale': {'value': 16.0},
        'parallel_count': {'value': 10},
    }
}
