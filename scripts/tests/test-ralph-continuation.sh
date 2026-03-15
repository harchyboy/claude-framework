#!/bin/bash
# test-ralph-continuation.sh — Tests for ralph.sh continuation prompts (US-002)
# Run: bash scripts/tests/test-ralph-continuation.sh

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

echo ""
echo "═══════════════════════════════════════"
echo "TEST: Ralph Continuation Prompts"
echo "═══════════════════════════════════════"
echo ""

# ─── Helper: extract function from ralph.sh ──────────────────────────────────

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

# ─── Test 1: build_continuation_prompt function exists ───────────────────────

echo "── Function definition ──"

if grep -q '^build_continuation_prompt()' "$RALPH"; then
  pass "should define build_continuation_prompt() function"
else
  fail "should define build_continuation_prompt() function"
fi

# ─── Test 2: build_iteration_prompt still exists (not replaced) ──────────────

if grep -q '^build_iteration_prompt()' "$RALPH"; then
  pass "should retain build_iteration_prompt() function"
else
  fail "should retain build_iteration_prompt() function"
fi

# ─── Test 3: Continuation prompt includes story ID ──────────────────────────

echo ""
echo "── Continuation prompt content ──"

CONT_SRC=$(extract_function "build_continuation_prompt" 2>/dev/null || echo "")

if [[ -n "$CONT_SRC" ]]; then
  if echo "$CONT_SRC" | grep -qE 'STORY_ID|story_id|story ID'; then
    pass "should include story ID in continuation prompt"
  else
    fail "should include story ID in continuation prompt"
  fi
else
  fail "should include story ID in continuation prompt (function not found)"
fi

# ─── Test 4: Continuation prompt includes acceptance criteria ────────────────

if [[ -n "$CONT_SRC" ]]; then
  if echo "$CONT_SRC" | grep -qiE 'acceptanceCriteria|acceptance.criteria|criteria'; then
    pass "should include acceptance criteria in continuation prompt"
  else
    fail "should include acceptance criteria in continuation prompt"
  fi
else
  fail "should include acceptance criteria in continuation prompt (function not found)"
fi

# ─── Test 5: Continuation prompt includes last 50 lines of previous log ─────

if [[ -n "$CONT_SRC" ]]; then
  if echo "$CONT_SRC" | grep -qE 'tail.*50|50.*tail|PREV_LOG|prev_log|last.*log|log.*tail'; then
    pass "should include last 50 lines of previous attempt's log"
  else
    fail "should include last 50 lines of previous attempt's log"
  fi
else
  fail "should include last 50 lines of previous attempt's log (function not found)"
fi

# ─── Test 6: Continuation prompt does NOT include full AGENT_PROMPT.md ───────

if [[ -n "$CONT_SRC" ]]; then
  if echo "$CONT_SRC" | grep -qE 'AGENT_PROMPT|agent_prompt'; then
    fail "should NOT include AGENT_PROMPT.md in continuation prompt"
  else
    pass "should NOT include AGENT_PROMPT.md in continuation prompt"
  fi
else
  fail "should NOT include AGENT_PROMPT.md in continuation prompt (function not found)"
fi

# ─── Test 7: Continuation prompt written to /tmp/ralph_continuation_$$.md ────

echo ""
echo "── Prompt file handling ──"

if grep -qE 'ralph_continuation_\$\$\.md|ralph_continuation_' "$RALPH"; then
  pass "should write continuation prompt to /tmp/ralph_continuation_$$.md"
else
  fail "should write continuation prompt to /tmp/ralph_continuation_$$.md"
fi

# ─── Test 8: Decision is logged (full vs continuation) ──────────────────────

echo ""
echo "── Prompt selection logging ──"

if grep -qE 'Using full prompt' "$RALPH"; then
  pass "should log 'Using full prompt' for first attempts"
else
  fail "should log 'Using full prompt' for first attempts"
fi

if grep -qE 'Using continuation prompt.*retry' "$RALPH"; then
  pass "should log 'Using continuation prompt (retry #N)' for retries"
else
  fail "should log 'Using continuation prompt (retry #N)' for retries"
fi

# ─── Test 9: Retry tracking — Ralph detects retry vs new story ──────────────

echo ""
echo "── Retry detection ──"

# The main loop should check if current story == last story to decide prompt type
if grep -qE 'LAST_STORY|CONSECUTIVE_SAME|IS_RETRY|is_retry' "$RALPH"; then
  pass "should track whether current iteration is a retry"
else
  fail "should track whether current iteration is a retry"
fi

# ─── Test 10: PROMPT_FILE set to continuation file on retry ─────────────────

