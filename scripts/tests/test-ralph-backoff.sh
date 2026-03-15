#!/bin/bash
# test-ralph-backoff.sh — Tests for ralph.sh exponential backoff on story retries (US-004)
# Run: bash scripts/tests/test-ralph-backoff.sh

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

# Extract function from ralph.sh for isolated testing
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
echo "TEST: Ralph Exponential Backoff on Retries"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: --no-backoff flag exists in ralph.sh ─────────────────────────

echo "── Flag parsing ──"

if grep -q '\-\-no-backoff' "$RALPH"; then
  pass "should have --no-backoff flag in ralph.sh"
else
  fail "should have --no-backoff flag in ralph.sh"
fi

# ─── Test 2: BACKOFF_ENABLED variable exists and defaults to true ─────────

if grep -qE 'BACKOFF_ENABLED.*=.*true' "$RALPH"; then
  pass "should default BACKOFF_ENABLED to true"
else
  fail "should default BACKOFF_ENABLED to true"
fi

# ─── Test 3: --no-backoff sets BACKOFF_ENABLED to false ──────────────────

if grep -qE '\-\-no-backoff\).*BACKOFF_ENABLED=false' "$RALPH"; then
  pass "should set BACKOFF_ENABLED=false when --no-backoff is passed"
else
  fail "should set BACKOFF_ENABLED=false when --no-backoff is passed"
fi

# ─── Test 4: calculate_backoff function exists ───────────────────────────

echo ""
echo "── Backoff calculation function ──"

if grep -q '^calculate_backoff()' "$RALPH"; then
  pass "should have calculate_backoff() function"
else
  fail "should have calculate_backoff() function"
fi

# ─── Test 5: calculate_backoff returns correct values ────────────────────

CALC_FUNC=$(extract_function "calculate_backoff" 2>/dev/null || echo "")

if [[ -n "$CALC_FUNC" ]]; then
  # Create a test script that sources the function and checks values
  cat > "$TMPDIR_TEST/test_calc.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

# Source the function
eval "$CALC_FUNC_BODY"

# Test: fail_count=1 -> 10s
result=$(calculate_backoff 1)
if [[ "$result" -eq 10 ]]; then echo "PASS:1"; else echo "FAIL:1:got=$result"; fi

# Test: fail_count=2 -> 20s
result=$(calculate_backoff 2)
if [[ "$result" -eq 20 ]]; then echo "PASS:2"; else echo "FAIL:2:got=$result"; fi

# Test: fail_count=3 -> 40s
result=$(calculate_backoff 3)
if [[ "$result" -eq 40 ]]; then echo "PASS:3"; else echo "FAIL:3:got=$result"; fi

# Test: fail_count=4 -> 80s
result=$(calculate_backoff 4)
if [[ "$result" -eq 80 ]]; then echo "PASS:4"; else echo "FAIL:4:got=$result"; fi

# Test: fail_count=5 -> 160s
result=$(calculate_backoff 5)
if [[ "$result" -eq 160 ]]; then echo "PASS:5"; else echo "FAIL:5:got=$result"; fi

# Test: fail_count=6 -> 300s (capped)
result=$(calculate_backoff 6)
if [[ "$result" -eq 300 ]]; then echo "PASS:6"; else echo "FAIL:6:got=$result"; fi

