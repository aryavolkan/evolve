#!/usr/bin/env python3
"""
PR Validation System for Evolve.

Runs a multi-phase validation pipeline:
  Phase 0: Merge conflict detection & auto-resolution
  Phase 1: Unit tests (137+ tests via test_runner.gd)
  Phase 2: Gameplay integration tests (8 scenarios via gameplay_test_runner.gd)
  Phase 3: Training mode smoke test (AI training loop for N generations)
  Phase 4: Regression comparison against baseline (if baseline exists)

Usage:
  python scripts/pr_validator.py [--quick] [--baseline=path] [--godot=godot]
                                 [--merge-target=main] [--no-merge]

Exit codes:
  0 = all phases passed
  1 = test failure
  2 = regression detected
  3 = infrastructure error
  4 = unresolvable merge conflicts
"""
import argparse
import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
REPORTS_DIR = PROJECT_DIR / "test" / "integration" / "reports"
COMPARE_SCRIPT = PROJECT_DIR / "test" / "integration" / "compare_reports.py"

# Godot user data dir (OS-dependent)
if platform.system() == "Darwin":
    GODOT_USER_DIR = Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / "Evolve"
elif platform.system() == "Windows":
    GODOT_USER_DIR = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / "Evolve"
else:
    GODOT_USER_DIR = Path.home() / ".local" / "share" / "godot" / "app_userdata" / "Evolve"


def header(text: str) -> None:
    print(f"\n{'='*50}")
    print(f"  {text}")
    print(f"{'='*50}")


def run_cmd(cmd: list[str], timeout: int = 120, label: str = "") -> tuple[int, str]:
    """Run a command, capture output, return (exit_code, output)."""
    print(f"  Running: {' '.join(cmd)}")
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout,
            cwd=str(PROJECT_DIR),
        )
        output = result.stdout + result.stderr
        if result.returncode != 0:
            print(f"  [{label}] Exit code: {result.returncode}")
            if output.strip():
                # Show last 40 lines on failure
                lines = output.strip().split("\n")
                for line in lines[-40:]:
                    print(f"    {line}")
        return result.returncode, output
    except subprocess.TimeoutExpired:
        print(f"  [{label}] TIMEOUT after {timeout}s")
        return 124, f"Timeout after {timeout}s"
    except FileNotFoundError:
        print(f"  [{label}] Command not found: {cmd[0]}")
        return 127, f"Command not found: {cmd[0]}"


## ---------------------------------------------------------------------------
## Phase 0: Merge Conflict Detection & Auto-Resolution
## ---------------------------------------------------------------------------

@dataclass
class ConflictBlock:
    """A single conflict region within a file."""
    file_path: str
    ours: list[str]          # lines from current (PR) branch
    theirs: list[str]        # lines from target (main) branch
    context_before: str = ""  # a few lines before the conflict for context
    auto_resolved: bool = False
    resolution: list[str] = field(default_factory=list)


@dataclass
class MergeReport:
    """Summary of a merge attempt."""
    clean: bool = True
    auto_resolved_files: list[str] = field(default_factory=list)
    manual_conflicts: list[ConflictBlock] = field(default_factory=list)
    error: str | None = None


def _git(args: list[str], check: bool = False, **kwargs) -> subprocess.CompletedProcess:
    """Run a git command in PROJECT_DIR."""
    return subprocess.run(
        ["git"] + args,
        cwd=str(PROJECT_DIR),
        capture_output=True,
        text=True,
        check=check,
        **kwargs,
    )


def _current_branch() -> str:
    r = _git(["branch", "--show-current"])
    return r.stdout.strip()


def _parse_conflict_blocks(file_path: Path) -> list[ConflictBlock]:
    """Parse conflict markers in a file and return ConflictBlock list."""
    text = file_path.read_text()
    blocks: list[ConflictBlock] = []
    lines = text.split("\n")

    ours: list[str] = []
    theirs: list[str] = []
    in_ours = False
    in_theirs = False
    context_before = ""

    for i, line in enumerate(lines):
        if line.startswith("<<<<<<< "):
            in_ours = True
            ours = []
            # grab up to 3 lines of context before the marker
            start = max(0, i - 3)
            context_before = "\n".join(lines[start:i])
            continue
        if line.startswith("=======") and in_ours:
            in_ours = False
            in_theirs = True
            theirs = []
            continue
        if line.startswith(">>>>>>> ") and in_theirs:
            in_theirs = False
            blocks.append(ConflictBlock(
                file_path=str(file_path.relative_to(PROJECT_DIR)),
                ours=ours[:],
                theirs=theirs[:],
                context_before=context_before,
            ))
            continue
        if in_ours:
            ours.append(line)
        elif in_theirs:
            theirs.append(line)

    return blocks


