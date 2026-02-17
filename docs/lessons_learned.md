# Lessons Learned — Evolve & Chess-Evolve

**Date:** 2026-02-17  
**Context:** ~2 years on Evolve + 2 weeks on Chess-Evolve, with multi-agent AI collaboration throughout.

This document captures **process, tooling, and hard-won debugging lessons** — the stuff that bit us, surprised us, or changed how we work. For architecture differences and technical comparisons, see [`architecture_comparison.md`](./architecture_comparison.md).

---

## 🦀 Rust GDExtension

### The API feature flag matters — a lot
When integrating godot-rust, the Cargo.toml feature flag must match your Godot version exactly:
```toml
# ❌ Wrong — Godot crashes silently on load
gdext = { git = "...", features = ["api-4-4"] }

# ✅ Correct for Godot 4.6
gdext = { git = "...", features = ["api-4-6"] }
```
Using the wrong API version causes Godot to crash immediately when loading the extension, with a vague error. Check `godot --version` and match the feature flag exactly.

### The speedup was staggering
After fixing the feature flag, the Rust neural network was **73× faster** than GDScript (3.94 µs vs 287.86 µs per forward pass). This wasn't a micro-optimization — it fundamentally changed what's feasible. If you hit a GDScript performance ceiling, Rust GDExtension is the right tool.

### Build takes ~3 minutes but is incremental
First `cargo build --release` is slow (~3 min). Subsequent builds on changed files are fast (<30s). Keep the `.dylib` in `.gitignore` and build locally — CI doesn't need it unless you're testing Rust code paths.

---

## 🤖 Multi-Agent Collaboration

