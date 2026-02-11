#!/usr/bin/env bash
## PR Gatekeeper: Run all tests and gameplay checks for CI/CD.
##
## Usage:
##   ./test/integration/pr_gatekeeper.sh                    # Full test suite
##   ./test/integration/pr_gatekeeper.sh --baseline=report.json  # Compare against baseline
##   ./test/integration/pr_gatekeeper.sh --skip-gameplay    # Unit tests only
##   ./test/integration/pr_gatekeeper.sh --dry-run          # Print what would run
##
## Exit codes: 0 = all passed, 1 = failures, 2 = setup error
##
## GitHub Actions usage:
##   - name: Run PR Gatekeeper
##     run: ./test/integration/pr_gatekeeper.sh --baseline=test/integration/reports/baseline.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
REPORT_DIR="${PROJECT_DIR}/test/integration/reports"
BASELINE=""
SKIP_GAMEPLAY=false
DRY_RUN=false
GAMEPLAY_TIMEOUT=180
SCENARIO="all"

for arg in "$@"; do
    case "$arg" in
        --baseline=*) BASELINE="${arg#*=}" ;;
        --skip-gameplay) SKIP_GAMEPLAY=true ;;
        --dry-run) DRY_RUN=true ;;
        --timeout=*) GAMEPLAY_TIMEOUT="${arg#*=}" ;;
        --scenario=*) SCENARIO="${arg#*=}" ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --baseline=FILE    Compare gameplay report against baseline JSON"
            echo "  --skip-gameplay    Skip gameplay integration tests (unit tests only)"
            echo "  --dry-run          Print what would run without executing"
            echo "  --timeout=SECS     Gameplay test timeout (default: 180)"
            echo "  --scenario=NAME    Run specific gameplay scenario (default: all)"
            echo ""
            echo "Environment:"
            echo "  GODOT_BIN          Path to Godot binary"
            echo "  CI                 Set in CI environments (adjusts output)"
            exit 0 ;;
    esac
done

# Resolve baseline path
if [ -n "$BASELINE" ] && [ ! -f "$BASELINE" ]; then
    # Try relative to project dir
    if [ -f "$PROJECT_DIR/$BASELINE" ]; then
        BASELINE="$PROJECT_DIR/$BASELINE"
    else
        echo "ERROR: Baseline file not found: $BASELINE"
        exit 2
    fi
fi

mkdir -p "$REPORT_DIR"

# Header
echo "╔══════════════════════════════════════════════╗"
echo "║  Evolve PR Gatekeeper                        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Project:  $PROJECT_DIR"
echo "Godot:    $GODOT_BIN"
echo "Branch:   $(cd "$PROJECT_DIR" && git branch --show-current 2>/dev/null || echo 'detached')"
echo "Commit:   $(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo "Baseline: ${BASELINE:-none}"
echo ""

if $DRY_RUN; then
    echo "[DRY RUN] Would run:"
    echo "  1. Unit tests: $GODOT_BIN --headless --path $PROJECT_DIR --script test/test_runner.gd"
    if ! $SKIP_GAMEPLAY; then
        echo "  2. Gameplay tests: $GODOT_BIN --headless --path $PROJECT_DIR --script test/integration/gameplay_test_runner.gd"
        if [ -n "$BASELINE" ]; then
            echo "  3. Regression comparison against $BASELINE"
        fi
    fi
    exit 0
fi

# Check Godot binary
if [ ! -x "$GODOT_BIN" ] && ! command -v "$GODOT_BIN" &>/dev/null; then
    echo "ERROR: Godot binary not found at $GODOT_BIN"
    echo "Set GODOT_BIN environment variable to the correct path."
    exit 2
fi

UNIT_PASSED=false
GAMEPLAY_PASSED=false
REGRESSION_PASSED=false
OVERALL_EXIT=0

# ============================================================
# Phase 1: Unit Tests
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Phase 1: Unit Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

UNIT_OUTPUT=$("$GODOT_BIN" --headless --path "$PROJECT_DIR" --script test/test_runner.gd 2>&1) || {
    echo "$UNIT_OUTPUT"
    echo ""
    echo "❌ Unit tests FAILED"
    OVERALL_EXIT=1
}

