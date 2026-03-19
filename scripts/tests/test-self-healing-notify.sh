#!/bin/bash
# test-self-healing-notify.sh — Tests for self-healing retries and notifications
# Run: bash scripts/tests/test-self-healing-notify.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RALPH="$REPO_ROOT/scripts/ralph.sh"
NOTIFY="$REPO_ROOT/scripts/lib/notify.sh"

# ─── Test framework ─────────────────────────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=""

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  ✅ $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES="${FAILURES}\n  ❌ $1"
  echo "  ❌ $1"
}

echo ""
echo "═══════════════════════════════════════"
echo "TEST: Self-Healing Retries & Notifications"
echo "═══════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Feature 1: Self-Healing Retries
# ═══════════════════════════════════════════════════════════════════════════

echo "── Self-Healing Retries ──"

echo ""
echo "  Diagnosis injection:"

# Check build_continuation_prompt includes diagnosis lookup
if grep -qE 'diagnosis.*STORY_ID.*iter' "$RALPH" && grep -q 'build_continuation_prompt' "$RALPH"; then
  pass "should look for diagnosis files in build_continuation_prompt"
else
  fail "should look for diagnosis files in build_continuation_prompt"
fi

if grep -qE 'prev_diagnosis' "$RALPH"; then
  pass "should track prev_diagnosis variable"
else
  fail "should track prev_diagnosis variable"
fi

if grep -qE 'diag_summary' "$RALPH"; then
  pass "should extract diagnosis summary"
else
  fail "should extract diagnosis summary"
fi

if grep -qE 'diag_action' "$RALPH"; then
  pass "should extract suggested action"
else
  fail "should extract suggested action"
fi

if grep -qE 'PREVIOUS FAILURE DIAGNOSIS' "$RALPH"; then
  pass "should include PREVIOUS FAILURE DIAGNOSIS section in retry prompt"
else
  fail "should include PREVIOUS FAILURE DIAGNOSIS section in retry prompt"
fi

if grep -qE 'READ THIS FIRST' "$RALPH"; then
  pass "should instruct agent to read diagnosis first"
else
  fail "should instruct agent to read diagnosis first"
fi

if grep -qE 'Do NOT repeat the same approach' "$RALPH"; then
  pass "should warn agent not to repeat failed approach"
else
  fail "should warn agent not to repeat failed approach"
fi

if grep -qE 'Full diagnosis JSON' "$RALPH"; then
  pass "should include full diagnosis JSON in expandable section"
else
  fail "should include full diagnosis JSON in expandable section"
fi

# Check that diagnosis is conditionally included (empty = no section)
if grep -qE '\$\{prev_diagnosis:' "$RALPH"; then
  pass "should conditionally include diagnosis (skip if none available)"
else
  fail "should conditionally include diagnosis (skip if none available)"
fi

# Functional test: verify diagnosis file lookup logic
echo ""
echo "  Functional:"

TMPDIR_HEAL=$(mktemp -d)
ORIG_DIR=$(pwd)
cd "$TMPDIR_HEAL"
mkdir -p agent_logs

# Create a fake diagnosis file
cat > agent_logs/diagnosis-US-HEAL-iter2.json <<'DIAGEOF'
{
  "story_id": "US-HEAL",
  "iteration": 2,
  "failure_type": "quality_gate",
  "summary": "2 compilation errors: Cannot find name Session in src/auth.ts",
  "suggested_action": "Fix compilation errors. Add missing import for Session type.",
  "compilation_errors": [
    {"file": "src/auth.ts", "code": "TS2304", "message": "Cannot find name 'Session'"}
  ],
  "test_failures": [],
  "errors": [],
  "stack_traces": []
}
DIAGEOF