def _is_import_block(lines: list[str]) -> bool:
    """Check if all non-empty lines look like imports/preloads (GDScript or Python)."""
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if not (stripped.startswith("import ")
                or stripped.startswith("from ")
                or stripped.startswith("var ")
                or stripped.startswith("const ")
                or stripped.startswith("preload(")
                or stripped.startswith("@onready")
                or stripped.startswith("#")):
            return False
    return True


def _lines_overlap(ours: list[str], theirs: list[str]) -> bool:
    """Check if both sides modify the same content (true overlap)."""
    # If either side is empty, it's an add-vs-modify — usually auto-resolvable
    if not ours or not theirs:
        return False
    # If content is identical, trivially resolvable
    if ours == theirs:
        return False
    # Check if they touch completely different content (no common non-empty lines in originals)
    ours_set = {l.strip() for l in ours if l.strip()}
    theirs_set = {l.strip() for l in theirs if l.strip()}
    # If there's meaningful overlap in the actual text, it's a real conflict
    if ours_set & theirs_set:
        return False  # same lines = likely context-only conflict, take either
    return True


def _try_auto_resolve(block: ConflictBlock) -> bool:
    """
    Attempt to auto-resolve a conflict block. Returns True if resolved.
    Sets block.resolution and block.auto_resolved.

    Auto-resolvable cases:
    1. Identical changes on both sides → take either
    2. One side is empty (pure addition) → take both
    3. Both sides are import/declaration blocks → merge & dedupe
    4. Non-overlapping additions (one side adds, other modifies different content)
    """
    ours, theirs = block.ours, block.theirs

    # Case 1: identical
    if ours == theirs:
        block.resolution = ours
        block.auto_resolved = True
        return True

    # Case 2: one side empty (deleted vs added) — keep the addition
    if not [l for l in ours if l.strip()] and theirs:
        block.resolution = theirs
        block.auto_resolved = True
        return True
    if not [l for l in theirs if l.strip()] and ours:
        block.resolution = ours
        block.auto_resolved = True
        return True

    # Case 3: both are import/declaration blocks — merge and dedupe
    if _is_import_block(ours) and _is_import_block(theirs):
        seen: set[str] = set()
        merged: list[str] = []
        for line in ours + theirs:
            key = line.strip()
            if key in seen:
                continue
            seen.add(key)
            merged.append(line)
        block.resolution = merged
        block.auto_resolved = True
        return True

    # Not auto-resolvable
    return False


def _apply_resolutions(file_path: Path, blocks: list[ConflictBlock]) -> bool:
    """
    Rewrite a conflicted file, substituting resolved blocks and leaving
    unresolved blocks as conflict markers.
    Returns True if ALL blocks were resolved.
    """
    text = file_path.read_text()
    lines = text.split("\n")
    result: list[str] = []
    block_idx = 0
    skip_until_end = False
    in_ours = False
    in_theirs = False

    for line in lines:
        if line.startswith("<<<<<<< ") and block_idx < len(blocks):
            blk = blocks[block_idx]
            if blk.auto_resolved:
                # Replace entire conflict region with resolution
                skip_until_end = True
                in_ours = True
                continue
            else:
                result.append(line)
                continue
        if line.startswith("=======") and (skip_until_end or in_ours):
            if skip_until_end:
                in_ours = False
                in_theirs = True
                continue
            result.append(line)
            continue
        if line.startswith(">>>>>>> ") and (skip_until_end or in_theirs):
            if skip_until_end:
                blk = blocks[block_idx]
                result.extend(blk.resolution)
                skip_until_end = False
                in_ours = False
                in_theirs = False
                block_idx += 1
                continue
            result.append(line)
            block_idx += 1
            in_theirs = False
            continue
        if skip_until_end:
            continue
        result.append(line)

    file_path.write_text("\n".join(result))
    return all(b.auto_resolved for b in blocks)


