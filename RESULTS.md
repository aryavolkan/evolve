# Evolve — Training Results & Sweep Findings

**Last Updated:** 2026-02-10

---

## Best Hyperparameters

### Sweep x0cst76l (Current Best)

**Best run:** `comfy-sweep-22` — Fitness **147,672**

| Parameter | Value |
|-----------|-------|
| Population size | 120 |
| Hidden neurons | 80 |
| Elite count | 20 |
| Mutation rate | 0.270 |
| Mutation strength | 0.110 |
| Crossover rate | 0.704 |
| Evals per individual | 2 |
| Max generations | 50 |
| Parallel arenas | 10 |
| Time scale | 16× |

**Sweep method:** Bayesian optimization  
**Metric optimized:** `all_time_best` (maximize)

#### Parameter Ranges Searched

| Parameter | Range |
|-----------|-------|
| Population size | [100, 120, 150] |
| Hidden neurons | [64, 80, 96] |
| Elite count | [15, 20, 25] |
| Mutation rate | 0.20–0.35 (uniform) |
| Mutation strength | 0.08–0.15 (uniform) |
| Crossover rate | 0.65–0.80 (uniform) |
| Evals per individual | [2, 3] |

### Sweep 8hhcv03h (Previous Best)

**Best run:** `rose-sweep-17` — Fitness **115,272**

This earlier sweep used wider parameter ranges and discovered that hidden=80 was missing from the search space, leading to the refined sweep x0cst76l.

---

## Key Observations

### What Works

1. **Larger hidden layers help.** 80 hidden neurons significantly outperformed the original 32. The network needs capacity to encode complex spatial relationships from 86 sensor inputs.

2. **Moderate mutation is optimal.** Mutation rate ~0.27 with strength ~0.11 balances exploration and exploitation. Too high (>0.35) destroys good solutions; too low (<0.15) stagnates.

3. **High crossover rate.** 0.70 crossover rate enables productive recombination of evolved strategies. Two-point crossover preserves useful weight blocks.

4. **Multi-seed evaluation (evals=2+) is critical.** Single-seed evaluation produces brittle networks that exploit specific spawn patterns. Two seeds provides a good robustness/speed tradeoff.

5. **Elite count ~17% of population.** 20 elites out of 120 (16.7%) preserves proven solutions while allowing enough slots for exploration.

6. **Curriculum learning accelerates early training.** Progressive difficulty staging (nursery → elementary → intermediate → advanced → final) lets agents learn basic movement before facing complex scenarios. Cuts wasted compute on early generations by ~50%.

### What Doesn't Work

1. **Very small populations (<50).** Insufficient diversity for evolution to find good solutions. Tournament selection needs a critical mass.

2. **Single evaluation seed.** Networks overfit to specific enemy spawn patterns and fail on different seeds.

3. **Aggressive mutation (>0.35 rate, >0.20 strength).** Destroys the gradient of improvement that selection builds.

4. **Very large populations (>200) with limited generations.** Not enough generations for the population to converge. Better to run 120 individuals for 50 generations than 200 for 30.

---

## Algorithm Notes

### Evolution Pipeline

1. **Tournament selection** (best of 3 random) picks parents
2. **Two-point crossover** (70% rate) combines parent weights
3. **Gaussian mutation** (27% rate, σ=0.11) perturbs offspring weights
4. **Elitism** preserves top 20 unchanged
5. **Fitness averaging** across 2 seeds per individual

### Available Algorithms

| Algorithm | Status | Use Case |
|-----------|--------|----------|
| Fixed-topology evolution | ✅ Production | Default training, sweep optimization |
| NEAT (topology evolution) | ✅ Working | Explores network structure alongside weights |
| NSGA-II (multi-objective) | ✅ Working | Optimizes survival/kills/collection simultaneously |
| MAP-Elites (quality-diversity) | ✅ Working | Maintains archive of diverse strategies |
| Curriculum learning | ✅ Production | Progressive difficulty staging |

### Curriculum Stages

| Stage | Arena Scale | Enemy Types | Advancement Threshold |
|-------|------------|-------------|----------------------|
| 0: Nursery | 25% | Pawns | 5,000 avg fitness |
| 1: Elementary | 50% | Pawns, Knights | 10,000 |
| 2: Intermediate | 75% | +Bishops | 15,000 |
| 3: Advanced | 100% | +Rooks | 12,000 |
| 4: Final | 100% | +Queens | — (terminal) |

### Fitness Function

```
fitness = survival_score + kill_score + powerup_score + shaping_bonuses

survival_score:
  +5 points/second survived
  +100 points milestone every 15 seconds (increasing)

kill_score:
  +1000× chess piece value per kill
  (pawn=1000, knight=3000, bishop=3000, rook=5000, queen=9000)

powerup_score:
  +5000 per powerup collected
  +8000 bonus for screen clear
  +proximity bonus for being near powerups (continuous)

shaping_bonuses:
  +50 for shooting toward enemies (training only)
```

---

## Reproducing Results

### Quick Training Run

```bash
# Headless training with default (optimal) parameters
godot --path . --headless -- --auto-train
```

### W&B Sweep

```bash
cd overnight-agent
python overnight_evolve.py --project evolve-neuroevolution --hours 8
```

### Join Existing Sweep

```bash
python overnight_evolve.py --project evolve-neuroevolution --sweep-id x0cst76l
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for full setup instructions.
