#!/usr/bin/env python3
"""Compare two gameplay test reports for regression detection."""
import json, sys

THRESHOLDS = {
    "score": -20.0, "kills": -30.0, "survival_time": -20.0,
    "avg_frame_ms": 50.0, "max_frame_ms": 100.0, "peak_memory_mb": 30.0,
}

def compare(baseline, current):
    regressions, improvements = [], []
    base_s = {s["name"]: s for s in baseline.get("scenarios", [])}
    curr_s = {s["name"]: s for s in current.get("scenarios", [])}

    for name, curr in curr_s.items():
        base = base_s.get(name)
        if not base:
            print(f"  NEW: {name}"); continue
        if base.get("passed") and not curr.get("passed"):
            regressions.append(f"{name}: PASS → FAIL")
            for e in curr.get("errors", []): regressions.append(f"  → {e}")
        for metric in ["score", "kills", "survival_time"]:
            bv = base.get("gameplay", {}).get(metric, 0)
            cv = curr.get("gameplay", {}).get(metric, 0)
            if bv > 0:
                pct = ((cv - bv) / bv) * 100
                if pct < THRESHOLDS.get(metric, -20):
                    regressions.append(f"{name}/{metric}: {bv:.0f}→{cv:.0f} ({pct:+.1f}%)")
                elif pct > abs(THRESHOLDS.get(metric, 20)):
                    improvements.append(f"{name}/{metric}: {bv:.0f}→{cv:.0f} ({pct:+.1f}%)")
        for metric in ["avg_frame_ms", "max_frame_ms", "peak_memory_mb"]:
            bv = base.get("performance", {}).get(metric, 0)
            cv = curr.get("performance", {}).get(metric, 0)
            if bv > 0:
                pct = ((cv - bv) / bv) * 100
                if pct > THRESHOLDS.get(metric, 50):
                    regressions.append(f"{name}/{metric}: {bv:.1f}→{cv:.1f} ({pct:+.1f}%)")
    for name in base_s:
        if name not in curr_s: regressions.append(f"{name}: MISSING")

    if regressions:
        print("⚠️  REGRESSIONS:"); [print(f"  {r}") for r in regressions]
    else:
        print("✓ No regressions")
    if improvements:
        print("🎉 Improvements:"); [print(f"  {i}") for i in improvements]
    print(f"\nBaseline: {baseline['summary']['passed']}/{baseline['summary']['total']}")
    print(f"Current:  {current['summary']['passed']}/{current['summary']['total']}")
    return len(regressions) > 0

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <baseline.json> <current.json>"); sys.exit(1)
    with open(sys.argv[1]) as f: baseline = json.load(f)
    with open(sys.argv[2]) as f: current = json.load(f)
    sys.exit(1 if compare(baseline, current) else 0)