### Agents work best in parallel, not series
The biggest productivity gains came from spawning multiple sub-agents simultaneously on independent tasks. The 6-PR sprint (PRs #15-#20, Evolve roadmap) took ~10 minutes per PR when agents worked in parallel — tasks that would have taken a human developer days.

**When to parallelize:**
- Tasks touch different files (no merge conflicts)
- Each task has a clear, bounded scope
- You can verify each independently

**When NOT to parallelize:**
- Tasks share core infrastructure files (training_manager.gd, main.gd)
- Ordering matters (e.g. API must exist before tests are written)
- Token budget is tight

### Sub-agents time out — plan for it
Background agents time out after ~30 minutes. Design tasks to be completable in that window, or write explicit handoff notes so the next agent (or you) can pick up cleanly. The game replay task had one timeout mid-implementation; Alfred finished the remaining integration.

**Mitigation:** Break tasks into phases. Phase 1 = core data structures + tests. Phase 2 = integration + UI. Each phase should be independently mergeable.

### Different agents have different strengths
From the Evolve roadmap sprint:
- **Claude Opus:** Best for holistic design, multi-file refactoring, writing tests alongside features
- **Codex:** Best for focused implementation tasks, fixing specific bugs, parse errors
- **Alfred (Claude Sonnet):** Best for orchestration, research, debugging root causes, documentation
- **Grok:** Best for project management perspective, task decomposition, coordination

Match the agent to the task type, not just availability.

### config.patch replaces arrays — never patch a subset
This burned us early. If your config has `agents.list = [agent1, agent2, agent3]` and you patch with `agents.list = [agent1]`, you lose agents 2 and 3. Always use `config.apply` with the full config, or edit the JSON directly. Partial patching is only safe for non-array fields.

---

## 🎮 Godot Headless Training

### Import cache must be rebuilt after adding new assets
When a PR adds new assets (images, scenes) that GDScript references via `preload()`, you must run:
```bash
godot --headless --import
```
before any headless training will work. Without this, workers silently fail or crash when encountering unimported assets. The `.godot/imported/` directory is not in git, so every fresh checkout needs this step.

**Add to your setup docs:** `godot --headless --import` is step 0 for any new machine or after adding asset files.

### stdout is buffered in Godot — use files for metrics
`print()` calls in Godot headless mode are buffered and may not flush reliably, especially in long-running training loops. The reliable pattern:
1. Write a `metrics.json` file every generation
2. Have your Python logger poll that file (every 5s is fine)
3. Log from Python to W&B

This also makes training resumable — you can restart a crashed run and the logger picks up where it left off.

### Signal connections need named methods in tests
When writing headless tests, connecting signals with lambdas is unreliable in synchronous test environments. Use named methods on `RefCounted` classes:
```gdscript
# ❌ Unreliable in headless tests
signal.connect(func(): callback_called = true)

# ✅ Reliable
func _on_signal_fired(): callback_called = true
signal.connect(_on_signal_fired)
```

### Title screen can block integration tests
In Evolve, a title screen was blocking the game from starting in integration test scenarios. If you add UI scenes that wait for input before proceeding, add a `--skip-intro` (or `--headless`) path that bypasses them. Test your test scenarios against the actual game startup flow periodically.

### Headless workers need nohup, not just background &
```bash
# ❌ Dies when terminal closes or times out
python3 train.py &

# ✅ Survives terminal close, redirects output
nohup python3 train.py > worker.log 2>&1 &
```
exec background sessions in OpenClaw also time out after ~30 minutes. For overnight runs, always use `nohup` or a proper process manager.

---

## 📊 W&B Sweeps

### Bayesian search finds optima faster than grid search
For Evolve, a Bayesian W&B sweep over 15 runs found hyperparameters (pop=120, hidden=80, elite=20, mut_rate=0.270, mut_str=0.110, crossover=0.704) that achieved fitness 147,672 — higher than anything found by manual tuning. Budget at least 15-20 runs per sweep for meaningful exploration.

### Workers stopping early = missing data
W&B sweep workers will stop after their `count` limit, even if the sweep hasn't explored the full space. Monitor sweep progress and restart workers if needed. The `start_workers.sh` script makes relaunching easy.

### Python scripts need line buffering for real-time logs
```python
import sys
sys.stdout.reconfigure(line_buffering=True)
```
Without this, output only appears in bursts (or at script end). Add this at the top of every training/monitoring script.

### 5-second wait after training completes
When Godot finishes training and exits, give the metrics file a moment to fully flush before your logger reads the final values:
```python
time.sleep(5)  # After process.wait() returns
```

---

## 🧪 Testing

### Tests are your refactoring safety net — invest early
Evolve started with ~137 tests and grew to 560. Every major refactor (training_manager shrink, sensor caching, NSGA-II integration) was only safe because of the test suite. Chess-Evolve started with ~40 tests — the first priority should be expanding coverage before adding features.

**Rule of thumb:** If you can't write a test for it, the design isn't clean enough yet.

### Test count ≠ test quality
560 tests in 1.27 seconds (~440 tests/sec) is fast because they're unit tests with no I/O. Avoid test designs that require file I/O, network, or sleep() calls — they slow the suite and make CI flaky. Mock external dependencies.

### PR gatekeeper scenarios are worth the investment
Evolve's 13 integration scenarios (test_runner.gd) catch regressions that unit tests miss — specifically, the interaction between components. The game replay PR found a title-screen-blocking-game-start bug only because the integration test tried to actually run a game. Write a "smoke test" integration scenario for every new major feature.

---

## ⚡ Performance Optimization

### Profile first, optimize second
Every time we assumed we knew the bottleneck, we were partially wrong. The actual profile for Evolve:
- Sensors: 35% (expected)
- Rendering: 20% (**not** expected to be this high)
- Neural net forward: 15% (expected)
- Enemy AI: 10% (tree walks — easily fixed)
- Scene management: 5%

Rendering being 20% led to the SubViewport resolution reduction (1280×720 → 640×360, 75% fewer pixels) — a fix we'd have missed without measurement.

### Precompute adjacency for NEAT networks
NEAT's topology-evolving networks use connection lists that change structure. The naive forward pass (scan all connections for each node) is O(nodes × all_connections). Precomputing an adjacency list (which connections feed each node) brings this to O(nodes × fan_in) — a 3-5× speedup for typical topologies.

### The 20-arena limit is about physics, not rendering
We expected rendering to be the limiting factor for parallel arenas. It wasn't — physics (move_and_slide, collision detection) scales more steeply. 20 arenas at ~50 FPS is the sweet spot; beyond 25, physics becomes the bottleneck. Headless mode gets you another 5-10 arenas by eliminating rendering.

### Network size has a linear cost — benchmark upfront
Chess-Evolve benchmarked neural network sizes before committing to an architecture:
- 32 hidden: 1,569 forwards/sec
- 64 hidden: 792 forwards/sec (2× slower, not 4×)

The relationship is roughly linear with parameter count. For Evolve, we never benchmarked this explicitly — we should have. Start small and scale up only when fitness plateaus.

---

## 🏗️ Architecture

### Separate populations, separate files
Co-evolution (player vs enemy, or white vs black chess) works cleanest when each population has its own manager with clear interfaces. Trying to manage both in one class causes entangled state that's hard to test and debug.

### Metrics polling beats stdout for training loops
Whether training is running locally or via an agent, polling a JSON file is more reliable than parsing stdout:
- Survives process restarts
- No buffering issues
- Multiple readers (logger + UI) can consume it independently
- Easy to add fields without breaking consumers

### Keep the fitness function simple at first
Both projects started with complex, multi-factor fitness functions. The simpler the fitness signal, the faster evolution converges to useful behavior. Add complexity only when the population is stuck — not as a starting point.

---

## 🔧 Dev Process

### Test-first actually saves time
On the replay feature: writing `test_game_recorder.gd` before implementing the recorder clarified the API, found two design issues early, and made the final integration trivial. The tests also served as documentation.

### Small, reviewable PRs are worth the overhead
Each PR in the roadmap sprint was focused on one concern:
- PR #15: Documentation only
- PR #16: Refactoring only (no behavior change)
- PR #17: Performance only
- PR #18: Enemy AI
- PR #19: Co-evolution
- PR #20: Game polish

This made each PR fast to review, easy to revert if needed, and safe to parallelize across agents.

### Commit working states frequently
Several agent runs ended with uncommitted work. Partial implementations sitting in the working tree are hard for the next agent to pick up safely. Establish a rule: if a sub-agent session ends, it commits whatever is working (even if incomplete) with a clear WIP message.

### Document the "why", not just the "what"
The architecture_comparison.md and this file exist because we kept making the same decisions and forgetting the reasoning. When you make a non-obvious choice (e.g., "why polling instead of stdout?"), write a one-liner explaining it. Future-you (or a new agent) will thank you.

---

## 🎯 What We'd Do Differently

1. **Start with headless training** — Evolve's visual arena system is beautiful but added complexity early. Chess-Evolve going headless-first was the right call.
2. **Benchmark network sizes before picking an architecture** — Would have saved tuning time in Evolve.
3. **Write integration tests alongside the first feature** — Evolve's PR gatekeeper scenarios came late; they should be foundational.
4. **Plan for agent timeouts** — Design sub-agent tasks to be completable in 25 minutes, not 45.
5. **Use Rust GDExtension from the start for neural networks** — The 73× speedup was available all along; we just didn't try it until late.

---

## 📚 References

- [`architecture_comparison.md`](./architecture_comparison.md) — Side-by-side technical comparison
- [`performance_bottleneck_analysis.md`](./performance_bottleneck_analysis.md) — Profiling data and optimizations
- [`parallel_arena_analysis.md`](./parallel_arena_analysis.md) — Arena scaling limits
- [`rust-performance-investigation.md`](./rust-performance-investigation.md) — Rust integration investigation
- Evolve W&B project: `aryavolkan-personal/evolve-neuroevolution`

---

*Last updated: 2026-02-17 by Alfred*
