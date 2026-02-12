---
name: review-pr
description: Run the multi-phase PR validation pipeline (unit tests, gameplay integration, training smoke test) and optionally auto-merge. Use when user wants to test a PR, validate changes before merging, or run the full gatekeeper pipeline.
disable-model-invocation: true
---

# PR Review & Validation

Run the multi-phase test pipeline against a PR branch and optionally auto-merge on success.

## Current State
- Branch: !`cd /home/mint/Projects/evolve && git branch --show-current`
- Open PRs: !`gh pr list --repo aryavolkan/evolve --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || echo "none"`

## Instructions

Parse the user's arguments to determine the mode. Supported forms:

- `/review-pr` — Review the current branch's open PR
- `/review-pr 42` — Review PR #42
- `/review-pr --dry-run` — Run tests without merging
- `/review-pr --merge` — Auto-merge if all phases pass
- `/review-pr --skip-gameplay` — Unit tests only (faster)

### Phase 1: Identify the PR

1. If a PR number is given, use it directly.
2. Otherwise, detect the PR for the current branch:
   ```bash
   gh pr view --json number,title,headRefName,state
   ```
3. If no PR is found, tell the user and offer to run tests anyway (without merge).

### Phase 2: Run Unit Tests

```bash
godot --headless --path /home/mint/Projects/evolve --script test/test_runner.gd 2>&1
```

- Check output for `Tests failed: 0` to determine pass/fail.
- Report total tests run and any failures.

### Phase 3: Run Gameplay Integration Tests

```bash
timeout 120 godot --headless --path /home/mint/Projects/evolve --script test/integration/gameplay_test_runner.gd 2>&1
```

- Check output for `GAMEPLAY TEST RESULTS` section.
- Report pass/fail counts and list any failed scenarios.
- Note: `enemy_spawning` and `ai_controller_gameplay` are known flaky tests (timing-dependent, ~4-5s threshold). Flag these as pre-existing if they fail.

### Phase 4: Training Smoke Test

```bash
timeout 30 godot --headless --path /home/mint/Projects/evolve -- --auto-train 2>&1
```

- Success = process starts, loads resources, and begins training without crashes or script errors.
- Check output for `SCRIPT ERROR`, `Failed to load`, or crash indicators.
- The process will be killed by timeout (expected — training runs indefinitely).

### Phase 5: Report Results

Present a summary table:

```
Phase               | Result
--------------------|--------
Unit Tests          | PASS (N/N)
Gameplay Tests      | PASS (N/M) [note any known flaky]
Training Smoke Test | PASS
```

### Phase 6: Merge Decision

- If `--merge` flag or user asked to merge:
  - If all phases passed (gameplay flaky failures are acceptable), merge with:
    ```bash
    gh pr merge <PR_NUMBER> --merge
    ```
  - Then checkout main and pull:
    ```bash
    git checkout main && git pull
    ```
- If `--dry-run` or no merge requested: report results only.
- If any non-flaky test failed: do NOT merge, report failures.

### Alternative: Full Gatekeeper Script

For the complete automated pipeline (with PR comments and rollback support), the user can run:

```bash
./scripts/pr_gatekeeper.sh --pr <NUMBER>
./scripts/pr_gatekeeper.sh --pr <NUMBER> --dry-run
```

This script handles checkout, testing, commenting on the PR, auto-merge, and post-merge verification. Prefer the manual phases above for interactive use within Claude Code.
