---
name: review-pr
description: Review and validate a PR with unit tests, training smoke test, and code review. Use when user wants to test a PR, validate changes before merging, or run the full review pipeline.
disable-model-invocation: true
---

# PR Review & Validation

Multi-phase PR validation pipeline: unit tests → training smoke test → code review → optional merge.

## Current State
- Branch: !`git branch --show-current`
- Open PRs: !`gh pr list --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || echo "none"`

## Instructions

Parse user arguments:
- `/review-pr` — Review current branch's open PR
- `/review-pr 42` — Review PR #42
- `/review-pr --dry-run` — Run tests only, no merge
- `/review-pr --merge` — Auto-merge if all phases pass
- `/review-pr --skip-smoke` — Skip training smoke test (faster)

Default: dry-run (no merge unless `--merge` is passed).

---

### Phase 1: Identify & Checkout PR

1. If a PR number is given, fetch it:
   ```bash
   gh pr checkout <number>
   ```
2. If no number, detect PR for current branch:
   ```bash
   gh pr view --json number,title,headRefName,state,body
   ```
3. If no PR found, tell the user. Offer to run tests on the current branch anyway.
4. Show PR title, description, and changed files:
   ```bash
   gh pr diff --stat
   ```

---

### Phase 2: Unit Tests

Run the Godot test suite headless:

```bash
timeout 120 godot --headless --script test/test_runner.gd 2>&1
```

**Pass criteria:** Exit code 0 and output contains "PASSED" with 0 failures.

If tests fail:
- Show which tests failed and why
- Stop the pipeline (do not continue to Phase 3)
- Suggest fixes if the failure is obvious

---

### Phase 3: Training Smoke Test

Run headless training for 3 generations to verify the training pipeline isn't broken:

```bash
timeout 180 godot --headless --rendering-driver dummy -- --auto-train --worker-id=pr-test 2>&1
```

**Pass criteria:**
- No `SCRIPT ERROR` or `Parse Error` in output
- At least 1 generation completes (look for `Gen 1` in output)
- Check metrics file was written:
  ```bash
  cat ~/.local/share/godot/app_userdata/Evolve/metrics_pr-test.json
  ```
- Verify `avg_fitness > 0`, `avg_kill_score > 0`

If smoke test fails:
- Show the errors
- Stop the pipeline
- Analyze what broke (missing classes, parse errors, runtime crashes)

Clean up after:
```bash
rm -f ~/.local/share/godot/app_userdata/Evolve/metrics_pr-test.json
rm -f ~/.local/share/godot/app_userdata/Evolve/sweep_config_pr-test.json
```

---

### Phase 4: Code Review

Review the PR diff for:

1. **Breaking changes** — Does it modify public APIs, signals, or exported properties?
2. **Test coverage** — Are new features covered by tests? Check `test/` directory.
3. **Training impact** — Could changes affect fitness calculation, evolution, or metrics?
4. **Performance** — Any obvious performance issues (nested loops in _process, heavy allocations per frame)?
5. **Style** — Follows project conventions (type hints, signal-based communication, @export for editor props)?

```bash
gh pr diff
```

Summarize findings as:
- ✅ **Pass** — No issues found
- ⚠️ **Warning** — Minor issues, safe to merge with notes
- ❌ **Fail** — Blocking issues that need fixes

---

### Phase 5: Result & Merge

Print a summary table:

```
╔══════════════════════════════════╗
║       PR #XX Review Results      ║
╠══════════════════════════════════╣
║ Unit Tests:      ✅ PASS (N/N)   ║
║ Smoke Test:      ✅ PASS (Gen 1) ║
║ Code Review:     ⚠️ WARNINGS     ║
╠══════════════════════════════════╣
║ Verdict:         SAFE TO MERGE   ║
╚══════════════════════════════════╝
```

If `--merge` was passed and all phases passed:
```bash
gh pr merge <number> --squash --delete-branch
```

If not merging, suggest:
```
To merge: /review-pr <number> --merge
```

Always return to the original branch after:
```bash
git checkout main
```
