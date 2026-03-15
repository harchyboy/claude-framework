#!/bin/bash
# test-ralph-dynamic-config.sh — Tests for ralph.sh dynamic config reload (US-006)
# Run: bash scripts/tests/test-ralph-dynamic-config.sh

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
echo "TEST: Ralph Dynamic Config Reload (US-006)"
echo "═══════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Section 1: Function existence and structure
# ═══════════════════════════════════════════════════════════════════════════════

echo "── Function existence ──"

# Test 1: load_dynamic_config function exists
if grep -q '^load_dynamic_config()' "$RALPH"; then
  pass "should have load_dynamic_config() function"
else
  fail "should have load_dynamic_config() function"
fi

# Test 2: CONFIG_LAST_MTIME variable exists for tracking file changes
if grep -qE 'CONFIG_LAST_MTIME' "$RALPH"; then
  pass "should have CONFIG_LAST_MTIME variable for tracking changes"
else
  fail "should have CONFIG_LAST_MTIME variable for tracking changes"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 2: Config file location
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Config file location ──"

# Test 3: Checks for ralph-config.json in PRD directory
if grep -qE 'ralph-config\.json' "$RALPH"; then
  pass "should reference ralph-config.json config file"
else
  fail "should reference ralph-config.json config file"
fi

# Test 4: Config file path uses PRD_DIR
if grep -qE 'PRD_DIR.*ralph-config|ralph-config.*PRD_DIR' "$RALPH"; then
  pass "should look for ralph-config.json in PRD directory"
else
  fail "should look for ralph-config.json in PRD directory"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 3: Reloadable settings
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Reloadable settings ──"

# Test 5: model is reloadable
if grep -qE 'load_dynamic_config|RELOADABLE' "$RALPH" && grep -qE '"model"' "$RALPH"; then
  pass "should support reloading model setting"
else
  fail "should support reloading model setting"
fi

# Test 6: timeout is reloadable
if grep -qE '"timeout"' "$RALPH" && grep -q 'load_dynamic_config' "$RALPH"; then
  pass "should support reloading timeout setting"
else
  fail "should support reloading timeout setting"
fi

# Test 7: quality_gate is reloadable
if grep -qE '"quality_gate"' "$RALPH" && grep -q 'load_dynamic_config' "$RALPH"; then
  pass "should support reloading quality_gate setting"
else
  fail "should support reloading quality_gate setting"
fi

# Test 8: strict is reloadable
if grep -qE '"strict"' "$RALPH" && grep -q 'load_dynamic_config' "$RALPH"; then
  pass "should support reloading strict setting"
else
  fail "should support reloading strict setting"
fi

# Test 9: skip_tests is reloadable
if grep -qE '"skip_tests"' "$RALPH" && grep -q 'load_dynamic_config' "$RALPH"; then
  pass "should support reloading skip_tests setting"
else
  fail "should support reloading skip_tests setting"
fi

# Test 10: review is reloadable
if grep -qE '"review"' "$RALPH" && grep -q 'load_dynamic_config' "$RALPH"; then
  pass "should support reloading review setting"
else
  fail "should support reloading review setting"
fi

# Test 11: max_cost is reloadable
if grep -qE '"max_cost"' "$RALPH" && grep -q 'load_dynamic_config' "$RALPH"; then
  pass "should support reloading max_cost setting"
else
  fail "should support reloading max_cost setting"
fi

# Test 12: stall_timeout is reloadable
if grep -qE '"stall_timeout"' "$RALPH" && grep -q 'load_dynamic_config' "$RALPH"; then
  pass "should support reloading stall_timeout setting"
else
  fail "should support reloading stall_timeout setting"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 4: Non-reloadable settings (set at launch only)
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Non-reloadable settings ──"

# Test 13: Documents non-reloadable settings
if grep -qE 'telemetry|hooks_dir|docker' "$RALPH" && grep -qE 'non.reloadable|launch.only|NON_RELOADABLE|not reloadable' "$RALPH"; then
  pass "should document non-reloadable settings (telemetry, hooks_dir, docker)"
else
  fail "should document non-reloadable settings (telemetry, hooks_dir, docker)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 5: Change detection (mtime-based)
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Change detection ──"

