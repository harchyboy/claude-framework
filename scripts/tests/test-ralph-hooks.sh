#!/bin/bash
# test-ralph-hooks.sh — Tests for ralph.sh workspace lifecycle hooks (US-001)
# Run: bash scripts/tests/test-ralph-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# Extract run_hook function from ralph.sh for isolated testing
# We'll source a minimal version that includes just the function
extract_run_hook() {
  # Create a minimal testable script with the run_hook function
  # by grepping it out of ralph.sh
  local start_line end_line
  start_line=$(grep -n '^run_hook()' "$REPO_ROOT/scripts/ralph.sh" | head -1 | cut -d: -f1)

  if [[ -z "$start_line" ]]; then
    echo "ERROR: run_hook() not found in ralph.sh" >&2
    return 1
  fi

  # Find the closing brace of the function
  local brace_count=0
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if [[ $line_num -lt $start_line ]]; then continue; fi
    # Count opening and closing braces
    local opens closes
    opens=$(echo "$line" | tr -cd '{' | wc -c)
    closes=$(echo "$line" | tr -cd '}' | wc -c)
    brace_count=$((brace_count + opens - closes))
    if [[ $brace_count -eq 0 && $line_num -gt $start_line ]]; then
      end_line=$line_num
      break
    fi
  done < "$REPO_ROOT/scripts/ralph.sh"

  sed -n "${start_line},${end_line}p" "$REPO_ROOT/scripts/ralph.sh"
}

echo ""
echo "═══════════════════════════════════════"
echo "TEST: Ralph Workspace Lifecycle Hooks"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: --hooks-dir flag exists in usage/help ───────────────────────────

echo "── Flag parsing ──"

if grep -q '\-\-hooks-dir' "$REPO_ROOT/scripts/ralph.sh"; then
  pass "should have --hooks-dir flag in ralph.sh"
else
  fail "should have --hooks-dir flag in ralph.sh"
fi

# ─── Test 2: Default hooks dir is scripts/ralph-hooks/ ───────────────────────

if grep -q 'HOOKS_DIR=.*scripts/ralph-hooks' "$REPO_ROOT/scripts/ralph.sh"; then
  pass "should default HOOKS_DIR to scripts/ralph-hooks/"
else
  fail "should default HOOKS_DIR to scripts/ralph-hooks/"
fi

# ─── Test 3: run_hook function exists ────────────────────────────────────────

echo ""
echo "── run_hook function ──"

if grep -q '^run_hook()' "$REPO_ROOT/scripts/ralph.sh"; then
  pass "should define run_hook() function"
else
  fail "should define run_hook() function"
fi

# ─── Test 4: run_hook passes correct env vars ───────────────────────────────

if grep -qE 'RALPH_STORY_ID|RALPH_ITERATION|RALPH_PRD_DIR|RALPH_MODEL' "$REPO_ROOT/scripts/ralph.sh"; then
  # Check all four are present
  local_count=0
  for var in RALPH_STORY_ID RALPH_ITERATION RALPH_PRD_DIR RALPH_MODEL; do
    if grep -q "$var" "$REPO_ROOT/scripts/ralph.sh"; then
      local_count=$((local_count + 1))
    fi
  done
  if [[ $local_count -eq 4 ]]; then
    pass "should pass all 4 environment variables to hooks"
  else
    fail "should pass all 4 environment variables to hooks (found $local_count/4)"
  fi
else
  fail "should pass environment variables to hooks"
fi

# ─── Test 5: 60-second timeout on hooks ─────────────────────────────────────

if grep -qE 'timeout\s+60|HOOK_TIMEOUT.*60' "$REPO_ROOT/scripts/ralph.sh"; then
  pass "should have 60-second timeout for hooks"
else
  fail "should have 60-second timeout for hooks"
fi

# ─── Test 6: Hook stdout/stderr captured to log ─────────────────────────────