def phase_merge_conflicts(target_branch: str = "main") -> MergeReport:
    """
    Phase 0: Attempt to merge target_branch into current PR branch.
    Auto-resolve simple conflicts, report complex ones.
    """
    header("Phase 0: Merge Conflict Check")
    report = MergeReport()
    pr_branch = _current_branch()
    print(f"  PR branch:     {pr_branch}")
    print(f"  Target branch: {target_branch}")

    if not pr_branch:
        report.clean = False
        report.error = "Not on any branch (detached HEAD?)"
        print(f"  ✗ {report.error}")
        return report

    # Fetch latest target
    print(f"  Fetching latest {target_branch}...")
    fetch_result = _git(["fetch", "origin", target_branch])
    if fetch_result.returncode != 0:
        # Try without origin (local-only repo)
        print(f"  ⚠ Remote fetch failed, using local {target_branch}")

    # Attempt the merge (no-commit so we can inspect)
    print(f"  Attempting merge with {target_branch}...")
    merge_result = _git(["merge", f"origin/{target_branch}", "--no-commit", "--no-ff"])

    if merge_result.returncode == 0:
        # Clean merge — no conflicts
        print("  ✓ Clean merge — no conflicts")
        # Commit the merge
        _git(["commit", "-m", f"Merge {target_branch} into {pr_branch} (auto, clean)"])
        return report

    # Check if it's a merge conflict or some other error
    if "CONFLICT" not in merge_result.stdout and "CONFLICT" not in merge_result.stderr:
        # Try local branch name (no origin/ prefix)
        merge_result = _git(["merge", target_branch, "--no-commit", "--no-ff"])
        if merge_result.returncode == 0:
            print("  ✓ Clean merge — no conflicts")
            _git(["commit", "-m", f"Merge {target_branch} into {pr_branch} (auto, clean)"])
            return report
        if "CONFLICT" not in merge_result.stdout and "CONFLICT" not in merge_result.stderr:
            _git(["merge", "--abort"])
            report.clean = False
            report.error = f"Merge failed (not a conflict): {merge_result.stderr.strip()}"
            print(f"  ✗ {report.error}")
            return report

    # We have conflicts — identify conflicted files
    merge_output = merge_result.stdout + merge_result.stderr
    print("  ⚠ Merge conflicts detected")

    # Get list of conflicted files
    diff_result = _git(["diff", "--name-only", "--diff-filter=U"])
    conflicted_files = [f.strip() for f in diff_result.stdout.strip().split("\n") if f.strip()]
    print(f"  Conflicted files ({len(conflicted_files)}):")
    for f in conflicted_files:
        print(f"    - {f}")

    report.clean = False
    all_resolved = True

    for fpath_str in conflicted_files:
        fpath = PROJECT_DIR / fpath_str
        if not fpath.exists():
            report.manual_conflicts.append(ConflictBlock(
                file_path=fpath_str, ours=[], theirs=[],
                context_before="File not found after merge attempt",
            ))
            all_resolved = False
            continue

        blocks = _parse_conflict_blocks(fpath)
        if not blocks:
            # Git says conflict but no markers found — might be binary or deleted
            report.manual_conflicts.append(ConflictBlock(
                file_path=fpath_str, ours=[], theirs=[],
                context_before="No conflict markers found (binary or delete conflict?)",
            ))
            all_resolved = False
            continue

        # Try auto-resolving each block
        for block in blocks:
            _try_auto_resolve(block)

        file_fully_resolved = _apply_resolutions(fpath, blocks)

        if file_fully_resolved:
            report.auto_resolved_files.append(fpath_str)
            _git(["add", fpath_str])
            print(f"    ✓ Auto-resolved: {fpath_str}")
        else:
            unresolved = [b for b in blocks if not b.auto_resolved]
            report.manual_conflicts.extend(unresolved)
            all_resolved = False
            print(f"    ✗ Manual resolution needed: {fpath_str} ({len(unresolved)} conflict(s))")

    if all_resolved:
        report.clean = True
        _git(["commit", "-m",
              f"Merge {target_branch} into {pr_branch} (auto-resolved conflicts)\n\n"
              f"Auto-resolved files:\n" +
              "\n".join(f"  - {f}" for f in report.auto_resolved_files)])
        print("\n  ✓ All conflicts auto-resolved and committed")
    else:
        # Abort the merge so we don't leave dirty state
        _git(["merge", "--abort"])
        print(f"\n  ✗ {len(report.manual_conflicts)} conflict(s) require manual resolution")

    return report


