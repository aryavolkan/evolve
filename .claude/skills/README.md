# Claude Code Skills

Available slash commands for the Evolve project.

## `/sweep [OPTIONS]`

Launch, monitor, or join a W&B hyperparameter sweep.

| Command | Description |
|---------|-------------|
| `/sweep` | Launch 8-hour sweep with defaults |
| `/sweep --hours 2` | Quick 2-hour sweep |
| `/sweep --join SWEEP_ID` | Join an existing sweep |
| `/sweep status` | List all sweeps |
| `/sweep status SWEEP_ID` | Detailed status for a specific sweep |

**Skill file:** `.claude/skills/sweep/SKILL.md`

## `/workers`

Check status of W&B sweep worker processes (Python agents and Godot headless training instances).

| Command | Description |
|---------|-------------|
| `/workers` | Show all running workers and their status |

**Skill file:** `.claude/skills/workers/SKILL.md`

## `/review-pr [PR_NUMBER] [OPTIONS]`

Run the multi-phase PR validation pipeline and optionally auto-merge.

| Command | Description |
|---------|-------------|
| `/review-pr` | Review current branch's PR |
| `/review-pr 42` | Review PR #42 |
| `/review-pr --merge` | Auto-merge if all phases pass |
| `/review-pr --dry-run` | Run tests without merging |
| `/review-pr --skip-gameplay` | Unit tests only (faster) |

**Phases:**
1. Unit tests (490+ tests via `test/test_runner.gd`)
2. Gameplay integration (13 scenarios via `test/integration/gameplay_test_runner.gd`)
3. Training smoke test (headless `--auto-train` startup check)

**Skill file:** `.claude/skills/review-pr/SKILL.md`