# Test 14: Uses file mtime for change detection
if grep -qE 'stat.*ralph-config|mtime.*config|config.*mtime|CONFIG_LAST_MTIME' "$RALPH"; then
  pass "should use mtime to detect config file changes"
else
  fail "should use mtime to detect config file changes"
fi

# Test 15: Skips reload if file hasn't changed
if grep -qE 'CONFIG_LAST_MTIME.*==.*current_mtime|mtime.*unchanged|same.*mtime|CONFIG_LAST_MTIME.*-eq' "$RALPH"; then
  pass "should skip reload if config file mtime unchanged"
else
  fail "should skip reload if config file mtime unchanged"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 6: Logging
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Logging ──"

# Test 16: Logs config changes with old and new values
if grep -qE 'Config reloaded|config.*changed|changed.*from.*to' "$RALPH"; then
  pass "should log config changes with details"
else
  fail "should log config changes with details"
fi

# Test 17: Logs warning on malformed config
if grep -qE 'malformed|invalid.*config|parse.*error|Config.*warning|keeping previous' "$RALPH"; then
  pass "should log warning when config file is malformed"
else
  fail "should log warning when config file is malformed"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 7: Graceful handling of missing/malformed config
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Error handling ──"

# Test 18: No error when ralph-config.json doesn't exist
if grep -qE '! -f.*ralph-config|! -f.*config_file|ralph-config.*not.*exist|config.*missing' "$RALPH"; then
  pass "should handle missing ralph-config.json gracefully (no error)"
else
  fail "should handle missing ralph-config.json gracefully (no error)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 8: Functional tests — load_dynamic_config behaviour
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Functional: config reload behaviour ──"

LOAD_FUNC=$(extract_function "load_dynamic_config" 2>/dev/null || echo "")

if [[ -n "$LOAD_FUNC" ]]; then

  # Test 19: No config file — function returns 0 (success, no-op)
  cat > "$TMPDIR_TEST/test_no_config.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

# Provide required variables
PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE=""
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config
exit_code=$?

if [[ $exit_code -eq 0 ]]; then
  echo "PASS:no_config"
else
  echo "FAIL:no_config:exit=$exit_code"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/empty_prd"
  mkdir -p "$TEST_PRD_DIR"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_no_config.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:no_config"; then
    pass "should return success when ralph-config.json doesn't exist"
  else
    fail "should return success when ralph-config.json doesn't exist ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

  # Test 20: Valid config file — updates MODEL_OVERRIDE
  cat > "$TMPDIR_TEST/test_model_reload.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE="claude-sonnet-4-6"
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config

if [[ "$MODEL_OVERRIDE" == "claude-opus-4-6" ]]; then
  echo "PASS:model_reload"
else
  echo "FAIL:model_reload:got=$MODEL_OVERRIDE"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/model_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{"model": "claude-opus-4-6"}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_model_reload.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:model_reload"; then
    pass "should update MODEL_OVERRIDE when model changes in config"
  else
    fail "should update MODEL_OVERRIDE when model changes in config ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

  # Test 21: Valid config file — updates ITER_TIMEOUT
  cat > "$TMPDIR_TEST/test_timeout_reload.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE=""
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config

if [[ "$ITER_TIMEOUT" -eq 45 ]]; then
  echo "PASS:timeout"
else
  echo "FAIL:timeout:got=$ITER_TIMEOUT"
fi

if [[ "$TIMEOUT_SECONDS" -eq 2700 ]]; then
  echo "PASS:timeout_seconds"
else
  echo "FAIL:timeout_seconds:got=$TIMEOUT_SECONDS"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/timeout_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{"timeout": 45}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_timeout_reload.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:timeout"; then
    pass "should update ITER_TIMEOUT when timeout changes in config"
  else
    fail "should update ITER_TIMEOUT when timeout changes in config ($(echo "$OUTPUT" | grep "FAIL:timeout" || echo "function error: $OUTPUT"))"
  fi

  if echo "$OUTPUT" | grep -q "PASS:timeout_seconds"; then
    pass "should recalculate TIMEOUT_SECONDS when timeout changes"
  else
    fail "should recalculate TIMEOUT_SECONDS when timeout changes ($(echo "$OUTPUT" | grep "FAIL:timeout_seconds" || echo "function error: $OUTPUT"))"
  fi

  # Test 22: Valid config file — updates boolean settings
  cat > "$TMPDIR_TEST/test_bool_reload.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE=""
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config

