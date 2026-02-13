# Evolve

A 2D arcade survival game built with Godot 4.5+ where you dodge chess-piece enemies, collect power-ups, and compete for high scores — or let a neuroevolution AI learn to play for you.

![Gameplay](assets/gameplay.png)

## Gameplay

- Move with **arrow keys**, shoot with **WASD**
- Enemies are chess pieces (pawns, knights, bishops, rooks, queens) with chess-inspired movement patterns on a virtual grid
- Collect power-ups for speed boosts, invincibility, screen clears, and more
- Score increases over time and from killing enemies
- Difficulty ramps up as your score grows
- 3 lives, with respawn invincibility

## Running

Requires [Godot 4.5+](https://godotengine.org/download).

```bash
# Open in editor
godot --path . --editor

# Play directly
godot --path . --play
```

## Architecture

```mermaid
flowchart LR
    subgraph Training Loop
        TM[training_manager.gd\nOrchestrator]
        CM[curriculum_manager.gd\nStage Progression]
        ST[stats_tracker.gd\nFitness & Metrics]
    end

    subgraph Evolution
        EVO[evolution.gd\nPopulation & Selection]
        NEAT[neat_evolution.gd\nTopology Evolution]
        NSGA[nsga2.gd\nMulti-Objective]
        ME[map_elites.gd\nQuality-Diversity]
    end

    subgraph Neural Network
        NN[neural_network.gd\nFixed Topology]
        NEATN[neat_network.gd\nVariable Topology]
    end

    subgraph Agent
        AIC[ai_controller.gd\nAction Selection]
        SEN[sensor.gd\n16 Raycasts → 86 Inputs]
    end

    subgraph Game
        MAIN[main.gd\nArena & Spawning]
        PLAYER[player.gd\nMovement & Shooting]
        ENEMY[enemy.gd\nChess Pieces]
        PWR[powerup.gd\nCollectibles]
    end

    TM -->|creates & evolves| EVO
    TM -->|or| NEAT
    TM --> CM
    TM --> ST
    EVO --> NN
    NEAT --> NEATN
    EVO --> NSGA
    EVO --> ME
    NN --> AIC
    NEATN --> AIC
    AIC -->|move + shoot| PLAYER
    SEN -->|86 floats| NN
    SEN -->|86 floats| NEATN
    SEN -.->|raycasts| ENEMY
    SEN -.->|raycasts| PWR
    MAIN --> PLAYER
    MAIN --> ENEMY
    MAIN --> PWR
    ST -.->|W&B metrics.json| WB[wandb_bridge.py]
```

**Data flow:** Each generation, `training_manager` assigns neural networks from the evolution system to AI controllers in parallel arenas. Sensors feed 86 inputs (16 raycasts × 5 values + 6 player state) into the network, which outputs 6 actions (movement + shooting). Fitness scores flow back to the evolution system for selection and mutation.

## AI Training

![AI Training](assets/training.png)

Neural networks learn to play through neuroevolution — a population of agents evolves over generations using tournament selection, crossover, and mutation.

### Network Architecture

- **86 inputs**: 16 raycasts (enemy distance/type, obstacles, power-ups, walls) + player state
- **80 hidden neurons** (tanh activation, configurable)
- **6 outputs**: movement (x/y) + shoot directions

### Controls

| Key | Action |
|-----|--------|
| T | Start/stop training (48 parallel arenas) |
| P | Watch the best AI play |
| H | Return to human control |
| [ / ] | Adjust training speed (1x-8x) |

### Headless Training

```bash
godot --path . --headless -- --auto-train
```

### W&B Sweep Integration

Run hyperparameter sweeps with Weights & Biases:

```bash
cd overnight-agent
python overnight_evolve.py --project evolve-neuroevolution-new
```

## Testing

Run the headless test suite:

```bash
godot --headless --script test/test_runner.gd
```

## Project Structure

```
├── main.tscn/gd           # Game manager, UI, spawning
├── player.tscn/gd         # Player movement, collision, shooting
├── enemy.tscn/gd          # Chess piece enemies with grid movement
├── powerup.tscn/gd        # 10 power-up types
├── projectile.tscn/gd     # Player projectiles
├── training_manager.gd    # Training orchestration
├── ai/                    # Neural network, sensors, evolution
├── scripts/               # W&B bridge scripts
├── overnight-agent/       # Headless sweep runner
└── test/                  # Test suite
```
