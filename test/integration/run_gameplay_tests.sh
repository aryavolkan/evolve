#!/usr/bin/env bash
## Run automated gameplay tests for regression detection.
## Usage: ./test/integration/run_gameplay_tests.sh [--compare=<baseline.json>] [--scenario=<name>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
SCENARIO="all"
BASELINE=""
REPORT_DIR="${PROJECT_DIR}/test/integration/reports"

for arg in "$@"; do
    case "$arg" in
        --compare=*) BASELINE="${arg#*=}" ;;
        --scenario=*) SCENARIO="${arg#*=}" ;;
        --help) echo "Usage: $0 [--compare=baseline.json] [--scenario=name]"; exit 0 ;;
    esac
done

mkdir -p "$REPORT_DIR"

echo "╔══════════════════════════════════════╗"
echo "║  Evolve Gameplay Test Runner         ║"
echo "╚══════════════════════════════════════╝"
echo "Project: $PROJECT_DIR"
echo "Branch:  $(cd "$PROJECT_DIR" && git branch --show-current 2>/dev/null || echo 'unknown')"
echo "Commit:  $(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo ""

echo "=== Phase 1: Unit Tests ==="
if "$GODOT_BIN" --headless --path "$PROJECT_DIR" --script test/test_runner.gd 2>&1; then
    echo "Unit tests passed ✓"
else
    echo "Unit tests FAILED ✗"; exit 1
fi

echo ""
echo "=== Phase 2: Gameplay Integration Tests ==="
TIMEOUT=120
if timeout "$TIMEOUT" "$GODOT_BIN" --headless --path "$PROJECT_DIR" \
    --script test/integration/gameplay_test_runner.gd -- --scenario="$SCENARIO" 2>&1; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
    [ "$EXIT_CODE" -eq 124 ] && echo "TIMEOUT: Tests exceeded ${TIMEOUT}s"
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
    echo "Report: $REPORT_DST"
    if [ -n "$BASELINE" ] && [ -f "$BASELINE" ]; then
        echo "=== Regression Comparison ==="
        python3 "$SCRIPT_DIR/compare_reports.py" "$BASELINE" "$REPORT_DST" 2>/dev/null || true
    fi
fi

exit "$EXIT_CODE"