def generate_conflict_report(report: MergeReport) -> str:
    """Generate a human-readable conflict report for PR comments."""
    lines = ["## 🔀 Merge Conflict Report\n"]

    if report.auto_resolved_files:
        lines.append(f"### ✅ Auto-Resolved ({len(report.auto_resolved_files)} files)")
        for f in report.auto_resolved_files:
            lines.append(f"- `{f}`")
        lines.append("")

    if report.manual_conflicts:
        lines.append(f"### ❌ Manual Resolution Required ({len(report.manual_conflicts)} conflicts)")
        lines.append("")
        for i, block in enumerate(report.manual_conflicts, 1):
            lines.append(f"**{i}. `{block.file_path}`**")
            if block.context_before:
                lines.append(f"Context: `...{block.context_before[-80:]}`")
            lines.append("```")
            lines.append("<<<<<<< PR branch (yours)")
            lines.extend(block.ours[:10])
            if len(block.ours) > 10:
                lines.append(f"  ... ({len(block.ours) - 10} more lines)")
            lines.append("=======")
            lines.extend(block.theirs[:10])
            if len(block.theirs) > 10:
                lines.append(f"  ... ({len(block.theirs) - 10} more lines)")
            lines.append(">>>>>>> target branch (theirs)")
            lines.append("```")
            lines.append("")

    if report.error:
        lines.append(f"### ⚠️ Error\n{report.error}\n")

    return "\n".join(lines)


def find_godot(godot_arg: str | None) -> str:
    if godot_arg:
        return godot_arg
    for name in ["godot", "godot4"]:
        if shutil.which(name):
            return name
    print("ERROR: godot not found in PATH. Use --godot=<path>")
    sys.exit(3)


def phase_unit_tests(godot: str) -> bool:
    header("Phase 1: Unit Tests")
    code, output = run_cmd(
        [godot, "--headless", "--path", str(PROJECT_DIR), "--script", "test/test_runner.gd"],
        timeout=60, label="unit-tests",
    )
    if code == 0:
        print("  ✓ Unit tests passed")
        return True
    else:
        print("  ✗ Unit tests FAILED")
        return False


def phase_gameplay_tests(godot: str, quick: bool = False) -> bool:
    header("Phase 2: Gameplay Integration Tests")
    scenario = "boot_and_run" if quick else "all"
    code, output = run_cmd(
        [godot, "--headless", "--path", str(PROJECT_DIR),
         "--script", "test/integration/gameplay_test_runner.gd",
         "--", f"--scenario={scenario}"],
        timeout=180, label="gameplay-tests",
    )
    # Print relevant output
    for line in output.split("\n"):
        if any(k in line for k in ["PASS", "FAIL", "Result", "GAMEPLAY TEST"]):
            print(f"    {line.strip()}")

    if code == 0:
        print("  ✓ Gameplay tests passed")
        return True
    else:
        print("  ✗ Gameplay tests FAILED")
        return False


def phase_training_smoke(godot: str) -> bool:
    header("Phase 3: Training Mode Smoke Test")
    # Run the game in headless auto-train mode briefly to verify training loop works
    # We use a short timeout — training should start and produce at least 1 generation
    code, output = run_cmd(
        [godot, "--headless", "--path", str(PROJECT_DIR),
         "--script", "test/integration/training_smoke_test.gd"],
        timeout=120, label="training-smoke",
    )
    for line in output.split("\n"):
        if any(k in line for k in ["PASS", "FAIL", "Gen", "ERROR", "Training"]):
            print(f"    {line.strip()}")

    if code == 0:
        print("  ✓ Training smoke test passed")
        return True
    else:
        print("  ✗ Training smoke test FAILED")
        return False


def phase_regression_check(baseline_path: str | None) -> bool:
    header("Phase 4: Regression Check")

    report_path = GODOT_USER_DIR / "gameplay_test_report.json"
    if not report_path.exists():
        print("  ⚠ No gameplay report found, skipping regression check")
        return True

    # Save report with timestamp
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    try:
        branch = subprocess.check_output(
            ["git", "branch", "--show-current"], cwd=str(PROJECT_DIR), text=True
        ).strip().replace("/", "_")
    except Exception:
        branch = "unknown"
    dest = REPORTS_DIR / f"report_{branch}_{timestamp}.json"
    shutil.copy2(report_path, dest)
    print(f"  Report saved: {dest.name}")

    # Find baseline
    if baseline_path:
        baseline = Path(baseline_path)
    else:
        baseline = REPORTS_DIR / "baseline.json"

    if not baseline.exists():
        print("  ⚠ No baseline found, saving current as baseline")
        shutil.copy2(dest, REPORTS_DIR / "baseline.json")
        return True

    # Compare
    code, output = run_cmd(
        [sys.executable, str(COMPARE_SCRIPT), str(baseline), str(dest)],
        timeout=10, label="regression-check",
    )
    for line in output.split("\n"):
        if line.strip():
            print(f"    {line}")

    if code == 0:
        print("  ✓ No regressions detected")
        return True
    else:
        print("  ⚠ REGRESSIONS DETECTED")
        return False


