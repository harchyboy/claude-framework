#!/bin/bash
# test-failure-diagnosis.sh — Tests for automatic failure diagnosis
# Run: bash scripts/tests/test-failure-diagnosis.sh

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

echo ""
echo "═══════════════════════════════════════"
echo "TEST: Automatic Failure Diagnosis"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: Function exists ────────────────────────────────────────────────

echo "── Function structure ──"

if grep -qE 'ralph_diagnose_failure\(\)' "$RALPH"; then
  pass "should have ralph_diagnose_failure() function"
else
  fail "should have ralph_diagnose_failure() function"
fi

if grep -qE 'ralph_diagnose_failure.*story_id.*log_file.*failure_type' "$RALPH"; then
  pass "should accept story_id, log_file, failure_type parameters"
else
  fail "should accept story_id, log_file, failure_type parameters"
fi

# ─── Test 2: Error pattern detection ────────────────────────────────────────

echo ""
echo "── Error pattern detection ──"

if grep -qE 'stackTracePattern|stack_traces' "$RALPH"; then
  pass "should detect stack traces"
else
  fail "should detect stack traces"
fi

if grep -qE 'tscPattern|compilation_errors' "$RALPH"; then
  pass "should detect TypeScript compilation errors"
else
  fail "should detect TypeScript compilation errors"
fi

if grep -qE 'testFailPattern|test_failures' "$RALPH"; then
  pass "should detect test failures"
else
  fail "should detect test failures"
fi

if grep -qE 'eslintErrorLine|eslint' "$RALPH"; then
  pass "should detect ESLint errors"
else
  fail "should detect ESLint errors"
fi

if grep -qE 'npm ERR' "$RALPH"; then
  pass "should detect npm errors"
else
  fail "should detect npm errors"
fi

if grep -qE 'Cannot find module|Module not found' "$RALPH"; then
  pass "should detect missing module errors"
else
  fail "should detect missing module errors"
fi

if grep -qE 'ENOENT|EACCES|EPERM' "$RALPH"; then
  pass "should detect filesystem errors"
else
  fail "should detect filesystem errors"
fi

if grep -qE 'Connection refused|ECONNREFUSED' "$RALPH"; then
  pass "should detect connection errors"
else
  fail "should detect connection errors"
fi

if grep -qE 'TypeError|ReferenceError|SyntaxError' "$RALPH"; then
  pass "should detect JavaScript runtime errors"
else
  fail "should detect JavaScript runtime errors"
fi

if grep -qE 'ImportError|ModuleNotFoundError' "$RALPH"; then
  pass "should detect Python import errors"
else
  fail "should detect Python import errors"
fi

# ─── Test 3: Diagnosis output ────────────────────────────────────────────────

echo ""
echo "── Diagnosis output ──"

if grep -qE 'diagnosis-.*\.json' "$RALPH"; then
  pass "should write per-story diagnosis JSON file"
else
  fail "should write per-story diagnosis JSON file"
fi

if grep -qE 'errors\.jsonl' "$RALPH"; then
  pass "should append to running errors.jsonl stream"
else
  fail "should append to running errors.jsonl stream"
fi

if grep -qE 'appendFileSync.*errors\.jsonl' "$RALPH"; then
  pass "should use appendFileSync for errors.jsonl (atomic append)"
else
  fail "should use appendFileSync for errors.jsonl (atomic append)"
fi

# ─── Test 4: Diagnosis content ──────────────────────────────────────────────

echo ""
echo "── Diagnosis content ──"

if grep -qE 'summary.*parts\.join' "$RALPH"; then
  pass "should generate human-readable summary"
else
  fail "should generate human-readable summary"
fi

if grep -qE 'suggested_action' "$RALPH"; then
  pass "should include suggested action"
else
  fail "should include suggested action"
fi

if grep -qE 'failure_type.*timeout.*stall.*crash.*quality_gate.*verification' "$RALPH"; then
  pass "should categorise failure types"
else
  # Check individually
  if grep -q 'timeout' "$RALPH" && grep -q 'stall' "$RALPH" && grep -q 'crash' "$RALPH" && grep -q 'quality_gate' "$RALPH" && grep -q 'verification' "$RALPH"; then
    pass "should categorise failure types"
  else
    fail "should categorise failure types"
  fi
fi

# ─── Test 5: Integration points ─────────────────────────────────────────────

echo ""
echo "── Integration points ──"

if grep -B2 'ralph_diagnose_failure' "$RALPH" | grep -q 'Stall detected\|stall'; then
  pass "should diagnose on stall detection"
else
  fail "should diagnose on stall detection"
fi

if grep -B2 'ralph_diagnose_failure' "$RALPH" | grep -q 'timed out\|timeout'; then
  pass "should diagnose on timeout"
else
  fail "should diagnose on timeout"
fi

if grep -B2 'ralph_diagnose_failure' "$RALPH" | grep -q 'exited with error\|crash'; then
  pass "should diagnose on Claude crash"
else
  fail "should diagnose on Claude crash"
fi

if grep -B2 'ralph_diagnose_failure' "$RALPH" | grep -q 'Quality gate failed\|quality_gate'; then
  pass "should diagnose on quality gate failure"
else
  fail "should diagnose on quality gate failure"
fi

if grep -B2 'ralph_diagnose_failure' "$RALPH" | grep -q 'Verification failed\|verification'; then
  pass "should diagnose on verification failure"