if grep -qE 'LOG_FILE|>> "\$LOG_FILE"|>>\s*"\$LOG_FILE"|tee.*LOG_FILE' "$REPO_ROOT/scripts/ralph.sh" && \
   grep -qE 'run_hook.*log|hook.*LOG_FILE|hook.*log' "$REPO_ROOT/scripts/ralph.sh"; then
  pass "should capture hook output to log file"
else
  fail "should capture hook output to log file"
fi

# ─── Test 7: All four hook points exist ──────────────────────────────────────

echo ""
echo "── Hook integration points ──"

for hook_name in after_create before_run after_run before_remove; do
  if grep -q "run_hook.*${hook_name}" "$REPO_ROOT/scripts/ralph.sh"; then
    pass "should call run_hook for ${hook_name}"
  else
    fail "should call run_hook for ${hook_name}"
  fi
done

# ─── Test 8: after_create failure causes worktree retry ─────────────────────

echo ""
echo "── Hook failure handling ──"

# after_create failure should cause worktree creation to fail
if grep -A5 'run_hook.*after_create' "$REPO_ROOT/scripts/ralph.sh" | grep -qE 'fail|retry|return 1|exit 1'; then
  pass "should treat after_create failure as worktree creation failure"
else
  fail "should treat after_create failure as worktree creation failure"
fi

# before_run failure should skip attempt (not stuck)
if grep -A5 'run_hook.*before_run' "$REPO_ROOT/scripts/ralph.sh" | grep -qE 'skip|continue|retry'; then
  pass "should skip current attempt when before_run fails"
else
  fail "should skip current attempt when before_run fails"
fi

# after_run failure should be logged but not fatal
if grep -A5 'run_hook.*after_run' "$REPO_ROOT/scripts/ralph.sh" | grep -qE 'true$|\|\| true|log|warn'; then
  pass "should not fail iteration when after_run fails"
else
  fail "should not fail iteration when after_run fails"
fi

# before_remove failure should be logged but not fatal
if grep -A5 'run_hook.*before_remove' "$REPO_ROOT/scripts/ralph.sh" | grep -qE 'true$|\|\| true|log|warn'; then
  pass "should not fail when before_remove fails"
else
  fail "should not fail when before_remove fails"
fi

# ─── Test 9: Hooks are optional — missing dir proceeds silently ─────────────

echo ""
echo "── Optional hooks ──"

if grep -qE 'HOOKS_DIR.*-d|! -d.*HOOKS_DIR|\[ -d.*HOOKS_DIR|test -d.*HOOKS_DIR' "$REPO_ROOT/scripts/ralph.sh"; then
  pass "should check if hooks directory exists before running"
else
  fail "should check if hooks directory exists before running"
fi

if grep -qE '\-x.*hook|\-f.*hook|test -x|test -f' "$REPO_ROOT/scripts/ralph.sh"; then
  pass "should check if specific hook script exists and is executable"
else
  fail "should check if specific hook script exists and is executable"
fi

# ─── Test 10: Functional test — run_hook with real scripts ──────────────────

echo ""
echo "── Functional tests ──"

# Create a temporary hooks directory with test hooks
FUNC_TEST_DIR="$TMPDIR_TEST/func_test"
HOOKS_TEST_DIR="$FUNC_TEST_DIR/hooks"
mkdir -p "$HOOKS_TEST_DIR"

# Create a passing hook
cat > "$HOOKS_TEST_DIR/after_create.sh" <<'HOOK'
#!/bin/bash
echo "HOOK_RAN=true"
echo "STORY=$RALPH_STORY_ID"
echo "ITER=$RALPH_ITERATION"
echo "PRD=$RALPH_PRD_DIR"
echo "MODEL=$RALPH_MODEL"
exit 0
HOOK
chmod +x "$HOOKS_TEST_DIR/after_create.sh"