def main():
    parser = argparse.ArgumentParser(description="Evolve PR Validator")
    parser.add_argument("--quick", action="store_true", help="Run minimal checks only")
    parser.add_argument("--baseline", type=str, help="Baseline report for regression comparison")
    parser.add_argument("--godot", type=str, help="Path to Godot binary")
    parser.add_argument("--skip-training", action="store_true", help="Skip training smoke test")
    parser.add_argument("--merge-target", type=str, default="main",
                        help="Target branch to merge from (default: main)")
    parser.add_argument("--no-merge", action="store_true",
                        help="Skip merge conflict check")
    args = parser.parse_args()

    godot = find_godot(args.godot)

    print("╔══════════════════════════════════════╗")
    print("║     Evolve PR Validator              ║")
    print("╚══════════════════════════════════════╝")
    print(f"  Project:  {PROJECT_DIR}")
    print(f"  Godot:    {godot}")
    print(f"  Mode:     {'quick' if args.quick else 'full'}")

    results = {}
    start = time.time()

    # Phase 0: Merge conflict check
    if not args.no_merge:
        merge_report = phase_merge_conflicts(args.merge_target)
        if merge_report.manual_conflicts:
            report_text = generate_conflict_report(merge_report)
            # Save conflict report to disk
            conflict_report_path = PROJECT_DIR / "conflict_report.md"
            conflict_report_path.write_text(report_text)
            print(f"\n  Conflict report saved to: {conflict_report_path}")
            print(report_text)
            print("\n❌ BLOCKED: Unresolvable merge conflicts. See report above.")
            sys.exit(4)
        if merge_report.error:
            print(f"\n❌ BLOCKED: Merge error — {merge_report.error}")
            sys.exit(3)
        results["merge_conflicts"] = merge_report.clean or bool(merge_report.auto_resolved_files)
    else:
        results["merge_conflicts"] = None
        print("\n  ⏭ Merge conflict check skipped")

    # Phase 1: Unit tests (always run)
    results["unit_tests"] = phase_unit_tests(godot)
    if not results["unit_tests"]:
        print("\n❌ BLOCKED: Unit tests failed. Fix before merging.")
        sys.exit(1)

    # Phase 2: Gameplay tests
    results["gameplay_tests"] = phase_gameplay_tests(godot, quick=args.quick)
    if not results["gameplay_tests"]:
        print("\n❌ BLOCKED: Gameplay tests failed. Gameplay regression detected.")
        sys.exit(1)

    # Phase 3: Training smoke test
    if not args.quick and not args.skip_training:
        results["training_smoke"] = phase_training_smoke(godot)
        if not results["training_smoke"]:
            print("\n❌ BLOCKED: Training mode broken. AI training pipeline regression.")
            sys.exit(1)
    else:
        results["training_smoke"] = None
        print("\n  ⏭ Training smoke test skipped")

    # Phase 4: Regression comparison
    if not args.quick:
        results["regression_check"] = phase_regression_check(args.baseline)
        if not results["regression_check"]:
            print("\n⚠️  WARNING: Regressions detected. Review before merging.")
            # Regression is a warning, not a blocker (exit 2)
            elapsed = time.time() - start
            print(f"\nCompleted in {elapsed:.1f}s")
            sys.exit(2)
    else:
        results["regression_check"] = None

    elapsed = time.time() - start
    header("SUMMARY")
    for phase, passed in results.items():
        if passed is None:
            icon = "⏭"
        elif passed:
            icon = "✓"
        else:
            icon = "✗"
        print(f"  {icon} {phase}")
    print(f"\n  Completed in {elapsed:.1f}s")
    print("\n✅ PR APPROVED — all checks passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
