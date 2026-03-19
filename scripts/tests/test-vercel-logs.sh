#!/bin/bash
# test-vercel-logs.sh — Tests for Vercel log integration
# Run: bash scripts/tests/test-vercel-logs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RALPH="$REPO_ROOT/scripts/ralph.sh"
VL="$REPO_ROOT/scripts/lib/vercel-logs.sh"
CV="$REPO_ROOT/scripts/check-vercel.sh"

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
echo "TEST: Vercel Log Integration"
echo "═══════════════════════════════════════"
echo ""

# ─── Shared library ──────────────────────────────────────────────────────────

echo "── Shared library (scripts/lib/vercel-logs.sh) ──"

if [[ -f "$VL" ]]; then
  pass "should have scripts/lib/vercel-logs.sh"
else
  fail "should have scripts/lib/vercel-logs.sh"
fi

if grep -qE 'vercel_check_token\(\)' "$VL"; then
  pass "should export vercel_check_token function"
else
  fail "should export vercel_check_token function"
fi

if grep -qE 'vercel_find_project\(\)' "$VL"; then
  pass "should export vercel_find_project function"
else
  fail "should export vercel_find_project function"
fi

if grep -qE 'vercel_get_latest_deployment\(\)' "$VL"; then
  pass "should export vercel_get_latest_deployment function"
else
  fail "should export vercel_get_latest_deployment function"
fi

if grep -qE 'vercel_get_build_logs\(\)' "$VL"; then
  pass "should export vercel_get_build_logs function"
else
  fail "should export vercel_get_build_logs function"
fi

if grep -qE 'vercel_get_runtime_logs\(\)' "$VL"; then
  pass "should export vercel_get_runtime_logs function"
else
  fail "should export vercel_get_runtime_logs function"
fi

if grep -qE 'vercel_diagnose_deployment\(\)' "$VL"; then
  pass "should export vercel_diagnose_deployment function"
else
  fail "should export vercel_diagnose_deployment function"
fi

# ─── Token handling ──────────────────────────────────────────────────────────

echo ""
echo "── Token handling ──"

if grep -qE 'VERCEL_TOKEN' "$VL"; then
  pass "should use VERCEL_TOKEN environment variable"
else
  fail "should use VERCEL_TOKEN environment variable"
fi

if grep -qE 'Authorization.*Bearer.*VERCEL_TOKEN' "$VL"; then
  pass "should pass token as Bearer auth header"
else
  fail "should pass token as Bearer auth header"
fi

# ─── Project discovery ───────────────────────────────────────────────────────

echo ""
echo "── Project discovery ──"

if grep -qE '\.vercel/project\.json' "$VL"; then
  pass "should check .vercel/project.json for project ID"
else
  fail "should check .vercel/project.json for project ID"
fi

if grep -qE 'v9/projects' "$VL"; then
  pass "should fall back to API project listing"
else
  fail "should fall back to API project listing"
fi

# ─── Build logs ──────────────────────────────────────────────────────────────

echo ""
echo "── Build logs ──"

if grep -qE 'deployments.*events' "$VL"; then
  pass "should fetch build events from deployment API"
else
  fail "should fetch build events from deployment API"
fi

if grep -qE 'stdout' "$VL" && grep -qE 'stderr' "$VL"; then
  pass "should parse stdout and stderr from build events"
else
  fail "should parse stdout and stderr from build events"
fi

# ─── Runtime logs ────────────────────────────────────────────────────────────

echo ""
echo "── Runtime logs ──"

if grep -qE 'projects.*logs' "$VL"; then
  pass "should fetch runtime logs from project logs API"
else
  fail "should fetch runtime logs from project logs API"
fi

if grep -qE 'since_minutes' "$VL"; then
  pass "should support configurable time window for runtime logs"
else
  fail "should support configurable time window for runtime logs"
fi

# ─── Diagnosis ───────────────────────────────────────────────────────────────

echo ""
echo "── Diagnosis ──"

if grep -qE 'build_errors' "$VL"; then
  pass "should extract build errors from logs"
else
  fail "should extract build errors from logs"
fi

if grep -qE 'runtime_errors' "$VL"; then
  pass "should extract runtime errors from logs"
else
  fail "should extract runtime errors from logs"
fi

if grep -qE 'vercel-diagnosis\.json' "$VL"; then
  pass "should write vercel-diagnosis.json"
else
  fail "should write vercel-diagnosis.json"
fi

if grep -qE 'errors\.jsonl' "$VL"; then
  pass "should append to errors.jsonl when errors found"
else
  fail "should append to errors.jsonl when errors found"
fi

if grep -qE 'FUNCTION_INVOCATION' "$VL" && grep -qE '500.*502.*503' "$VL"; then
  pass "should detect serverless function errors"
else
  fail "should detect serverless function errors"
fi

# ─── Ralph integration ──────────────────────────────────────────────────────

echo ""
echo "── Ralph integration ──"

if grep -qE 'vercel-logs\.sh' "$RALPH"; then
  pass "should source vercel-logs.sh in ralph.sh"
else
  fail "should source vercel-logs.sh in ralph.sh"
fi

if grep -qE 'CHECK_VERCEL' "$RALPH"; then
  pass "should have CHECK_VERCEL config variable"
else
  fail "should have CHECK_VERCEL config variable"
fi

if grep -qE 'check-vercel' "$RALPH" && grep -qE 'skip-vercel' "$RALPH"; then
  pass "should accept --check-vercel and --skip-vercel flags"
else
  fail "should accept --check-vercel and --skip-vercel flags"
fi

if grep -qE 'vercel_diagnose_deployment' "$RALPH"; then
  pass "should call vercel_diagnose_deployment in main loop"
else
  fail "should call vercel_diagnose_deployment in main loop"
fi

if grep -qE 'vercel-diagnosis\.json' "$RALPH"; then
  pass "should show Vercel status in end summary"
else
  fail "should show Vercel status in end summary"
fi

# ─── Standalone script ──────────────────────────────────────────────────────

echo ""
echo "── Standalone script (check-vercel.sh) ──"

if [[ -f "$CV" ]]; then
  pass "should have scripts/check-vercel.sh"
else
  fail "should have scripts/check-vercel.sh"
fi

if grep -qE '\-\-all' "$CV"; then
  pass "should accept --all flag"
else
  fail "should accept --all flag"
fi

if grep -qE '\-\-json' "$CV"; then
  pass "should accept --json flag"
else
  fail "should accept --json flag"
fi

if grep -qE '\-\-runtime' "$CV"; then
  pass "should accept --runtime flag for time window"
else
  fail "should accept --runtime flag for time window"
fi

if grep -qE 'VERCEL STATUS' "$CV"; then
  pass "should display formatted status output"
else
  fail "should display formatted status output"
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
