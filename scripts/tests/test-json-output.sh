#!/bin/bash
# test-json-output.sh — Tests for --json output across all HCF scripts
# Run: bash scripts/tests/test-json-output.sh

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

echo ""
echo "═══════════════════════════════════════"
echo "TEST: --json Output Across All Scripts"
echo "═══════════════════════════════════════"
echo ""

# ─── Shared library tests ───────────────────────────────────────────────────

echo "── Shared library (scripts/lib/json-output.sh) ──"

LIB="$REPO_ROOT/scripts/lib/json-output.sh"

if [[ -f "$LIB" ]]; then
  pass "should have scripts/lib/json-output.sh"
else
  fail "should have scripts/lib/json-output.sh"
fi

if grep -qE 'json_output_init\(\)' "$LIB"; then
  pass "should export json_output_init function"
else
  fail "should export json_output_init function"
fi

if grep -qE 'json_output_add\(\)' "$LIB"; then
  pass "should export json_output_add function"
else
  fail "should export json_output_add function"
fi

if grep -qE 'json_output_emit\(\)' "$LIB"; then
  pass "should export json_output_emit function"
else
  fail "should export json_output_emit function"
fi

if grep -qE 'json_output_suppress\(\)' "$LIB"; then
  pass "should export json_output_suppress function"
else
  fail "should export json_output_suppress function"
fi

if grep -qE 'json_output_log\(\)' "$LIB"; then
  pass "should export json_output_log function"
else
  fail "should export json_output_log function"
fi

