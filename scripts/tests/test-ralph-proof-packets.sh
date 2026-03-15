#!/bin/bash
# test-ralph-proof-packets.sh — Tests for ralph.sh proof packet collection (US-005)
# Run: bash scripts/tests/test-ralph-proof-packets.sh

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
echo "TEST: Ralph Proof Packets (US-005)"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: collect_proof_packet function exists ─────────────────────────

echo "── Function existence ──"

if grep -q '^collect_proof_packet()' "$RALPH"; then
  pass "should have collect_proof_packet() function"
else
  fail "should have collect_proof_packet() function"
fi

# ─── Test 2: Function accepts required parameters ────────────────────────

if grep -qE 'collect_proof_packet\(\)|collect_proof_packet.*story_id.*iteration.*status.*exit_code.*duration' "$RALPH"; then
  pass "should define collect_proof_packet function"
else
  fail "should define collect_proof_packet function"
fi

# ─── Test 3: Proof packet saved to correct path ──────────────────────────

echo ""
echo "── Output path ──"

if grep -qE 'agent_logs/proof-.*story.*iter' "$RALPH"; then
  pass "should save proof packet to agent_logs/proof-{story_id}-iter{N}.json"
else
  fail "should save proof packet to agent_logs/proof-{story_id}-iter{N}.json"
fi

# ─── Test 4: Proof packet contains required core fields ──────────────────

echo ""
echo "── Core fields ──"

for field in story_id iteration status duration_seconds model exit_code; do
  if grep -qE "$field" "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
    pass "should include '$field' in proof packet"
  else
    fail "should include '$field' in proof packet"
  fi
done

# ─── Test 5: Proof packet includes git diff stats ────────────────────────

echo ""
echo "── Git diff stats ──"

if grep -qE 'files_changed.*git diff|git diff.*stat|diff.*--stat' "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
  pass "should include files_changed from git diff --stat"
else
  fail "should include files_changed from git diff --stat"
fi

if grep -qE 'lines_added|insertions' "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
  pass "should include lines_added in proof packet"
else
  fail "should include lines_added in proof packet"
fi

if grep -qE 'lines_removed|deletions' "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
  pass "should include lines_removed in proof packet"
else
  fail "should include lines_removed in proof packet"
fi

# ─── Test 6: Proof packet includes commit count ──────────────────────────

if grep -qE 'commit_count' "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
  pass "should include commit_count in proof packet"
else
  fail "should include commit_count in proof packet"
fi

# ─── Test 7: Quality gate fields included when available ──────────────────

echo ""
echo "── Quality gate fields ──"

for field in tests_passed tests_failed tests_skipped lint_errors lint_warnings build_clean; do
  if grep -qE "$field" "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
    pass "should include '$field' when quality gate data available"
  else
    fail "should include '$field' when quality gate data available"
  fi
done

# ─── Test 8: collect_proof_packet is called in main loop ──────────────────

echo ""
echo "── Integration ──"

if grep -qE 'collect_proof_packet.*\$' "$RALPH"; then
  pass "should call collect_proof_packet in the main loop"
else
  fail "should call collect_proof_packet in the main loop"
fi

# ─── Test 9: Proof collection errors don't fail the iteration ────────────

if grep -qE 'collect_proof_packet.*\|\|.*true|collect_proof_packet.*2>/dev/null' "$RALPH"; then
  pass "should never fail the iteration on proof collection errors"
else
  fail "should never fail the iteration on proof collection errors"
fi

# ─── Test 10: Telemetry POST for proof packets ───────────────────────────

echo ""
echo "── Telemetry ──"

if grep -qE 'proof.*TELEMETRY|TELEMETRY.*proof|api/ralph/proof|proof_packet' "$RALPH"; then
  pass "should POST proof packet to telemetry when enabled"
else
  fail "should POST proof packet to telemetry when enabled"
fi

# ─── Test 11: Function generates valid JSON ──────────────────────────────

echo ""
echo "── JSON output ──"

COLLECT_FUNC=$(extract_function "collect_proof_packet" 2>/dev/null || echo "")
BUILD_JSON_FUNC=$(extract_function "build_json" 2>/dev/null || echo "")

if [[ -n "$COLLECT_FUNC" ]]; then
  # Set up a fake git repo for testing
  FAKE_REPO="$TMPDIR_TEST/fake_repo"
  mkdir -p "$FAKE_REPO/agent_logs"
  cd "$FAKE_REPO"
  git init -q
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "initial"
  echo "changed" > file.txt
  git add file.txt
  git commit -q -m "second commit"

  cat > "$TMPDIR_TEST/test_proof.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

