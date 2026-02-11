#!/bin/bash
# PR Assignment Manager - Monitors PRs and spawns dedicated reviewer agents
#
# Usage:
#   ./scripts/pr_assignment_manager.sh              # Run once
#   ./scripts/pr_assignment_manager.sh --watch       # Continuous monitoring
#   ./scripts/pr_assignment_manager.sh --status      # Show active assignments
#   ./scripts/pr_assignment_manager.sh --cleanup     # Clean up stale agents
#
set -euo pipefail

REPO="aryavolkan/evolve"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="$PROJECT_DIR/.pr-agents"
LOCK_FILE="$STATE_DIR/.manager.lock"
POLL_INTERVAL="${POLL_INTERVAL:-120}"
LOG_FILE="$STATE_DIR/manager.log"

mkdir -p "$STATE_DIR"

# --- Logging ---
log() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" | tee -a "$LOG_FILE"
}

# --- Lock management ---
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Manager already running (PID $pid). Use --status to check."
            exit 1
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# --- State management ---
# Each assigned PR gets a file: $STATE_DIR/pr-<number>.json
# Contains: { number, title, branch, agent_session, assigned_at, status }

is_assigned() {
    local pr_num="$1"
    [[ -f "$STATE_DIR/pr-${pr_num}.json" ]]
}

mark_assigned() {
    local pr_num="$1" title="$2" branch="$3" session_id="$4"
    cat > "$STATE_DIR/pr-${pr_num}.json" <<EOF
{
  "number": $pr_num,
  "title": "$(echo "$title" | sed 's/"/\\"/g')",
  "branch": "$branch",
  "agent_session": "$session_id",
  "assigned_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "status": "active"
}
EOF
    log "Assigned agent $session_id to PR #$pr_num ($title)"
}

mark_completed() {
    local pr_num="$1" reason="$2"
    if [[ -f "$STATE_DIR/pr-${pr_num}.json" ]]; then
        # Update status
        local tmp=$(mktemp)
        jq --arg r "$reason" --arg t "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
            '.status = "completed" | .completed_at = $t | .reason = $r' \
            "$STATE_DIR/pr-${pr_num}.json" > "$tmp" && mv "$tmp" "$STATE_DIR/pr-${pr_num}.json"
        log "PR #$pr_num completed: $reason"
    fi
}