if [ "$OVERALL_EXIT" -eq 0 ]; then
    # Extract test counts from output
    UNIT_PASSED=true
    echo "$UNIT_OUTPUT" | tail -15
    echo ""
    echo "✅ Unit tests passed"
fi

# ============================================================
# Phase 2: Gameplay Integration Tests
# ============================================================
if ! $SKIP_GAMEPLAY; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Phase 2: Gameplay Integration Tests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    GAMEPLAY_EXIT=0
    GAMEPLAY_OUTPUT=$(timeout "$GAMEPLAY_TIMEOUT" "$GODOT_BIN" --headless --path "$PROJECT_DIR" \
        --script test/integration/gameplay_test_runner.gd -- --scenario="$SCENARIO" 2>&1) || {
        GAMEPLAY_EXIT=$?
        if [ "$GAMEPLAY_EXIT" -eq 124 ]; then
            echo "⏰ TIMEOUT: Gameplay tests exceeded ${GAMEPLAY_TIMEOUT}s"
        fi
    }

    # Check for script load failures
    if echo "$GAMEPLAY_OUTPUT" | grep -q "Failed to load script\|SCRIPT ERROR"; then
        echo "❌ Gameplay test script failed to load!"
        GAMEPLAY_EXIT=1
    fi

    # Check for results marker
    if ! echo "$GAMEPLAY_OUTPUT" | grep -q "GAMEPLAY TEST RESULTS"; then
        echo "❌ Gameplay tests did not produce results"
        GAMEPLAY_EXIT=1
    fi

    echo "$GAMEPLAY_OUTPUT" | tail -30
    echo ""

    if [ "$GAMEPLAY_EXIT" -eq 0 ]; then
        GAMEPLAY_PASSED=true
        echo "✅ Gameplay tests passed"
    else
        echo "❌ Gameplay tests FAILED"
        OVERALL_EXIT=1
    fi

    # Copy report
    if [ "$(uname)" = "Darwin" ]; then
        GODOT_USER_DIR="${HOME}/Library/Application Support/Godot/app_userdata/Evolve"
    else
        GODOT_USER_DIR="${HOME}/.local/share/godot/app_userdata/Evolve"
    fi
    REPORT_SRC="${GODOT_USER_DIR}/gameplay_test_report.json"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BRANCH=$(cd "$PROJECT_DIR" && git branch --show-current 2>/dev/null | tr '/' '_' || echo 'unknown')
    REPORT_DST="${REPORT_DIR}/report_${BRANCH}_${TIMESTAMP}.json"

    if [ -f "$REPORT_SRC" ]; then
        cp "$REPORT_SRC" "$REPORT_DST"
        echo "Report saved: $REPORT_DST"

        # ============================================================
        # Phase 3: Regression Comparison (optional)
        # ============================================================
        if [ -n "$BASELINE" ] && [ -f "$BASELINE" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  Phase 3: Regression Comparison"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

            if python3 "$SCRIPT_DIR/compare_reports.py" "$BASELINE" "$REPORT_DST"; then
                REGRESSION_PASSED=true
                echo ""
                echo "✅ No regressions detected"
            else
                echo ""
                echo "⚠️  Regressions detected (see above)"
                OVERALL_EXIT=1
            fi
        fi
    fi
else
    echo ""
    echo "(Gameplay tests skipped)"
    GAMEPLAY_PASSED=true
    REGRESSION_PASSED=true
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

_icon() { if $1; then echo "✅"; else echo "❌"; fi; }

echo "  Unit tests:        $(_icon $UNIT_PASSED)"
if ! $SKIP_GAMEPLAY; then
    echo "  Gameplay tests:    $(_icon $GAMEPLAY_PASSED)"
    if [ -n "$BASELINE" ]; then
        echo "  Regression check:  $(_icon $REGRESSION_PASSED)"
    fi
fi
echo ""

if [ "$OVERALL_EXIT" -eq 0 ]; then
    echo "🎉 All checks passed — ready to merge!"
else
    echo "💥 Some checks failed — see details above."
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$OVERALL_EXIT"