# Verify the prompt file path switches between full and continuation
if grep -qE 'PROMPT_FILE.*continuation|continuation.*PROMPT_FILE' "$RALPH"; then
  pass "should set PROMPT_FILE to continuation file on retry"
else
  fail "should set PROMPT_FILE to continuation file on retry"
fi

# ─── Test 11: Continuation prompt includes retry instruction ────────────────

echo ""
echo "── Continuation prompt instructions ──"

if [[ -n "$CONT_SRC" ]]; then
  if echo "$CONT_SRC" | grep -qiE 'retry|fix.*remaining|previous attempt|failed'; then
    pass "should include retry/fix instruction in continuation prompt"
  else
    fail "should include retry/fix instruction in continuation prompt"
  fi
else
  fail "should include retry/fix instruction in continuation prompt (function not found)"
fi

# ─── Test 12: Existing flags still work (--skip-preflight etc) ──────────────

echo ""
echo "── Flag compatibility ──"

# Verify --skip-preflight and other existing flags are still parsed
if grep -qE '\-\-skip-preflight.*SKIP_PREFLIGHT|SKIP_PREFLIGHT.*skip-preflight' "$RALPH"; then
  pass "should still support --skip-preflight flag"
else
  fail "should still support --skip-preflight flag"
fi

# ─── Test 13: Functional test — build_continuation_prompt output ─────────────

echo ""
echo "── Functional tests ──"

if [[ -n "$CONT_SRC" ]]; then
  # Set up minimal environment and call the function
  FUNC_TEST_DIR="$TMPDIR_TEST/func_cont"
  mkdir -p "$FUNC_TEST_DIR/agent_logs"
  PRD_DIR="$FUNC_TEST_DIR"

  # Create a minimal prd.json
  cat > "$FUNC_TEST_DIR/prd.json" <<'JSON'
{
  "project": "TestProject",
  "branchName": "test-branch",
  "description": "Test PRD",
  "userStories": [
    {
      "id": "US-TEST",
      "title": "Test Story",
      "description": "A test story for continuation prompts",
      "acceptanceCriteria": [
        "First criterion",
        "Second criterion",
        "Third criterion"
      ],
      "filesInScope": ["test.sh"],
      "priority": 1,
      "passes": false
    }
  ]
}
JSON

  # Create a fake previous log
  PREV_LOG="$FUNC_TEST_DIR/agent_logs/iteration_1_abc123.log"
  for i in $(seq 1 60); do
    echo "Log line $i: doing work on the story" >> "$PREV_LOG"
  done

  # Extract and run the function
  PROMPT_OUTPUT=$(
    STORY_ID="US-TEST"
    ITERATION=2
    CONSECUTIVE_SAME=1
    PRD_DIR="$FUNC_TEST_DIR"
    PREV_LOG_FILE="$PREV_LOG"
    eval "$CONT_SRC"
    build_continuation_prompt
  ) 2>/dev/null || PROMPT_OUTPUT=""

  if [[ -n "$PROMPT_OUTPUT" ]]; then
    # Check it contains the story ID
    if echo "$PROMPT_OUTPUT" | grep -q "US-TEST"; then
      pass "should output story ID in continuation prompt"
    else
      fail "should output story ID in continuation prompt"
    fi

    # Check it contains acceptance criteria
    if echo "$PROMPT_OUTPUT" | grep -q "First criterion"; then
      pass "should output acceptance criteria in continuation prompt"
    else
      fail "should output acceptance criteria in continuation prompt"
    fi

    # Check it contains log tail
    if echo "$PROMPT_OUTPUT" | grep -q "Log line"; then
      pass "should include previous log lines in continuation prompt"
    else
      fail "should include previous log lines in continuation prompt"
    fi

    # Check it's shorter than the full prompt would be (rough check)
    CONT_LENGTH=${#PROMPT_OUTPUT}
    if [[ $CONT_LENGTH -lt 5000 ]]; then
      pass "should produce a shorter prompt than full prompt (${CONT_LENGTH} chars)"
    else
      fail "should produce a shorter prompt than full prompt (${CONT_LENGTH} chars — expected <5000)"
    fi
  else
    fail "should output story ID in continuation prompt (no output)"
    fail "should output acceptance criteria in continuation prompt (no output)"
    fail "should include previous log lines in continuation prompt (no output)"
    fail "should produce a shorter prompt than full prompt (no output)"
  fi
else
  fail "should output story ID in continuation prompt (function not found)"
  fail "should output acceptance criteria in continuation prompt (function not found)"
  fail "should include previous log lines in continuation prompt (function not found)"
  fail "should produce a shorter prompt than full prompt (function not found)"
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