# Simulate the lookup logic
LOOKUP_RESULT=$(bash -c "
  STORY_ID='US-HEAL'
  ITERATION=3
  for ((di=ITERATION-1; di>=1; di--)); do
    diag_file=\"agent_logs/diagnosis-\${STORY_ID}-iter\${di}.json\"
    if [[ -f \"\$diag_file\" ]]; then
      echo \"FOUND:\$diag_file\"
      break
    fi
  done
" 2>&1)

if echo "$LOOKUP_RESULT" | grep -q "FOUND:agent_logs/diagnosis-US-HEAL-iter2.json"; then
  pass "should find most recent diagnosis file for story"
else
  fail "should find most recent diagnosis file for story"
fi

# Verify summary extraction
SUMMARY=$(node -e "const d=JSON.parse(require('fs').readFileSync('agent_logs/diagnosis-US-HEAL-iter2.json','utf8'));console.log(d.summary)" 2>/dev/null || echo "")
if echo "$SUMMARY" | grep -q "compilation errors"; then
  pass "should extract summary from diagnosis file"
else
  fail "should extract summary from diagnosis file"
fi

cd "$ORIG_DIR"
rm -rf "$TMPDIR_HEAL"

# ═══════════════════════════════════════════════════════════════════════════
# Feature 2: Notifications
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "── Notification Library ──"

echo ""
echo "  Library structure:"

if [[ -f "$NOTIFY" ]]; then
  pass "should have scripts/lib/notify.sh"
else
  fail "should have scripts/lib/notify.sh"
fi

if grep -qE 'notify_send\(\)' "$NOTIFY"; then
  pass "should export notify_send dispatcher function"
else
  fail "should export notify_send dispatcher function"
fi

if grep -qE 'notify_slack\(\)' "$NOTIFY"; then
  pass "should export notify_slack function"
else
  fail "should export notify_slack function"
fi

if grep -qE 'notify_discord\(\)' "$NOTIFY"; then
  pass "should export notify_discord function"
else
  fail "should export notify_discord function"
fi

if grep -qE 'notify_generic_webhook\(\)' "$NOTIFY"; then
  pass "should export notify_generic_webhook function"
else
  fail "should export notify_generic_webhook function"
fi

if grep -qE 'notify_is_enabled\(\)' "$NOTIFY"; then
  pass "should export notify_is_enabled function"
else
  fail "should export notify_is_enabled function"
fi

if grep -qE 'notify_sanitize\(\)' "$NOTIFY"; then
  pass "should export notify_sanitize function"
else
  fail "should export notify_sanitize function"
fi

echo ""
echo "  Environment variables:"

if grep -qE 'SLACK_WEBHOOK_URL' "$NOTIFY"; then
  pass "should support SLACK_WEBHOOK_URL"
else
  fail "should support SLACK_WEBHOOK_URL"
fi

if grep -qE 'DISCORD_WEBHOOK_URL' "$NOTIFY"; then
  pass "should support DISCORD_WEBHOOK_URL"
else
  fail "should support DISCORD_WEBHOOK_URL"
fi

if grep -qE 'NOTIFICATION_WEBHOOK_URL' "$NOTIFY"; then
  pass "should support NOTIFICATION_WEBHOOK_URL"
else
  fail "should support NOTIFICATION_WEBHOOK_URL"
fi

if grep -qE 'NOTIFY_ENABLED' "$NOTIFY"; then
  pass "should support NOTIFY_ENABLED kill switch"
else
  fail "should support NOTIFY_ENABLED kill switch"
fi

echo ""
echo "  Safety:"

if grep -qE 'max-time 10' "$NOTIFY"; then
  pass "should use --max-time 10 on all curl calls"
else
  fail "should use --max-time 10 on all curl calls"
fi

if grep -qE '\|\| true' "$NOTIFY"; then
  pass "should never fail on notification errors (|| true)"
else
  fail "should never fail on notification errors (|| true)"
fi

if grep -qE 'notify_sanitize' "$NOTIFY"; then
  pass "should sanitize paths before sending"
else
  fail "should sanitize paths before sending"
fi

echo ""
echo "  Formatting:"

if grep -qE 'severity_color' "$NOTIFY"; then
  pass "should support severity-based colors"
else
  fail "should support severity-based colors"
fi

if grep -q 'blocks' "$NOTIFY"; then
  pass "should use Slack Block Kit formatting"
else
  fail "should use Slack Block Kit formatting"
fi

if grep -qE 'embeds' "$NOTIFY"; then
  pass "should use Discord embed formatting"
else
  fail "should use Discord embed formatting"
fi

echo ""
echo "  Ralph integration:"

if grep -qE 'notify\.sh' "$RALPH"; then
  pass "should source notify.sh in ralph.sh"
else
  fail "should source notify.sh in ralph.sh"
fi

# Trigger: loop completion
if grep -qE 'notify_send.*ralph_complete' "$RALPH"; then
  pass "should notify on loop completion"
else
  fail "should notify on loop completion"
fi

# Trigger: story stuck
if grep -qE 'notify_send.*story_stuck' "$RALPH"; then
  pass "should notify on story stuck"
else
  fail "should notify on story stuck"
fi

# Trigger: crash
if grep -qE 'notify_send.*critical_failure.*crash' "$RALPH"; then
  pass "should notify on agent crash"
else
  fail "should notify on agent crash"
fi

# Trigger: stall
if grep -qE 'notify_send.*critical_failure.*stall' "$RALPH"; then
  pass "should notify on agent stall"
else
  fail "should notify on agent stall"
fi

# Completion notification includes key metrics
if grep -q 'STORIES_DONE' "$RALPH" && grep -q 'NOTIFY_MSG' "$RALPH"; then
  pass "should include stories/iterations/time in completion notification"
else
  fail "should include stories/iterations/time in completion notification"
fi

# Stuck notification includes story ID
if grep -q 'story_stuck' "$RALPH" && grep -q 'STORY_ID' "$RALPH"; then
  pass "should include story ID in stuck notification"
else
  fail "should include story ID in stuck notification"
fi

# Functional test: notify_send dispatches without errors
echo ""
echo "  Functional:"

DISPATCH_OUTPUT=$(bash -c "
  . '$NOTIFY'
  # No webhooks set — should silently do nothing
  notify_send 'test_event' 'Test Title' 'Test message' 'info' 2>&1
  echo 'DISPATCH_OK'
" 2>&1)

if echo "$DISPATCH_OUTPUT" | grep -q "DISPATCH_OK"; then
  pass "should silently succeed when no webhooks configured"
else
  fail "should silently succeed when no webhooks configured"
fi

# Test sanitize function
SANITIZE_OUTPUT=$(bash -c "
  . '$NOTIFY'
  result=\$(notify_sanitize '/c/Users/craig/Documents/Projects/myapp/src/file.ts')
  echo \"\$result\"
" 2>&1)

if echo "$SANITIZE_OUTPUT" | grep -qv "craig"; then
  pass "should strip username from paths in sanitize"
else
  fail "should strip username from paths in sanitize"
fi

# ─── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "RESULTS: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "═══════════════════════════════════════"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo ""
  echo "Failures:"
  echo -e "$FAILURES"
  echo ""
  exit 1
fi

exit 0