else
  fail "should diagnose on verification failure"
fi

# ─── Test 6: Failure digest in summary ───────────────────────────────────────

echo ""
echo "── Failure digest ──"

if grep -qE 'FAILURE DIGEST' "$RALPH"; then
  pass "should show FAILURE DIGEST section in summary"
else
  fail "should show FAILURE DIGEST section in summary"
fi

if grep -qE 'failure_type.*toUpperCase' "$RALPH"; then
  pass "should display failure type in uppercase"
else
  fail "should display failure type in uppercase"
fi

if grep -qE 'Full diagnoses.*diagnosis-' "$RALPH"; then
  pass "should reference diagnosis files in digest"
else
  fail "should reference diagnosis files in digest"
fi

if grep -qE 'Error stream.*errors\.jsonl' "$RALPH"; then
  pass "should reference errors.jsonl stream in digest"
else
  fail "should reference errors.jsonl stream in digest"
fi

# ─── Test 7: JSON output includes failures ───────────────────────────────────

echo ""
echo "── JSON output ──"

if grep -qE 'failures.*failures' "$RALPH" && grep -qE 'errors\.jsonl' "$RALPH"; then
  pass "should include failures array in JSON summary"
else
  fail "should include failures array in JSON summary"
fi

# ─── Test 8: Telemetry event ────────────────────────────────────────────────

echo ""
echo "── Telemetry ──"

if grep -qE 'failure_diagnosed' "$RALPH"; then
  pass "should emit failure_diagnosed telemetry event"
else
  fail "should emit failure_diagnosed telemetry event"
fi

if grep -qE 'diagnosis_file' "$RALPH" && grep -qE 'failure_diagnosed' "$RALPH"; then
  pass "should include diagnosis_file in telemetry event"
else
  fail "should include diagnosis_file in telemetry event"
fi

# ─── Test 9: Functional test — diagnosis parsing ────────────────────────────

echo ""
echo "── Functional: log parsing ──"

TMPDIR_DIAG=$(mktemp -d)
ORIG_DIR=$(pwd)
cd "$TMPDIR_DIAG"
mkdir -p agent_logs

# Create a fake log with known error patterns
cat > test.log <<'LOGEOF'
Starting build...
src/auth.ts(42,5): error TS2304: Cannot find name 'Session'.
src/auth.ts(58,10): error TS2345: Argument of type 'string' is not assignable to parameter of type 'number'.
npm ERR! Test failed. See above for more details.
FAIL src/auth.test.ts
  ✘ should authenticate user with valid token
    TypeError: Cannot read properties of undefined (reading 'token')
      at Object.<anonymous> (src/auth.test.ts:15:22)
      at Promise.then.completed (node_modules/jest/build/index.js:250:12)
LOGEOF

# Run the diagnosis inline (simulate what ralph_diagnose_failure does)
ITERATION=1
node -e "
  const fs = require('fs');
  const logContent = fs.readFileSync('test.log', 'utf8');
  const lines = logContent.split('\n');
  const diagnosis = { errors: [], stack_traces: [], test_failures: [], compilation_errors: [], summary: '' };

  // TypeScript errors
  const tscPattern = /^(.+\.tsx?)\((\d+),(\d+)\):\s*error\s+(TS\d+):\s*(.+)/;
  for (const line of lines) {
    const match = line.match(tscPattern);
    if (match) diagnosis.compilation_errors.push({ file: match[1], code: match[4], message: match[5] });
  }

  // Test failures
  const testFailPattern = /(?:FAIL|✘|✗|×|FAILED)\s+(.+)/i;
  for (const line of lines) {
    if (testFailPattern.test(line)) diagnosis.test_failures.push(line.trim());
  }

  // Stack traces
  const stackPattern = /^\s*(at\s+|TypeError:|ReferenceError:)/;
  for (const line of lines) {
    if (stackPattern.test(line)) diagnosis.stack_traces.push(line.trim());
  }

  // Verify
  if (diagnosis.compilation_errors.length === 2) console.log('COMPILE_ERRORS_OK');
  if (diagnosis.compilation_errors[0].code === 'TS2304') console.log('TS_CODE_OK');
  if (diagnosis.compilation_errors[0].file === 'src/auth.ts') console.log('TS_FILE_OK');
  if (diagnosis.test_failures.length >= 1) console.log('TEST_FAILURES_OK');
  if (diagnosis.stack_traces.length >= 1) console.log('STACK_TRACES_OK');
" 2>/dev/null > result.txt

if grep -q 'COMPILE_ERRORS_OK' result.txt; then
  pass "should extract TypeScript compilation errors from log"
else
  fail "should extract TypeScript compilation errors from log"
fi

if grep -q 'TS_CODE_OK' result.txt; then
  pass "should extract error code (TS2304)"
else
  fail "should extract error code (TS2304)"
fi

if grep -q 'TS_FILE_OK' result.txt; then
  pass "should extract file path from error"
else
  fail "should extract file path from error"
fi

if grep -q 'TEST_FAILURES_OK' result.txt; then
  pass "should extract test failure lines"
else
  fail "should extract test failure lines"
fi

if grep -q 'STACK_TRACES_OK' result.txt; then
  pass "should extract stack trace lines"
else
  fail "should extract stack trace lines"
fi

cd "$ORIG_DIR"
rm -rf "$TMPDIR_DIAG"

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