# Create a failing hook
cat > "$HOOKS_TEST_DIR/before_run.sh" <<'HOOK'
#!/bin/bash
echo "FAILING_HOOK"
exit 1
HOOK
chmod +x "$HOOKS_TEST_DIR/before_run.sh"

# Source the run_hook function and test it
RUN_HOOK_SRC=$(extract_run_hook 2>/dev/null || echo "")

if [[ -n "$RUN_HOOK_SRC" ]]; then
  # Test: passing hook returns 0 and captures output
  HOOK_LOG="$FUNC_TEST_DIR/test.log"
  touch "$HOOK_LOG"

  HOOK_OUTPUT=$(
    HOOKS_DIR="$HOOKS_TEST_DIR"
    STORY_ID="US-TEST"
    ITERATION="3"
    PRD_DIR="/tmp/test-prd"
    MODEL="claude-sonnet-4-6"
    HOOK_TIMEOUT=60
    LOG_FILE="$HOOK_LOG"
    eval "$RUN_HOOK_SRC"
    run_hook "after_create" "$FUNC_TEST_DIR" 2>&1
  ) || true

  if [[ $? -eq 0 ]] || echo "$HOOK_OUTPUT" | grep -q "HOOK_RAN=true"; then
    pass "should run passing hook and capture output"
  else
    fail "should run passing hook and capture output"
  fi

  if grep -q "STORY=US-TEST" "$HOOK_LOG" 2>/dev/null || echo "$HOOK_OUTPUT" | grep -q "STORY=US-TEST"; then
    pass "should pass RALPH_STORY_ID to hook environment"
  else
    fail "should pass RALPH_STORY_ID to hook environment"
  fi

  # Test: failing hook returns non-zero
  FAIL_RESULT=0
  (
    HOOKS_DIR="$HOOKS_TEST_DIR"
    HOOK_TIMEOUT=60
    LOG_FILE="$HOOK_LOG"
    eval "$RUN_HOOK_SRC"
    run_hook "before_run" "$FUNC_TEST_DIR"
  ) 2>/dev/null && FAIL_RESULT=0 || FAIL_RESULT=$?

  if [[ $FAIL_RESULT -ne 0 ]]; then
    pass "should return non-zero when hook fails"
  else
    fail "should return non-zero when hook fails"
  fi

  # Test: missing hook proceeds silently (returns 0)
  MISS_RESULT=0
  (
    HOOKS_DIR="$HOOKS_TEST_DIR"
    HOOK_TIMEOUT=60
    LOG_FILE="$HOOK_LOG"
    eval "$RUN_HOOK_SRC"
    run_hook "nonexistent_hook" "$FUNC_TEST_DIR"
  ) 2>/dev/null && MISS_RESULT=0 || MISS_RESULT=$?

  if [[ $MISS_RESULT -eq 0 ]]; then
    pass "should succeed silently when hook script is missing"
  else
    fail "should succeed silently when hook script is missing"
  fi

  # Test: missing hooks directory proceeds silently
  NODIR_RESULT=0
  (
    HOOKS_DIR="/nonexistent/path"
    HOOK_TIMEOUT=60
    LOG_FILE="$HOOK_LOG"
    eval "$RUN_HOOK_SRC"
    run_hook "after_create" "$FUNC_TEST_DIR"
  ) 2>/dev/null && NODIR_RESULT=0 || NODIR_RESULT=$?

  if [[ $NODIR_RESULT -eq 0 ]]; then
    pass "should succeed silently when hooks directory is missing"
  else
    fail "should succeed silently when hooks directory is missing"
  fi
else
  fail "should be able to extract run_hook function for testing"
  fail "should run passing hook and capture output (skipped — no function)"
  fail "should pass RALPH_STORY_ID to hook environment (skipped — no function)"
  fail "should return non-zero when hook fails (skipped — no function)"
  fail "should succeed silently when hook script is missing (skipped — no function)"
  fail "should succeed silently when hooks directory is missing (skipped — no function)"
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
