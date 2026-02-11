#!/bin/bash
# PR Gatekeeper - monitors, tests, and auto-merges PRs for Evolve
#
# Usage:
#   ./scripts/pr_gatekeeper.sh              # Check all open PRs once
#   ./scripts/pr_gatekeeper.sh --watch      # Poll every 5 min
#   ./scripts/pr_gatekeeper.sh --pr 42      # Test specific PR
#   ./scripts/pr_gatekeeper.sh --dry-run    # No merge/comment
#
set -euo pipefail

REPO="aryavolkan/evolve"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPORTS_DIR="$PROJECT_DIR/reports/pr-validation"
GODOT="${GODOT:-godot}"
DRY_RUN=false
WATCH=false
SPECIFIC_PR=""
POLL_INTERVAL=300

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --watch)   WATCH=true; shift ;;
        --pr)      SPECIFIC_PR="$2"; shift 2 ;;
        --interval) POLL_INTERVAL="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

mkdir -p "$REPORTS_DIR"

comment_pr() {
    local pr_num="$1" body="$2"
    if $DRY_RUN; then
        echo "[DRY RUN] Would comment on PR #$pr_num"
    else
        gh pr comment "$pr_num" --repo "$REPO" --body "$body"
    fi
}

merge_pr() {
    local pr_num="$1"
    if $DRY_RUN; then
        echo "[DRY RUN] Would merge PR #$pr_num"
    else
        gh pr merge "$pr_num" --repo "$REPO" --merge \
            --subject "Auto-merge PR #$pr_num (all tests passed)"
    fi
}