# Test: fail_count=10 -> 300s (still capped)
result=$(calculate_backoff 10)
if [[ "$result" -eq 300 ]]; then echo "PASS:10"; else echo "FAIL:10:got=$result"; fi
TESTEOF

  export CALC_FUNC_BODY="$CALC_FUNC"
  TEST_OUTPUT=$(bash "$TMPDIR_TEST/test_calc.sh" 2>&1) || true

  # Check fail_count=1 -> 10s
  if echo "$TEST_OUTPUT" | grep -q "PASS:1"; then
    pass "should return 10s for fail_count=1"
  else
    fail "should return 10s for fail_count=1 ($(echo "$TEST_OUTPUT" | grep "FAIL:1" || echo "function error"))"
  fi

  # Check fail_count=2 -> 20s
  if echo "$TEST_OUTPUT" | grep -q "PASS:2"; then
    pass "should return 20s for fail_count=2"
  else
    fail "should return 20s for fail_count=2 ($(echo "$TEST_OUTPUT" | grep "FAIL:2" || echo "function error"))"
  fi

  # Check fail_count=3 -> 40s
  if echo "$TEST_OUTPUT" | grep -q "PASS:3"; then
    pass "should return 40s for fail_count=3"
  else
    fail "should return 40s for fail_count=3 ($(echo "$TEST_OUTPUT" | grep "FAIL:3" || echo "function error"))"
  fi

  # Check fail_count=4 -> 80s
  if echo "$TEST_OUTPUT" | grep -q "PASS:4"; then
    pass "should return 80s for fail_count=4"
  else
    fail "should return 80s for fail_count=4 ($(echo "$TEST_OUTPUT" | grep "FAIL:4" || echo "function error"))"
  fi

  # Check fail_count=5 -> 160s
  if echo "$TEST_OUTPUT" | grep -q "PASS:5"; then
    pass "should return 160s for fail_count=5"
  else
    fail "should return 160s for fail_count=5 ($(echo "$TEST_OUTPUT" | grep "FAIL:5" || echo "function error"))"
  fi

  # Check fail_count=6 -> 300s (capped at max)
  if echo "$TEST_OUTPUT" | grep -q "PASS:6"; then
    pass "should cap at 300s for fail_count=6"
  else
    fail "should cap at 300s for fail_count=6 ($(echo "$TEST_OUTPUT" | grep "FAIL:6" || echo "function error"))"
  fi

  # Check fail_count=10 -> 300s (still capped)
  if echo "$TEST_OUTPUT" | grep -q "PASS:10"; then
    pass "should remain capped at 300s for fail_count=10"
  else
    fail "should remain capped at 300s for fail_count=10 ($(echo "$TEST_OUTPUT" | grep "FAIL:10" || echo "function error"))"
  fi
else
  fail "should return 10s for fail_count=1 (function not found)"
  fail "should return 20s for fail_count=2 (function not found)"
  fail "should return 40s for fail_count=3 (function not found)"
  fail "should return 80s for fail_count=4 (function not found)"
  fail "should return 160s for fail_count=5 (function not found)"
  fail "should cap at 300s for fail_count=6 (function not found)"
  fail "should remain capped at 300s for fail_count=10 (function not found)"
fi

# ─── Test 6: Backoff uses formula min(10 * 2^(n-1), 300) ────────────────

echo ""
echo "── Backoff formula ──"

if grep -qE '10.*2.*fail|2.*fail.*10|BASE_DELAY.*10|base.*10' "$RALPH"; then
  pass "should use base delay of 10 seconds in formula"
else
  fail "should use base delay of 10 seconds in formula"
fi

if grep -qE 'MAX_BACKOFF.*300|max.*300|300' "$RALPH" && grep -qE 'calculate_backoff' "$RALPH"; then
  pass "should cap at 300 seconds maximum"
else
  fail "should cap at 300 seconds maximum"
fi

# ─── Test 7: Backoff only on same-story retry ────────────────────────────

echo ""
echo "── Backoff triggers ──"

# Check that backoff is conditional on CONSECUTIVE_SAME > 0
if grep -qE 'CONSECUTIVE_SAME.*-gt.*0.*backoff|backoff.*CONSECUTIVE_SAME|BACKOFF.*CONSECUTIVE' "$RALPH"; then
  pass "should only apply backoff when retrying the same story"
else
  fail "should only apply backoff when retrying the same story"
fi

# ─── Test 8: Backoff is logged ───────────────────────────────────────────

echo ""
echo "── Logging ──"

if grep -qE 'Backing off|backoff.*retry|Back.off.*before retry' "$RALPH"; then
  pass "should log backoff message with duration and retry number"
else
  fail "should log backoff message with duration and retry number"
fi

# ─── Test 9: Telemetry includes backoff duration ─────────────────────────

echo ""
echo "── Telemetry ──"

if grep -qE 'backoff_duration|backoff_seconds|backoff.*duration' "$RALPH"; then
  pass "should include backoff duration in telemetry events"
else
  fail "should include backoff duration in telemetry events"
fi

# ─── Test 10: Backoff respects Ctrl+C (uses interruptible sleep) ──────────

echo ""
echo "── Graceful shutdown ──"

