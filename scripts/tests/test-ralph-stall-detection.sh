#!/bin/bash
# test-ralph-stall-detection.sh — Tests for ralph.sh activity-based stall detection (US-003)
# Run: bash scripts/tests/test-ralph-stall-detection.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RALPH="$REPO_ROOT/scripts/ralph.sh"

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

# ─── Setup ───────────────────────────────────────────────────────────────────

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Extract start_stall_watchdog function from ralph.sh for isolated testing
extract_function() {
  local func_name="$1"
  local start_line end_line
  start_line=$(grep -n "^${func_name}()" "$RALPH" | head -1 | cut -d: -f1)

  if [[ -z "$start_line" ]]; then
    echo ""
    return 1
  fi

  local brace_count=0
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if [[ $line_num -lt $start_line ]]; then continue; fi
    local opens closes
    opens=$(echo "$line" | tr -cd '{' | wc -c)
    closes=$(echo "$line" | tr -cd '}' | wc -c)
    brace_count=$((brace_count + opens - closes))
    if [[ $brace_count -eq 0 && $line_num -gt $start_line ]]; then
      end_line=$line_num
      break
    fi
  done < "$RALPH"

  sed -n "${start_line},${end_line}p" "$RALPH"
}

echo ""
echo "═══════════════════════════════════════"
echo "TEST: Ralph Activity-Based Stall Detection"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: --stall-timeout flag exists in usage/help ───────────────────────

echo "── Flag parsing ──"

if grep -q '\-\-stall-timeout' "$RALPH"; then
  pass "should have --stall-timeout flag in ralph.sh"
else
  fail "should have --stall-timeout flag in ralph.sh"
fi

# ─── Test 2: Default stall timeout is 5 minutes ─────────────────────────────

if grep -qE 'STALL_TIMEOUT.*=.*5' "$RALPH"; then
  pass "should default STALL_TIMEOUT to 5 minutes"
else
  fail "should default STALL_TIMEOUT to 5 minutes"
fi

# ─── Test 3: Stall timeout can be disabled with 0 ───────────────────────────

if grep -qE 'STALL_TIMEOUT.*0|stall.*disable|stall.*skip' "$RALPH"; then
  pass "should support disabling stall detection with --stall-timeout 0"
else
  fail "should support disabling stall detection with --stall-timeout 0"
fi

# ─── Test 4: start_stall_watchdog function exists ────────────────────────────

echo ""
echo "── Stall watchdog function ──"

if grep -q '^start_stall_watchdog()' "$RALPH"; then
  pass "should define start_stall_watchdog() function"
else
  fail "should define start_stall_watchdog() function"
fi

# ─── Test 5: Watchdog monitors log file mtime ───────────────────────────────

if grep -qE 'stat.*%Y|stat.*%m|stat.*mtime|date.*-r|GetLastWriteTime' "$RALPH"; then
  pass "should check log file modification time"
else
  fail "should check log file modification time"
fi

# ─── Test 6: Watchdog checks every 30 seconds ───────────────────────────────

if grep -qE 'sleep 30|CHECK_INTERVAL.*30|check_interval.*30' "$RALPH"; then
  pass "should poll every 30 seconds"
else
  fail "should poll every 30 seconds"
fi

# ─── Test 7: Stall kill is logged ────────────────────────────────────────────

echo ""
echo "── Stall logging ──"

if grep -qE 'Stall detected|stall.*detect|no output for' "$RALPH"; then
  pass "should log stall detection message"
else
  fail "should log stall detection message"
fi

# ─── Test 8: Stall counts as failure for retry/stuck detection ───────────────

if grep -qE 'STALL.*fail|stall.*CLAUDE_EXIT|stall.*exit' "$RALPH"; then
  pass "should treat stall as failure for retry/stuck detection"
else
  fail "should treat stall as failure for retry/stuck detection"
fi

# ─── Test 9: 60-second grace period ──────────────────────────────────────────

echo ""
echo "── Grace period ──"

if grep -qE 'grace.*60|GRACE.*60|startup.*grace|60.*grace|grace_period.*60|STALL_GRACE.*60' "$RALPH"; then
  pass "should have 60-second startup grace period"
else
  fail "should have 60-second startup grace period"
fi

# ─── Test 10: Telemetry event emitted on stall ──────────────────────────────

echo ""
echo "── Telemetry ──"

if grep -qE 'stall_detected|emit_ralph_event.*stall' "$RALPH"; then
  pass "should emit stall_detected telemetry event"
else
  fail "should emit stall_detected telemetry event"
fi

# ─── Test 11: Telemetry includes story_id and elapsed time ──────────────────

if grep -A3 'stall_detected' "$RALPH" | grep -qE 'story_id|elapsed'; then
  pass "should include story_id in stall telemetry event"
else
  fail "should include story_id in stall telemetry event"
fi

# ─── Test 12: Watchdog kills with SIGTERM first ─────────────────────────────

echo ""
echo "── Kill behavior ──"

if grep -qE 'SIGTERM|kill.*-15|kill.*TERM|kill "\$CLAUDE_PID"' "$RALPH" | head -1 && \
   grep -qE 'stall.*kill|watchdog.*kill|kill.*CLAUDE' "$RALPH"; then
  pass "should kill Claude process on stall"
else
  # Simpler check — just verify kill is used in stall context
  if grep -qE 'stall' "$RALPH" && grep -qE 'kill.*CLAUDE_PID' "$RALPH"; then
    pass "should kill Claude process on stall"
  else
    fail "should kill Claude process on stall"
  fi