validate_pr() {
    local pr_num="$1"
    local pr_json
    pr_json=$(gh pr view "$pr_num" --repo "$REPO" --json number,title,headRefName,headRefOid,author)
    local title=$(echo "$pr_json" | jq -r '.title')
    local branch=$(echo "$pr_json" | jq -r '.headRefName')
    local sha=$(echo "$pr_json" | jq -r '.headRefOid')
    local author=$(echo "$pr_json" | jq -r '.author.login')

    echo ""
    echo "============================================================"
    echo "  PR #$pr_num: $title"
    echo "  Branch: $branch | Author: $author | SHA: ${sha:0:8}"
    echo "============================================================"

    # Save current state
    local original_branch
    original_branch=$(cd "$PROJECT_DIR" && git rev-parse --abbrev-ref HEAD)
    local main_sha
    main_sha=$(cd "$PROJECT_DIR" && git rev-parse main)

    # Checkout PR branch
    cd "$PROJECT_DIR"
    git fetch origin "$branch" 2>/dev/null || true
    git stash 2>/dev/null || true
    git checkout "$branch" 2>/dev/null
    git pull origin "$branch" 2>/dev/null || true

    # Run full validation
    local report=""
    local all_passed=true
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local start_time=$(date +%s)

    report+="## 🤖 PR Validator Report\n"
    report+="**PR:** #$pr_num — $title\n"
    report+="**Branch:** \`$branch\` @ \`${sha:0:8}\`\n"
    report+="**Time:** $timestamp\n\n"

    # Phase 1: Unit Tests
    echo "▶ Phase 1: Unit Tests..."
    local unit_output
    unit_output=$("$GODOT" --headless --path "$PROJECT_DIR" --script test/test_runner.gd 2>&1) || true
    local unit_exit=$?
    if echo "$unit_output" | grep -q "Tests failed: *0"; then
        local unit_count=$(echo "$unit_output" | grep "Tests run:" | sed 's/[^0-9]//g')
        report+="### ✅ Unit Tests ($unit_count passed)\n\n"
        echo "  ✓ Unit tests passed ($unit_count tests)"
    else
        all_passed=false
        local failures=$(echo "$unit_output" | grep "FAIL:" | head -10)
        report+="### ❌ Unit Tests FAILED\n\n"
        report+="\`\`\`\n$failures\n\`\`\`\n\n"
        echo "  ✗ Unit tests FAILED"
    fi

    # Phase 2: Gameplay Tests
    echo "▶ Phase 2: Gameplay Tests..."
    local gp_output
    gp_output=$("$GODOT" --headless --path "$PROJECT_DIR" --script test/integration/gameplay_test_runner.gd 2>&1) || true
    if echo "$gp_output" | grep -q "Failed: *0"; then
        local gp_count=$(echo "$gp_output" | grep "Total:" | sed 's/[^0-9]//g')
        report+="### ✅ Gameplay Tests ($gp_count scenarios passed)\n\n"
        echo "  ✓ Gameplay tests passed ($gp_count scenarios)"

        # Include gameplay stats
        local gp_report="$HOME/Library/Application Support/Godot/app_userdata/Evolve/gameplay_test_report.json"
        if [[ -f "$gp_report" ]]; then
            report+="<details><summary>Gameplay Details</summary>\n\n"
            for scenario in $(jq -r '.scenarios[].name' "$gp_report"); do
                local s_passed=$(jq -r ".scenarios[] | select(.name==\"$scenario\") | .passed" "$gp_report")
                local icon="✅"
                [[ "$s_passed" == "false" ]] && icon="❌"
                report+="- $icon $scenario\n"
            done
            report+="\n</details>\n\n"
        fi
    else
        all_passed=false
        local gp_failures=$(echo "$gp_output" | grep -E "FAIL|✗" | head -10)
        report+="### ❌ Gameplay Tests FAILED\n\n"
        report+="\`\`\`\n$gp_failures\n\`\`\`\n\n"
        echo "  ✗ Gameplay tests FAILED"
    fi

    # Phase 3: Training Smoke Test
    echo "▶ Phase 3: Training Smoke Test..."
    local train_output
    train_output=$("$GODOT" --headless --path "$PROJECT_DIR" --script test/integration/training_smoke_test.gd 2>&1) || true
    if echo "$train_output" | grep -q "PASSED"; then
        report+="### ✅ Training Smoke Test\n\n"
        echo "  ✓ Training smoke test passed"
    else
        all_passed=false
        report+="### ❌ Training Smoke Test FAILED\n\n"
        echo "  ✗ Training smoke test FAILED"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    report+="---\n**Duration:** ${duration}s\n\n"

    if $all_passed; then
        report+="🚀 **All tests passed — auto-merging.**"
        echo ""
        echo "✅ All tests passed for PR #$pr_num"
    else
        report+="⛔ **Merge blocked.** Fix failures and push again."
        echo ""
        echo "❌ PR #$pr_num failed validation"
    fi

    # Save report locally
    local report_file="$REPORTS_DIR/pr-${pr_num}-$(date '+%Y%m%d-%H%M%S').md"
    echo -e "$report" > "$report_file"
    echo "Report: $report_file"

    # Comment on PR
    comment_pr "$pr_num" "$(echo -e "$report")"

    # Merge if passed
    if $all_passed; then
        merge_pr "$pr_num"

        # Post-merge verification
        echo "▶ Post-merge verification..."
        git checkout main
        git pull origin main
        local verify_output
        verify_output=$("$GODOT" --headless --path "$PROJECT_DIR" --script test/test_runner.gd 2>&1) || true
        if echo "$verify_output" | grep -q "Tests failed: *0"; then
            echo "  ✓ Main branch verified"
        else
            echo "  ✗ MAIN BROKEN! Rolling back..."
            if ! $DRY_RUN; then
                git reset --hard "$main_sha"
                git push --force-with-lease origin main
                comment_pr "$pr_num" "## ⚠️ ROLLBACK\nMain tests failed post-merge. Reverted to \`${main_sha:0:8}\`."
            fi
        fi
    fi

    # Restore original branch
    cd "$PROJECT_DIR"
    git checkout "$original_branch" 2>/dev/null || true
    git stash pop 2>/dev/null || true

    return $($all_passed && echo 0 || echo 1)
}

run_once() {
    if [[ -n "$SPECIFIC_PR" ]]; then
        validate_pr "$SPECIFIC_PR"
        return
    fi

    local prs
    prs=$(gh pr list --repo "$REPO" --json number --jq '.[].number' 2>/dev/null)
    if [[ -z "$prs" ]]; then
        echo "No open PRs."
        return
    fi

    echo "Open PRs: $prs"
    for pr_num in $prs; do
        validate_pr "$pr_num" || true
    done
}

if $WATCH; then
    echo "Watching for PRs every ${POLL_INTERVAL}s (Ctrl+C to stop)..."
    while true; do
        run_once
        sleep "$POLL_INTERVAL"
    done
else
    run_once
fi