# The backoff sleep should be interruptible — either via trap or a sleep loop
if grep -qE 'trap.*backoff|backoff.*trap|sleep.*backoff.*INT|interruptible.*sleep|BACKOFF_INTERRUPTED|kill.*sleep' "$RALPH"; then
  pass "should respect Ctrl+C during backoff sleep (interruptible)"
else
  # Alternative: check for a loop-based sleep that checks a flag
  if grep -qE 'while.*backoff.*sleep 1|backoff.*sleep 1|backoff_sleep' "$RALPH"; then
    pass "should respect Ctrl+C during backoff sleep (loop-based)"
  else
    fail "should respect Ctrl+C during backoff sleep (interruptible)"
  fi
fi

# ─── Test 11: --no-backoff disables backoff ──────────────────────────────

echo ""
echo "── Flag behaviour ──"

if grep -qE 'BACKOFF_ENABLED.*!=.*true|BACKOFF_ENABLED.*==.*false|BACKOFF_ENABLED.*true.*backoff' "$RALPH"; then
  pass "should skip backoff when --no-backoff flag is set"
else
  fail "should skip backoff when --no-backoff flag is set"
fi

# ─── Test 12: No backoff when moving to a new story ──────────────────────

# The backoff should only trigger on same-story retries (CONSECUTIVE_SAME > 0)
# When CONSECUTIVE_SAME is reset to 0 for new stories, no backoff should happen
if grep -qE 'CONSECUTIVE_SAME.*0|CONSECUTIVE_SAME.*-eq.*0|new story.*no backoff' "$RALPH"; then
  pass "should not backoff when moving to a new story (CONSECUTIVE_SAME resets)"
else
  fail "should not backoff when moving to a new story (CONSECUTIVE_SAME resets)"
fi

# ─── Test 13: --no-backoff in help text ──────────────────────────────────

echo ""
echo "── Documentation ──"

if head -35 "$RALPH" | grep -q '\-\-no-backoff'; then
  pass "should document --no-backoff in help/usage header"
else
  fail "should document --no-backoff in help/usage header"
fi

# ─── Test 14: Backoff interruptible sleep function ────────────────────────

echo ""
echo "── Interruptible sleep ──"

if grep -q '^backoff_sleep()' "$RALPH"; then
  pass "should have backoff_sleep() function for interruptible waiting"
else
  fail "should have backoff_sleep() function for interruptible waiting"
fi

# ─── Test 15: backoff_sleep can be interrupted ────────────────────────────

SLEEP_FUNC=$(extract_function "backoff_sleep" 2>/dev/null || echo "")

if [[ -n "$SLEEP_FUNC" ]]; then
  # Test that backoff_sleep exits quickly when interrupted
  cat > "$TMPDIR_TEST/test_sleep.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

BACKOFF_INTERRUPTED=false

eval "$SLEEP_FUNC_BODY"

# Test: sleep for 60 seconds but interrupt after 1 second
(
  sleep 1
  kill -INT $$ 2>/dev/null || true
) &
INTERRUPTER=$!

trap 'BACKOFF_INTERRUPTED=true' INT

START=$(date +%s)
backoff_sleep 60
END=$(date +%s)
ELAPSED=$((END - START))

kill "$INTERRUPTER" 2>/dev/null || true
wait "$INTERRUPTER" 2>/dev/null || true

# Should have exited well before 60 seconds
if [[ "$ELAPSED" -lt 10 ]]; then
  echo "PASS:interrupt"
else
  echo "FAIL:interrupt:elapsed=$ELAPSED"
fi
TESTEOF

  export SLEEP_FUNC_BODY="$SLEEP_FUNC"
  SLEEP_OUTPUT=$(bash "$TMPDIR_TEST/test_sleep.sh" 2>&1) || true

  if echo "$SLEEP_OUTPUT" | grep -q "PASS:interrupt"; then
    pass "should exit backoff_sleep quickly when interrupted"
  else
    fail "should exit backoff_sleep quickly when interrupted ($(echo "$SLEEP_OUTPUT" | grep "FAIL:interrupt" || echo "function error"))"
  fi
else
  fail "should exit backoff_sleep quickly when interrupted (backoff_sleep function not found)"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

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

echo ""
exit 0