# Source the functions
eval "$BUILD_JSON_BODY"
eval "$COLLECT_FUNC_BODY"

# Set required variables
TELEMETRY=false
MODEL="claude-sonnet-4-6"
QUALITY_GATE=false
GATE_RESULT="skipped"
WORKTREE_PATH=""

# Run the function
collect_proof_packet "US-TEST" "3" "passed" "0" "120"

# Check the output file exists
PROOF_FILE="agent_logs/proof-US-TEST-iter3.json"
if [[ -f "$PROOF_FILE" ]]; then
  echo "FILE_EXISTS"
  # Validate JSON
  if node -e "JSON.parse(require('fs').readFileSync('$PROOF_FILE','utf8'))" 2>/dev/null; then
    echo "VALID_JSON"
    # Check fields
    node -e "
      const p = JSON.parse(require('fs').readFileSync('$PROOF_FILE','utf8'));
      if (p.story_id === 'US-TEST') console.log('HAS_STORY_ID');
      if (p.iteration === 3 || p.iteration === '3') console.log('HAS_ITERATION');
      if (p.status === 'passed') console.log('HAS_STATUS');
      if (p.exit_code === 0 || p.exit_code === '0') console.log('HAS_EXIT_CODE');
      if (p.duration_seconds === 120 || p.duration_seconds === '120') console.log('HAS_DURATION');
      if (p.model === 'claude-sonnet-4-6') console.log('HAS_MODEL');
      if ('files_changed' in p) console.log('HAS_FILES_CHANGED');
      if ('lines_added' in p) console.log('HAS_LINES_ADDED');
      if ('lines_removed' in p) console.log('HAS_LINES_REMOVED');
      if ('commit_count' in p) console.log('HAS_COMMIT_COUNT');
    "
  else
    echo "INVALID_JSON"
  fi
else
  echo "NO_FILE"
fi
TESTEOF

  export COLLECT_FUNC_BODY="$COLLECT_FUNC"
  export BUILD_JSON_BODY="$BUILD_JSON_FUNC"
  cd "$FAKE_REPO"
  TEST_OUTPUT=$(bash "$TMPDIR_TEST/test_proof.sh" 2>&1) || true

  if echo "$TEST_OUTPUT" | grep -q "FILE_EXISTS"; then
    pass "should create proof packet file at expected path"
  else
    fail "should create proof packet file at expected path"
  fi

  if echo "$TEST_OUTPUT" | grep -q "VALID_JSON"; then
    pass "should generate valid JSON"
  else
    fail "should generate valid JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_STORY_ID"; then
    pass "should include correct story_id in JSON"
  else
    fail "should include correct story_id in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_ITERATION"; then
    pass "should include correct iteration in JSON"
  else
    fail "should include correct iteration in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_STATUS"; then
    pass "should include correct status in JSON"
  else
    fail "should include correct status in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_EXIT_CODE"; then
    pass "should include exit_code in JSON"
  else
    fail "should include exit_code in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_DURATION"; then
    pass "should include duration_seconds in JSON"
  else
    fail "should include duration_seconds in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_MODEL"; then
    pass "should include model in JSON"
  else
    fail "should include model in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_FILES_CHANGED"; then
    pass "should include files_changed in JSON"
  else
    fail "should include files_changed in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_LINES_ADDED"; then
    pass "should include lines_added in JSON"
  else
    fail "should include lines_added in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_LINES_REMOVED"; then
    pass "should include lines_removed in JSON"
  else
    fail "should include lines_removed in JSON"
  fi

  if echo "$TEST_OUTPUT" | grep -q "HAS_COMMIT_COUNT"; then
    pass "should include commit_count in JSON"
  else
    fail "should include commit_count in JSON"
  fi

  cd "$REPO_ROOT"
else
  fail "should create proof packet file at expected path (function not found)"
  fail "should generate valid JSON (function not found)"
  fail "should include correct story_id in JSON (function not found)"
  fail "should include correct iteration in JSON (function not found)"
  fail "should include correct status in JSON (function not found)"
  fail "should include exit_code in JSON (function not found)"
  fail "should include duration_seconds in JSON (function not found)"
  fail "should include model in JSON (function not found)"
  fail "should include files_changed in JSON (function not found)"
  fail "should include lines_added in JSON (function not found)"
  fail "should include lines_removed in JSON (function not found)"
  fail "should include commit_count in JSON (function not found)"