# --- Agent spawning ---
spawn_reviewer_agent() {
    local pr_num="$1" title="$2" branch="$3" author="$4"

    if is_assigned "$pr_num"; then
        log "PR #$pr_num already assigned, skipping"
        return 0
    fi

    local session_id="pr-reviewer-${pr_num}"

    log "Spawning reviewer agent for PR #$pr_num: $title (branch: $branch)"

    # Build the agent task description
    local task="You are a dedicated PR reviewer agent for PR #${pr_num} in the evolve project.

PROJECT: /Users/aryasen/Projects/evolve
REPO: ${REPO}
PR: #${pr_num}
TITLE: ${title}
BRANCH: ${branch}
AUTHOR: ${author}

YOUR MISSION:
1. Check out the PR branch and ensure it's up to date
2. Check for merge conflicts with main - resolve if possible
3. Run the full validation suite:
   - Unit tests: godot --headless --path . --script test/test_runner.gd
   - Gameplay tests: godot --headless --path . --script test/integration/gameplay_test_runner.gd
   - Training smoke test: godot --headless --path . --script test/integration/training_smoke_test.gd
   OR use: python scripts/pr_validator.py --merge-target=main
4. Comment on the PR with detailed results using: gh pr comment ${pr_num} --repo ${REPO} --body '<report>'
5. If ALL tests pass: auto-merge with gh pr merge ${pr_num} --repo ${REPO} --merge
6. If tests fail: comment with failure details and do NOT merge
7. After merge: delete the remote branch with gh api -X DELETE repos/${REPO}/git/refs/heads/${branch}

IMPORTANT:
- Work in /Users/aryasen/Projects/evolve
- Use 'git stash' before switching branches if needed
- Always return to 'main' branch when done
- If merge conflicts can't be auto-resolved, comment on PR and stop
- Be thorough in your test report

Report format for PR comment:
## 🤖 Automated Review — PR #${pr_num}
**Branch:** \`${branch}\`
**Reviewer:** Agent ${session_id}

### Merge Conflicts
[clean/resolved/blocked]

### Unit Tests
[pass count / fail details]

### Gameplay Tests
[pass count / fail details]

### Training Smoke Test
[pass/fail]

### Decision
[✅ Auto-merging / ❌ Blocked — reason]
"

    # Spawn via openclaw agent (background)
    nohup openclaw agent \
        --session-id "$session_id" \
        --message "$task" \
        --channel whatsapp \
        --timeout 900 \
        > "$STATE_DIR/pr-${pr_num}.log" 2>&1 &

    local agent_pid=$!
    mark_assigned "$pr_num" "$title" "$branch" "$session_id"
    log "Agent PID $agent_pid spawned for PR #$pr_num"
}

# --- PR monitoring ---
check_new_prs() {
    log "Checking for open PRs..."

    local prs
    prs=$(gh pr list --repo "$REPO" --state open --json number,title,headRefName,author \
        --jq '.[] | "\(.number)\t\(.title)\t\(.headRefName)\t\(.author.login)"' 2>/dev/null) || {
        log "ERROR: Failed to fetch PRs"
        return 1
    }

    if [[ -z "$prs" ]]; then
        log "No open PRs"
        return 0
    fi

    while IFS=$'\t' read -r pr_num title branch author; do
        if ! is_assigned "$pr_num"; then
            spawn_reviewer_agent "$pr_num" "$title" "$branch" "$author"
        fi
    done <<< "$prs"
}

# --- Cleanup ---
cleanup_completed() {
    log "Checking for completed/closed PRs..."

    # Get list of currently open PR numbers
    local open_prs
    open_prs=$(gh pr list --repo "$REPO" --state open --json number --jq '.[].number' 2>/dev/null) || return 1

    # Check each assigned PR
    for state_file in "$STATE_DIR"/pr-*.json; do
        [[ -f "$state_file" ]] || continue

        local pr_num=$(jq -r '.number' "$state_file")
        local status=$(jq -r '.status' "$state_file")
        local session_id=$(jq -r '.agent_session' "$state_file")

        [[ "$status" == "completed" ]] && continue

        # Check if PR is still open
        if ! echo "$open_prs" | grep -q "^${pr_num}$"; then
            # PR was closed or merged
            local pr_state
            pr_state=$(gh pr view "$pr_num" --repo "$REPO" --json state --jq '.state' 2>/dev/null) || pr_state="UNKNOWN"

            log "PR #$pr_num is now $pr_state — cleaning up agent $session_id"
            mark_completed "$pr_num" "PR $pr_state"

            # Agent session will naturally terminate after completion
        fi
    done
}

# --- Status display ---
show_status() {
    echo "╔══════════════════════════════════════════════╗"
    echo "║       PR Assignment Manager — Status         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    local active=0 completed=0
    for state_file in "$STATE_DIR"/pr-*.json; do
        [[ -f "$state_file" ]] || continue

        local pr_num=$(jq -r '.number' "$state_file")
        local title=$(jq -r '.title' "$state_file")
        local status=$(jq -r '.status' "$state_file")
        local session=$(jq -r '.agent_session' "$state_file")
        local assigned=$(jq -r '.assigned_at' "$state_file")

        if [[ "$status" == "active" ]]; then
            echo "  🟢 PR #$pr_num: $title"
            echo "     Agent: $session | Since: $assigned"
            ((active++))
        else
            local reason=$(jq -r '.reason // "unknown"' "$state_file")
            echo "  ⚪ PR #$pr_num: $title ($reason)"
            ((completed++))
        fi
    done

    if [[ $active -eq 0 && $completed -eq 0 ]]; then
        echo "  No PR assignments yet."
    fi

    echo ""
    echo "  Active: $active | Completed: $completed"
    echo ""
}

# --- Main ---
ACTION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)    ACTION="watch"; shift ;;
        --status)   ACTION="status"; shift ;;
        --cleanup)  ACTION="cleanup"; shift ;;
        --interval) POLL_INTERVAL="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

case "$ACTION" in
    status)
        show_status
        ;;
    cleanup)
        cleanup_completed
        ;;
    watch)
        acquire_lock
        log "=== PR Assignment Manager started (poll every ${POLL_INTERVAL}s) ==="
        while true; do
            check_new_prs
            cleanup_completed
            sleep "$POLL_INTERVAL"
        done
        ;;
    *)
        # Single run
        check_new_prs
        cleanup_completed
        ;;
esac