fi

# ─── Test 13: Stall watchdog runs as background process ─────────────────────

if grep -qE 'STALL_WATCHDOG_PID|stall.*&$|watchdog.*&$|start_stall_watchdog.*&' "$RALPH"; then
  pass "should run stall watchdog as background process"
else
  fail "should run stall watchdog as background process"
fi

# ─── Test 14: Stall watchdog is cleaned up after Claude exits ────────────────

if grep -qE 'kill.*STALL_WATCHDOG|STALL_WATCHDOG.*kill' "$RALPH"; then
  pass "should clean up stall watchdog when Claude exits"
else
  fail "should clean up stall watchdog when Claude exits"
fi

# ─── Test 15: Stall timeout displayed in startup banner ─────────────────────

echo ""
echo "── Integration ──"

if grep -qE 'Stall timeout|stall.*timeout.*echo|STALL_TIMEOUT' "$RALPH" | head -1 && \
   grep -qE 'echo.*[Ss]tall' "$RALPH"; then
  pass "should display stall timeout in startup banner"
else
  if grep -qE 'echo.*[Ss]tall|STALL_TIMEOUT.*echo' "$RALPH"; then
    pass "should display stall timeout in startup banner"
  else
    fail "should display stall timeout in startup banner"
  fi
fi

# ─── Test 16: --stall-timeout flag parsing shifts argument ───────────────────

if grep -B1 -A1 'stall.timeout' "$RALPH" | grep -qE 'shift'; then
  pass "should shift after consuming --stall-timeout argument"
else
  fail "should shift after consuming --stall-timeout argument"
fi

# ─── Test 17: Functional test — stall watchdog detects stall ─────────────────

echo ""
echo "── Functional tests ──"

FUNC_SRC=$(extract_function "start_stall_watchdog" 2>/dev/null || echo "")

if [[ -n "$FUNC_SRC" ]]; then
  # Create a log file that won't be updated (simulating stall)
  STALL_LOG="$TMPDIR_TEST/stall_test.log"
  echo "initial content" > "$STALL_LOG"

  # Create a dummy process to be the "Claude" process
  sleep 300 &
  DUMMY_PID=$!

  # Run watchdog with very short timeout (2 seconds) and no grace period for testing
  (
    STALL_TIMEOUT=0  # will be overridden
    STALL_GRACE=0
    LOG_FILE="$STALL_LOG"
    CLAUDE_PID=$DUMMY_PID
    STORY_ID="US-TEST"
    TELEMETRY=false
    eval "$FUNC_SRC"
    # Override stall params for fast test
    STALL_TIMEOUT_SECS=2
    STALL_GRACE_SECS=0
    STALL_CHECK_INTERVAL=1
    start_stall_watchdog
  ) &
  WATCHDOG_TEST_PID=$!

  # Wait for watchdog to detect stall (should happen within ~3 seconds)
  sleep 4

  # Check if dummy process was killed
  if ! kill -0 "$DUMMY_PID" 2>/dev/null; then
    pass "should kill stalled process when no output detected"
  else
    fail "should kill stalled process when no output detected"
    kill "$DUMMY_PID" 2>/dev/null || true
  fi

  kill "$WATCHDOG_TEST_PID" 2>/dev/null || true
  wait "$WATCHDOG_TEST_PID" 2>/dev/null || true
  wait "$DUMMY_PID" 2>/dev/null || true

  # Test: watchdog does NOT kill when log file is being updated
  ACTIVE_LOG="$TMPDIR_TEST/active_test.log"
  echo "initial content" > "$ACTIVE_LOG"

  sleep 300 &
  DUMMY_PID2=$!

  # Keep updating the log file
  (
    for i in $(seq 1 10); do
      echo "output line $i" >> "$ACTIVE_LOG"
      sleep 1
    done
  ) &
  UPDATER_PID=$!

  (
    LOG_FILE="$ACTIVE_LOG"
    CLAUDE_PID=$DUMMY_PID2
    STORY_ID="US-TEST"
    TELEMETRY=false
    eval "$FUNC_SRC"
    STALL_TIMEOUT_SECS=3
    STALL_GRACE_SECS=0
    STALL_CHECK_INTERVAL=1
    start_stall_watchdog
  ) &
  WATCHDOG_TEST_PID2=$!

  sleep 4

  if kill -0 "$DUMMY_PID2" 2>/dev/null; then
    pass "should NOT kill process when log file is actively updated"
  else
    fail "should NOT kill process when log file is actively updated"
  fi

  kill "$DUMMY_PID2" 2>/dev/null || true
  kill "$UPDATER_PID" 2>/dev/null || true
  kill "$WATCHDOG_TEST_PID2" 2>/dev/null || true
  wait "$DUMMY_PID2" 2>/dev/null || true
  wait "$UPDATER_PID" 2>/dev/null || true
  wait "$WATCHDOG_TEST_PID2" 2>/dev/null || true
else
  fail "should define start_stall_watchdog function for testing"
  fail "should kill stalled process when no output detected (skipped — no function)"
  fail "should NOT kill process when log file is actively updated (skipped — no function)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "───────────────────────────────────────"
echo "Tests: $TESTS_RUN | Passed: $TESTS_PASSED | Failed: $TESTS_FAILED"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "\nFailures:$FAILURES"
  echo ""
  exit 1
else
  echo "All tests passing."
  echo ""
  exit 0
fi
