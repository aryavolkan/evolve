#!/usr/bin/env python3
"""Compare two gameplay test reports for regression detection.

Usage: python compare_reports.py baseline.json current.json [--strict]
Exit 0 = no regressions, Exit 1 = regressions detected, Exit 2 = usage error.

Thresholds (percentage change that triggers a regression flag):
  Gameplay metrics (score, kills, survival_time): >10% drop
  Performance metrics (frame time, memory): >30% increase
  Pass/fail: any previously-passing scenario that now fails
"""
import json
import sys

# Percentage thresholds: negative = drop is bad, positive = increase is bad
GAMEPLAY_THRESHOLDS = {
    "score": -10.0,
    "kills": -10.0,
    "survival_time": -10.0,
    "powerups_collected": -20.0,
    "score_from_kills": -10.0,
    "score_from_powerups": -10.0,
}

PERFORMANCE_THRESHOLDS = {
    "avg_frame_ms": 30.0,     # >30% slower = regression
    "max_frame_ms": 50.0,     # >50% worse spikes = regression
    "peak_memory_mb": 30.0,   # >30% more memory = regression
}


def load_report(path):
    with open(path) as f:
        return json.load(f)


def compare(baseline, current, strict=False):
    regressions = []
    improvements = []
    warnings = []

    # Summary-level checks
    bs, cs = baseline.get("summary", {}), current.get("summary", {})
    if cs.get("failed", 0) > bs.get("failed", 0):
        regressions.append(
            f"More failures: {bs.get('failed', 0)} → {cs.get('failed', 0)}"
        )

    # Build scenario maps
    b_scenarios = {s["name"]: s for s in baseline.get("scenarios", [])}
    c_scenarios = {s["name"]: s for s in current.get("scenarios", [])}

    # Check for missing scenarios
    for name in b_scenarios:
        if name not in c_scenarios:
            regressions.append(f"{name}: MISSING from current report")

    # Compare each scenario
    for name, curr in c_scenarios.items():
        base = b_scenarios.get(name)
        if not base:
            warnings.append(f"{name}: NEW scenario (no baseline)")
            continue

        # Pass/fail regression
        if base.get("passed") and not curr.get("passed"):
            regressions.append(f"{name}: PASS → FAIL")
            for e in curr.get("errors", []):
                regressions.append(f"  → {e}")
            continue  # Don't check metrics for failing scenarios

        # Gameplay metric regressions
        bg = base.get("gameplay", {})
        cg = curr.get("gameplay", {})
        for metric, threshold in GAMEPLAY_THRESHOLDS.items():
            bv = bg.get(metric, 0)
            cv = cg.get(metric, 0)
            if bv > 0:
                pct = ((cv - bv) / bv) * 100
                if pct < threshold:
                    regressions.append(
                        f"{name}/{metric}: {bv:.0f} → {cv:.0f} ({pct:+.1f}%, threshold: {threshold}%)"
                    )
                elif pct > abs(threshold) * 2:
                    improvements.append(
                        f"{name}/{metric}: {bv:.0f} → {cv:.0f} ({pct:+.1f}%)"
                    )

        # Performance metric regressions
        bp = base.get("performance", {})
        cp = curr.get("performance", {})
        for metric, threshold in PERFORMANCE_THRESHOLDS.items():
            bv = bp.get(metric, 0)
            cv = cp.get(metric, 0)
            if bv > 0:
                pct = ((cv - bv) / bv) * 100
                if pct > threshold:
                    regressions.append(
                        f"{name}/{metric}: {bv:.1f} → {cv:.1f} ({pct:+.1f}%, threshold: +{threshold}%)"
                    )

    # Print results
    print("=" * 50)
    print("  REGRESSION COMPARISON REPORT")
    print("=" * 50)
    print(f"Baseline: {bs.get('passed', '?')}/{bs.get('total', '?')} passed")
    print(f"Current:  {cs.get('passed', '?')}/{cs.get('total', '?')} passed")
    print()

    if regressions:
        print("⚠️  REGRESSIONS DETECTED:")
        for r in regressions:
            print(f"  {r}")
        print()

    if warnings:
        print("ℹ️  Warnings:")
        for w in warnings:
            print(f"  {w}")
        print()

    if improvements:
        print("🎉 Improvements:")
        for i in improvements:
            print(f"  {i}")
        print()

    if not regressions:
        print("✅ No regressions detected")

    has_regressions = len(regressions) > 0
    if strict and warnings:
        has_regressions = True

    return has_regressions


def main():
    strict = "--strict" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    if len(args) != 2:
        print(f"Usage: {sys.argv[0]} <baseline.json> <current.json> [--strict]")
        sys.exit(2)

    baseline = load_report(args[0])
    current = load_report(args[1])
    has_regressions = compare(baseline, current, strict=strict)
    sys.exit(1 if has_regressions else 0)


if __name__ == "__main__":
    main()