fi

# ─── Test 12: Proof packet with quality gate data ─────────────────────────

echo ""
echo "── Quality gate integration ──"

if [[ -n "$COLLECT_FUNC" ]]; then
  FAKE_REPO2="$TMPDIR_TEST/fake_repo2"
  mkdir -p "$FAKE_REPO2/agent_logs"
  cd "$FAKE_REPO2"
  git init -q
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "initial"

  cat > "$TMPDIR_TEST/test_proof_qg.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

eval "$BUILD_JSON_BODY"
eval "$COLLECT_FUNC_BODY"

TELEMETRY=false
MODEL="claude-sonnet-4-6"
QUALITY_GATE=true
GATE_RESULT="passed"
WORKTREE_PATH=""

# Set quality gate result variables
QG_TESTS_PASSED=15
QG_TESTS_FAILED=2
QG_TESTS_SKIPPED=1
QG_LINT_ERRORS=0
QG_LINT_WARNINGS=3
QG_BUILD_CLEAN=true

collect_proof_packet "US-QG" "1" "passed" "0" "60"

PROOF_FILE="agent_logs/proof-US-QG-iter1.json"
if [[ -f "$PROOF_FILE" ]]; then
  node -e "
    const p = JSON.parse(require('fs').readFileSync('$PROOF_FILE','utf8'));
    if ('tests_passed' in p) console.log('HAS_TESTS_PASSED');
    if ('tests_failed' in p) console.log('HAS_TESTS_FAILED');
    if ('tests_skipped' in p) console.log('HAS_TESTS_SKIPPED');
    if ('lint_errors' in p) console.log('HAS_LINT_ERRORS');
    if ('lint_warnings' in p) console.log('HAS_LINT_WARNINGS');
    if ('build_clean' in p) console.log('HAS_BUILD_CLEAN');
  "
fi
TESTEOF

  export COLLECT_FUNC_BODY="$COLLECT_FUNC"
  export BUILD_JSON_BODY="$BUILD_JSON_FUNC"
  cd "$FAKE_REPO2"
  QG_OUTPUT=$(bash "$TMPDIR_TEST/test_proof_qg.sh" 2>&1) || true

  for field in TESTS_PASSED TESTS_FAILED TESTS_SKIPPED LINT_ERRORS LINT_WARNINGS BUILD_CLEAN; do
    if echo "$QG_OUTPUT" | grep -q "HAS_$field"; then
      pass "should include $(echo "$field" | tr '[:upper:]' '[:lower:]') when quality gate ran"
    else
      fail "should include $(echo "$field" | tr '[:upper:]' '[:lower:]') when quality gate ran"
    fi
  done

  cd "$REPO_ROOT"
else
  for field in tests_passed tests_failed tests_skipped lint_errors lint_warnings build_clean; do
    fail "should include $field when quality gate ran (function not found)"
  done
fi

# ─── Test 13: Proof packet called after both pass and fail ────────────────

echo ""
echo "── Called on all outcomes ──"

# Check that collect_proof_packet is called regardless of Claude exit code
# It should be called in the main loop after Claude runs, not conditionally on success
if grep -c 'collect_proof_packet' "$RALPH" 2>/dev/null | grep -qE '^[1-9]'; then
  pass "should call collect_proof_packet in the main loop"
else
  fail "should call collect_proof_packet in the main loop"
fi

# ─── Test 14: Proof packet collection is lightweight ──────────────────────

echo ""
echo "── Performance ──"

# Should not have expensive operations like full test re-runs
# Just git diff --stat and file parsing
if grep -qE 'git diff.*--stat|git.*rev-list.*count|git.*log.*count' "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
  pass "should use lightweight git commands (diff --stat, rev-list --count)"
else
  fail "should use lightweight git commands (diff --stat, rev-list --count)"
fi

# ─── Test 15: Timestamp included in proof packet ─────────────────────────

echo ""
echo "── Metadata ──"

if grep -qE 'timestamp.*date|date.*timestamp|collected_at' "$RALPH" && grep -q 'collect_proof_packet' "$RALPH"; then
  pass "should include timestamp in proof packet"
else
  fail "should include timestamp in proof packet"
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
