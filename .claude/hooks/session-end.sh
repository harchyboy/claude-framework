#!/usr/bin/env bash
set -euo pipefail

# Session end hook — Stop event
# Writes structured handoff to .claude/handoff/session-summary.md
# Optionally pings healthcheck and Slack webhook.

HANDOFF_DIR=".claude/handoff"
HANDOFF_FILE="$HANDOFF_DIR/session-summary.md"
HISTORY_LOG="$HANDOFF_DIR/session-history.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$HANDOFF_DIR"

# Gather session data
FILES_CHANGED=$(git diff --name-only HEAD~1 2>/dev/null | head -20 || echo "Unable to determine")
TEST_STATUS=$(git log -1 --pretty=%B 2>/dev/null | grep -i "test\|pass\|fail" || echo "Unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# Write structured handoff file
cat > "$HANDOFF_FILE" <<HANDOFF
# Session Handoff — $TIMESTAMP

Branch: $BRANCH

## Completed
- [Fill in: what was finished with specific details]

## In Progress
- [Fill in: what was started but not completed, with current state]

## Not Started
- [Fill in: what remains from the original task]

## Key Decisions
- [Fill in: architectural decisions as belief statements]
- [e.g. "Authentication uses Bearer tokens; refresh endpoint returns 401 on expired tokens"]

## Files Modified
$FILES_CHANGED

## Test Status
$TEST_STATUS

## Blockers
- [Fill in: issues preventing progress, with what was already tried]
HANDOFF

# Append to session history log
CHANGED_COUNT=$(echo "$FILES_CHANGED" | wc -l | tr -d ' ')
echo "$TIMESTAMP | branch=$BRANCH | files_changed=$CHANGED_COUNT | tests=$TEST_STATUS" >> "$HISTORY_LOG"

# Ping healthcheck if configured
if [[ -n "${HEALTHCHECK_URL:-}" ]]; then
  curl -fsS -m 10 "$HEALTHCHECK_URL" &>/dev/null || true
fi

# Post to Slack if configured
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  SUMMARY="Session ended on branch \`$BRANCH\` at $TIMESTAMP. Files changed: $CHANGED_COUNT."
  curl -fsS -m 10 -X POST -H 'Content-type: application/json' \
    --data "{\"text\": \"$SUMMARY\"}" \
    "$SLACK_WEBHOOK_URL" &>/dev/null || true
fi

echo "Handoff written to $HANDOFF_FILE"
exit 0