PASS_COUNT=0
FAIL_LIST=""

if [[ "$QUALITY_GATE" == "true" ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}quality_gate=$QUALITY_GATE "; fi
if [[ "$STRICT" == "true" ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}strict=$STRICT "; fi
if [[ "$SKIP_TESTS" == "true" ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}skip_tests=$SKIP_TESTS "; fi
if [[ "$REVIEW" == "true" ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}review=$REVIEW "; fi

if [[ $PASS_COUNT -eq 4 ]]; then
  echo "PASS:booleans"
else
  echo "FAIL:booleans:${FAIL_LIST}"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/bool_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{"quality_gate": true, "strict": true, "skip_tests": true, "review": true}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_bool_reload.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:booleans"; then
    pass "should update boolean settings (quality_gate, strict, skip_tests, review)"
  else
    fail "should update boolean settings ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

  # Test 23: Malformed JSON — keeps previous config
  cat > "$TMPDIR_TEST/test_malformed.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE="claude-sonnet-4-6"
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config

if [[ "$MODEL_OVERRIDE" == "claude-sonnet-4-6" ]] && [[ "$ITER_TIMEOUT" -eq 30 ]]; then
  echo "PASS:malformed"
else
  echo "FAIL:malformed:model=$MODEL_OVERRIDE timeout=$ITER_TIMEOUT"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/malformed_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{broken json!!!}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_malformed.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:malformed"; then
    pass "should keep previous config when ralph-config.json is malformed"
  else
    fail "should keep previous config when ralph-config.json is malformed ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

  # Test 24: Skips reload if mtime unchanged
  cat > "$TMPDIR_TEST/test_mtime_skip.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE="claude-sonnet-4-6"
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5

# Get the current mtime and pre-set it (simulating already-loaded config)
CONFIG_FILE="$PRD_DIR/ralph-config.json"
if [[ "$(uname -s)" == "Darwin" ]]; then
  CONFIG_LAST_MTIME=$(stat -f %m "$CONFIG_FILE" 2>/dev/null || echo "0")
else
  CONFIG_LAST_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || date -r "$CONFIG_FILE" +%s 2>/dev/null || echo "0")
fi

eval "$FUNC_BODY"

# Call load — should skip because mtime hasn't changed
load_dynamic_config

# Model should NOT have changed since we pre-set the mtime
if [[ "$MODEL_OVERRIDE" == "claude-sonnet-4-6" ]]; then
  echo "PASS:mtime_skip"
else
  echo "FAIL:mtime_skip:model=$MODEL_OVERRIDE"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/mtime_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{"model": "claude-opus-4-6"}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_mtime_skip.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:mtime_skip"; then
    pass "should skip reload when config file mtime is unchanged"
  else
    fail "should skip reload when config file mtime is unchanged ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

  # Test 25: max_cost reloading
  cat > "$TMPDIR_TEST/test_maxcost.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE=""
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config

if [[ "$MAX_COST" == "50" ]]; then
  echo "PASS:max_cost"
else
  echo "FAIL:max_cost:got=$MAX_COST"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/maxcost_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{"max_cost": 50}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_maxcost.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:max_cost"; then
    pass "should update MAX_COST when max_cost changes in config"
  else
    fail "should update MAX_COST when max_cost changes in config ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

  # Test 26: stall_timeout reloading
  cat > "$TMPDIR_TEST/test_stall.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE=""
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config

if [[ "$STALL_TIMEOUT" -eq 10 ]]; then
  echo "PASS:stall_timeout"
else
  echo "FAIL:stall_timeout:got=$STALL_TIMEOUT"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/stall_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{"stall_timeout": 10}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_stall.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:stall_timeout"; then
    pass "should update STALL_TIMEOUT when stall_timeout changes in config"
  else
    fail "should update STALL_TIMEOUT when stall_timeout changes in config ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

  # Test 27: Multiple settings in one config file
  cat > "$TMPDIR_TEST/test_multi.sh" <<'TESTEOF'
#!/bin/bash
set -euo pipefail

PRD_DIR="$TEST_PRD_DIR"
MODEL_OVERRIDE=""
ITER_TIMEOUT=30
TIMEOUT_SECONDS=1800
QUALITY_GATE=false
STRICT=false
SKIP_TESTS=false
REVIEW=false
MAX_COST=""
STALL_TIMEOUT=5
CONFIG_LAST_MTIME=""

eval "$FUNC_BODY"

load_dynamic_config

PASS_COUNT=0
FAIL_LIST=""

if [[ "$MODEL_OVERRIDE" == "claude-opus-4-6" ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}model=$MODEL_OVERRIDE "; fi
if [[ "$ITER_TIMEOUT" -eq 60 ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}timeout=$ITER_TIMEOUT "; fi
if [[ "$QUALITY_GATE" == "true" ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}qg=$QUALITY_GATE "; fi
if [[ "$STALL_TIMEOUT" -eq 10 ]]; then PASS_COUNT=$((PASS_COUNT+1)); else FAIL_LIST="${FAIL_LIST}stall=$STALL_TIMEOUT "; fi

if [[ $PASS_COUNT -eq 4 ]]; then
  echo "PASS:multi"
else
  echo "FAIL:multi:${FAIL_LIST}"
fi
TESTEOF

  TEST_PRD_DIR="$TMPDIR_TEST/multi_prd"
  mkdir -p "$TEST_PRD_DIR"
  echo '{"model": "claude-opus-4-6", "timeout": 60, "quality_gate": true, "stall_timeout": 10}' > "$TEST_PRD_DIR/ralph-config.json"
  export TEST_PRD_DIR FUNC_BODY="$LOAD_FUNC"
  OUTPUT=$(bash "$TMPDIR_TEST/test_multi.sh" 2>&1) || true

  if echo "$OUTPUT" | grep -q "PASS:multi"; then
    pass "should reload multiple settings from a single config file"
  else
    fail "should reload multiple settings from a single config file ($(echo "$OUTPUT" | grep "FAIL:" || echo "function error: $OUTPUT"))"
  fi

else
  # Function not found — fail all functional tests
  fail "should return success when ralph-config.json doesn't exist (function not found)"
  fail "should update MODEL_OVERRIDE when model changes in config (function not found)"
  fail "should update ITER_TIMEOUT when timeout changes in config (function not found)"
  fail "should recalculate TIMEOUT_SECONDS when timeout changes (function not found)"
  fail "should update boolean settings (quality_gate, strict, skip_tests, review) (function not found)"
  fail "should keep previous config when ralph-config.json is malformed (function not found)"
  fail "should skip reload when config file mtime is unchanged (function not found)"
  fail "should update MAX_COST when max_cost changes in config (function not found)"
  fail "should update STALL_TIMEOUT when stall_timeout changes in config (function not found)"
  fail "should reload multiple settings from a single config file (function not found)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 9: Main loop integration
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Main loop integration ──"

# Test 28: load_dynamic_config is called in the main loop
if grep -A5 'while.*ITERATION.*MAX_ITERATIONS' "$RALPH" | grep -qE 'load_dynamic_config'; then
  pass "should call load_dynamic_config at the start of each iteration"
else
  # Check within a broader range of the loop start
  LOOP_LINE=$(grep -n 'while.*ITERATION.*MAX_ITERATIONS' "$RALPH" | head -1 | cut -d: -f1)
  if [[ -n "$LOOP_LINE" ]]; then
    LOOP_END=$((LOOP_LINE + 20))
    if sed -n "${LOOP_LINE},${LOOP_END}p" "$RALPH" | grep -q 'load_dynamic_config'; then
      pass "should call load_dynamic_config at the start of each iteration"
    else
      fail "should call load_dynamic_config at the start of each iteration"
    fi
  else
    fail "should call load_dynamic_config at the start of each iteration (main loop not found)"
  fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Section 10: Startup banner
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Documentation ──"

# Test 29: Sample config format documented in ralph.sh comments or help
if grep -qE 'ralph-config\.json' "$RALPH"; then
  pass "should document ralph-config.json in ralph.sh"
else
  fail "should document ralph-config.json in ralph.sh"
fi

# Test 30: Non-reloadable settings documented
if grep -qE 'non.reloadable|launch.only|NON_RELOADABLE|not reloadable' "$RALPH"; then
  pass "should document which settings are non-reloadable"
else
  fail "should document which settings are non-reloadable"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

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