# Functional test: library produces valid JSON
LIB_OUTPUT=$(bash -c "
  . '$LIB'
  JSON_OUTPUT=true
  json_output_init
  json_output_add 'name' 'test'
  json_output_add 'count' '42' --raw
  json_output_add 'active' 'true' --raw
  json_output_emit
" 2>/dev/null)

if echo "$LIB_OUTPUT" | node -e "JSON.parse(require('fs').readFileSync(0,'utf8'))" 2>/dev/null; then
  pass "should produce valid JSON from json_output_emit"
else
  fail "should produce valid JSON from json_output_emit"
fi

if echo "$LIB_OUTPUT" | node -e "
  const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
  process.exit(d.name === 'test' && d.count === 42 && d.active === true ? 0 : 1);
" 2>/dev/null; then
  pass "should preserve correct types (string, number, boolean)"
else
  fail "should preserve correct types (string, number, boolean)"
fi

# ─── generate-proof.sh --json ────────────────────────────────────────────────

echo ""
echo "── generate-proof.sh ──"

GP="$REPO_ROOT/scripts/generate-proof.sh"

if grep -qE '^\s+--json\)' "$GP"; then
  pass "should accept --json flag"
else
  fail "should accept --json flag"
fi

if grep -qE 'JSON_OUTPUT=false' "$GP"; then
  pass "should initialise JSON_OUTPUT=false"
else
  fail "should initialise JSON_OUTPUT=false"
fi

if grep -qE 'json_output_log' "$GP"; then
  pass "should use json_output_log for human output"
else
  fail "should use json_output_log for human output"
fi

if grep -qE 'json_output_suppress' "$GP"; then
  pass "should use json_output_suppress to hide non-JSON output"
else
  fail "should use json_output_suppress to hide non-JSON output"
fi

if grep -qE '\. "\$SCRIPT_DIR/lib/json-output\.sh"' "$GP"; then
  pass "should source shared JSON library"
else
  fail "should source shared JSON library"
fi

if grep -qE 'JSON_OUTPUT.*true' "$GP" && grep -qE 'verdict.*JSON' "$GP"; then
  pass "should emit verdict as JSON when --json is active"
else
  fail "should emit verdict as JSON when --json is active"
fi

# ─── generate-proof.sh --assertions ──────────────────────────────────────────

echo ""
echo "── generate-proof.sh content verification ──"

if grep -qE '^\s+--assertions\)' "$GP"; then
  pass "should accept --assertions flag"
else
  fail "should accept --assertions flag"
fi

if grep -qE '^\s+--verify-files\)' "$GP"; then
  pass "should accept --verify-files flag"
else
  fail "should accept --verify-files flag"
fi

if grep -qE 'ASSERTIONS_FILE' "$GP"; then
  pass "should track assertions file path"
else
  fail "should track assertions file path"
fi

if grep -qE 'content-validation\.json' "$GP"; then
  pass "should write content-validation.json to proof directory"
else
  fail "should write content-validation.json to proof directory"
fi

if grep -qE 'Phase 4b.*Content verification' "$GP"; then
  pass "should have Phase 4b: Content verification"
else
  fail "should have Phase 4b: Content verification"
fi

if grep -qE 'CONTENT_VERIFIED' "$GP"; then
  pass "should track CONTENT_VERIFIED state"
else
  fail "should track CONTENT_VERIFIED state"
fi

# DOM checks
if grep -qE 'has_doctype|has_html_tag|has_body|has_head' "$GP"; then
  pass "should check DOM structure (doctype, html, head, body)"
else
  fail "should check DOM structure (doctype, html, head, body)"
fi

if grep -qE 'no_error_page.*404.*500.*Error' "$GP"; then
  pass "should detect error pages (404, 500)"
else
  fail "should detect error pages (404, 500)"
fi

if grep -qE 'has_content.*500.*bytes' "$GP"; then
  pass "should check page has substantial content"
else
  fail "should check page has substantial content"
fi

# File verification
if grep -qE "25504446" "$GP" && grep -qE "pdf" "$GP"; then
  pass "should validate PDF files via magic bytes"
else
  fail "should validate PDF files via magic bytes"
fi

if grep -qE "89504e47" "$GP" && grep -qE "png" "$GP"; then
  pass "should validate PNG files via magic bytes"
else
  fail "should validate PNG files via magic bytes"
fi

if grep -qE 'required_headers' "$GP"; then
  pass "should validate CSV headers"
else
  fail "should validate CSV headers"
fi

if grep -qE 'min_rows.*lines\.length' "$GP"; then
  pass "should validate CSV row counts"
else
  fail "should validate CSV row counts"
fi

# API validation
if grep -qE 'curl.*FULL_URL' "$GP"; then
  pass "should validate API endpoints via curl"
else
  fail "should validate API endpoints via curl"
fi

if grep -q 'MISSING' "$GP" && grep -q 'required_fields' "$GP"; then
  pass "should check API response required fields"
else
  fail "should check API response required fields"
fi

# ─── quality-gate.sh --json ──────────────────────────────────────────────────

echo ""
echo "── quality-gate.sh ──"

QG="$REPO_ROOT/scripts/quality-gate.sh"

if grep -qE '^\s+--json\)' "$QG"; then
  pass "should accept --json flag"
else
  fail "should accept --json flag"
fi

if grep -qE 'JSON_OUTPUT=false' "$QG"; then
  pass "should initialise JSON_OUTPUT=false"
else
  fail "should initialise JSON_OUTPUT=false"
fi

if grep -qE '\. "\$SCRIPT_DIR/lib/json-output\.sh"' "$QG"; then
  pass "should source shared JSON library"
else
  fail "should source shared JSON library"
fi

if grep -qE 'QG_CHECK_NAMES|QG_CHECK_STATUSES' "$QG"; then
  pass "should accumulate check results in arrays"
else
  fail "should accumulate check results in arrays"
fi

if grep -qE 'json_output_emit' "$QG"; then
  pass "should call json_output_emit for JSON output"
else
  fail "should call json_output_emit for JSON output"
fi

if grep -qE 'json_output_add.*status.*PASSED' "$QG" && grep -qE 'json_output_add.*status.*FAILED' "$QG"; then
  pass "should include status in JSON output"
else
  fail "should include status in JSON output"
fi

if grep -qE '"checks".*CHECKS_JSON' "$QG"; then
  pass "should include checks array in JSON output"
else
  fail "should include checks array in JSON output"
fi

# ─── ralph.sh --json ─────────────────────────────────────────────────────────

echo ""
echo "── ralph.sh ──"

RALPH="$REPO_ROOT/scripts/ralph.sh"

if grep -qE '^\s+--json\)' "$RALPH"; then
  pass "should accept --json flag"
else
  fail "should accept --json flag"
fi

if grep -qE 'JSON_OUTPUT=false' "$RALPH"; then
  pass "should initialise JSON_OUTPUT=false"
else
  fail "should initialise JSON_OUTPUT=false"
fi

if grep -qE 'iterations:' "$RALPH" && grep -qE 'elapsed_minutes' "$RALPH" && grep -qE 'stories:' "$RALPH"; then
  pass "should emit JSON summary with iterations, elapsed, stories"
else
  fail "should emit JSON summary with iterations, elapsed, stories"
fi

if grep -qE 'avg_confidence|proof_packets' "$RALPH"; then
  pass "should include verification stats in JSON summary"
else
  fail "should include verification stats in JSON summary"
fi

# ─── workflow-runner.sh --json ───────────────────────────────────────────────

echo ""
echo "── workflow-runner.sh ──"

WR="$REPO_ROOT/scripts/workflow-runner.sh"

if grep -qE '^\s+--json\)' "$WR"; then
  pass "should accept --json flag"
else
  fail "should accept --json flag"
fi

if grep -qE 'JSON_OUTPUT=false' "$WR"; then
  pass "should initialise JSON_OUTPUT=false"
else
  fail "should initialise JSON_OUTPUT=false"
fi

if grep -qE 'run_id:' "$WR" && grep -qE 'phases_run:' "$WR" && grep -qE 'agents_run:' "$WR"; then
  pass "should emit JSON summary with run_id, phases, agents"
else
  fail "should emit JSON summary with run_id, phases, agents"
fi

# ─── consensus-gate.sh --output-json ─────────────────────────────────────────

echo ""
echo "── consensus-gate.sh ──"

CG="$REPO_ROOT/scripts/consensus-gate.sh"

if grep -qE '^\s+--output-json\)' "$CG"; then
  pass "should accept --output-json flag"
else
  fail "should accept --output-json flag"
fi

if grep -qE 'OUTPUT_JSON=false' "$CG"; then
  pass "should initialise OUTPUT_JSON=false"
else
  fail "should initialise OUTPUT_JSON=false"
fi

if grep -qE 'OUTPUT_JSON.*true' "$CG" && grep -qE 'echo.*RESULT' "$CG"; then
  pass "should echo RESULT as JSON when --output-json is active"
else
  fail "should echo RESULT as JSON when --output-json is active"
fi

# ─── blast-radius.sh (already has --json, verify pipe-to-while fix) ──────────

echo ""
echo "── blast-radius.sh (pipe-to-while fix) ──"

BR="$REPO_ROOT/scripts/blast-radius.sh"

if grep -qE 'done <<< "\$CHANGED_FILES"' "$BR"; then
  pass "should use heredoc instead of pipe-to-while for changed_files"
else
  fail "should use heredoc instead of pipe-to-while for changed_files"
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
