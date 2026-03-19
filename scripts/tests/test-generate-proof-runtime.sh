#!/bin/bash
# test-generate-proof-runtime.sh — Tests for generate-proof.sh runtime verification
# Run: bash scripts/tests/test-generate-proof-runtime.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GENERATE_PROOF="$REPO_ROOT/scripts/generate-proof.sh"

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
echo "TEST: generate-proof.sh Runtime Verification"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: Script accepts --skip-runtime flag ─────────────────────────────

echo "── Flag parsing ──"

if grep -qE '^\s+--skip-runtime\)' "$GENERATE_PROOF"; then
  pass "should accept --skip-runtime flag"
else
  fail "should accept --skip-runtime flag"
fi

if grep -qE '^\s+--dev-cmd\)' "$GENERATE_PROOF"; then
  pass "should accept --dev-cmd flag"
else
  fail "should accept --dev-cmd flag"
fi

if grep -qE '^\s+--dev-url\)' "$GENERATE_PROOF"; then
  pass "should accept --dev-url flag"
else
  fail "should accept --dev-url flag"
fi

# ─── Test 2: Runtime verification phase exists ──────────────────────────────

echo ""
echo "── Runtime verification phase ──"

if grep -qE 'Phase 4.*Runtime verification.*Playwright' "$GENERATE_PROOF"; then
  pass "should have Phase 4: Runtime verification"
else
  fail "should have Phase 4: Runtime verification"
fi

if grep -qE 'RUNTIME_VERIFIED=false' "$GENERATE_PROOF"; then
  pass "should initialise RUNTIME_VERIFIED flag"
else
  fail "should initialise RUNTIME_VERIFIED flag"
fi

# ─── Test 3: Auto-detect dev server command ──────────────────────────────────

echo ""
echo "── Dev server auto-detection ──"

if grep -qE 'scripts\.dev.*scripts\.start.*scripts\.serve' "$GENERATE_PROOF"; then
  pass "should auto-detect dev command from package.json (dev > start > serve)"
else
  fail "should auto-detect dev command from package.json (dev > start > serve)"
fi

if grep -qE "npm run" "$GENERATE_PROOF"; then
  pass "should construct npm run command from detected script"
else
  fail "should construct npm run command from detected script"
fi

# ─── Test 4: Dev server lifecycle ────────────────────────────────────────────

echo ""
echo "── Dev server lifecycle ──"

if grep -qE 'DEV_PID=""' "$GENERATE_PROOF"; then
  pass "should track dev server PID"
else
  fail "should track dev server PID"
fi

if grep -qE 'kill.*DEV_PID' "$GENERATE_PROOF"; then
  pass "should kill dev server after verification"
else
  fail "should kill dev server after verification"
fi

if grep -qE 'curl.*http_code.*DEV_URL' "$GENERATE_PROOF"; then
  pass "should poll dev server readiness with curl"
else
  fail "should poll dev server readiness with curl"
fi

if grep -qE 'DEV_TIMEOUT' "$GENERATE_PROOF"; then
  pass "should respect dev server startup timeout"
else
  fail "should respect dev server startup timeout"
fi

# ─── Test 5: Playwright test detection ───────────────────────────────────────

echo ""
echo "── Playwright test detection ──"

if grep -qE 'playwright\.config\.(ts|js|mjs)' "$GENERATE_PROOF"; then
  pass "should detect Playwright config files"
else
  fail "should detect Playwright config files"
fi

if grep -qE 'e2e|tests/e2e|test/e2e|tests/playwright' "$GENERATE_PROOF"; then
  pass "should detect e2e test directories"
else
  fail "should detect e2e test directories"
fi

if grep -qE 'npx playwright test' "$GENERATE_PROOF"; then
  pass "should run Playwright tests via npx"
else
  fail "should run Playwright tests via npx"
fi

# ─── Test 6: Smoke test fallback ─────────────────────────────────────────────

echo ""
echo "── Smoke test fallback ──"

if grep -qE 'No Playwright tests found.*smoke test' "$GENERATE_PROOF"; then
  pass "should fall back to HTTP smoke test when no Playwright tests exist"
else
  fail "should fall back to HTTP smoke test when no Playwright tests exist"
fi

if grep -qE 'smoke-response\.html' "$GENERATE_PROOF"; then
  pass "should save smoke test response body"
else
  fail "should save smoke test response body"
fi

# ─── Test 7: Screenshot capture ──────────────────────────────────────────────

echo ""
echo "── Screenshot capture ──"

if grep -qE 'npx.*playwright screenshot.*full-page' "$GENERATE_PROOF"; then
  pass "should capture full-page screenshot via Playwright CLI"
else
  fail "should capture full-page screenshot via Playwright CLI"
fi

if grep -qE 'screenshots/homepage\.png' "$GENERATE_PROOF"; then
  pass "should save screenshot to proof directory"
else
  fail "should save screenshot to proof directory"
fi

if grep -qE 'find.*test-results.*\.png.*cp.*screenshots' "$GENERATE_PROOF"; then
  pass "should collect Playwright test screenshots into proof directory"
else
  fail "should collect Playwright test screenshots into proof directory"
fi

# ─── Test 8: Runtime results feed into verdict ───────────────────────────────

echo ""
echo "── Verdict integration ──"

if grep -qE 'runtime_verified.*runtimeVerified' "$GENERATE_PROOF"; then
  pass "should include runtime_verified flag in verdict.json"
else
  fail "should include runtime_verified flag in verdict.json"
fi

if grep -qE 'RUNTIME_RESULTS_FILE' "$GENERATE_PROOF"; then
  pass "should write runtime results to a file"
else
  fail "should write runtime results to a file"
fi

if grep -qE 'verification_type.*verificationType' "$GENERATE_PROOF"; then
  pass "should set verification_type based on runtime verification"
else
  fail "should set verification_type based on runtime verification"
fi

# ─── Test 9: Confidence uncapped with runtime verification ───────────────────

echo ""
echo "── Confidence scoring ──"

if grep -qE 'Static-only verification caps confidence' "$GENERATE_PROOF"; then
  pass "should cap confidence at 0.85 for static-only verification"
else
  fail "should cap confidence at 0.85 for static-only verification"
fi

if grep -qE 'Runtime verification allows full confidence' "$GENERATE_PROOF"; then
  pass "should allow full confidence range with runtime verification"
else
  fail "should allow full confidence range with runtime verification"
fi

if grep -qE '!runtimeVerified' "$GENERATE_PROOF" && grep -qE 'Math\.min.*0\.85' "$GENERATE_PROOF"; then
  pass "should only cap confidence when runtime verification is not available"
else
  fail "should only cap confidence when runtime verification is not available"
fi

# ─── Test 10: UI criteria upgraded with runtime evidence ─────────────────────

echo ""
echo "── UI criteria detection ──"

if grep -qE 'display|show|render|visible|appear|page|button|click|form|input|navigate|redirect' "$GENERATE_PROOF"; then
  pass "should detect UI-related acceptance criteria keywords"
else
  fail "should detect UI-related acceptance criteria keywords"
fi

if grep -qE 'runtimeVerified' "$GENERATE_PROOF" && grep -qE 'Runtime verification passed' "$GENERATE_PROOF"; then
  pass "should upgrade UNTESTABLE UI criteria to PASS when runtime verified"
else
  fail "should upgrade UNTESTABLE UI criteria to PASS when runtime verified"
fi

# ─── Test 11: Screenshots included in verdict ───────────────────────────────

echo ""
echo "── Verdict screenshots ──"

if grep -qE 'screenshotDir' "$GENERATE_PROOF"; then
  pass "should collect screenshots from proof directory"
else
  fail "should collect screenshots from proof directory"
fi

if grep -qE 'screenshots:' "$GENERATE_PROOF"; then
  pass "should include screenshots array in verdict.json"
else
  fail "should include screenshots array in verdict.json"
fi

# ─── Test 12: Verification report includes runtime section ───────────────────

echo ""
echo "── Report format ──"

if grep -qE 'Runtime.*Playwright.*tests.*Static.*code.*tests only' "$GENERATE_PROOF"; then
  pass "should label verification type in report (Runtime vs Static)"
else
  fail "should label verification type in report (Runtime vs Static)"
fi

if grep -qE 'Runtime Results' "$GENERATE_PROOF"; then
  pass "should include Runtime Results section in verification.md"
else
  fail "should include Runtime Results section in verification.md"
fi

if grep -qE 'Screenshots' "$GENERATE_PROOF" && grep -qE '!\[Screenshot' "$GENERATE_PROOF"; then
  pass "should include Screenshots section with image links in verification.md"
else
  fail "should include Screenshots section with image links in verification.md"
fi

# ─── Test 13: ralph.sh defaults ──────────────────────────────────────────────

echo ""
echo "── ralph.sh defaults ──"

RALPH="$REPO_ROOT/scripts/ralph.sh"

if grep -qE '^VERIFY=true$' "$RALPH"; then
  pass "should default VERIFY=true in ralph.sh"
else
  fail "should default VERIFY=true in ralph.sh"
fi

if grep -qE '^VERIFY_RUNTIME=true$' "$RALPH"; then
  pass "should default VERIFY_RUNTIME=true in ralph.sh"
else
  fail "should default VERIFY_RUNTIME=true in ralph.sh"
fi

if grep -qE '^\s+--skip-verify\)' "$RALPH"; then
  pass "should accept --skip-verify flag in ralph.sh"
else
  fail "should accept --skip-verify flag in ralph.sh"
fi

if grep -qE '^\s+--skip-verify-runtime\)' "$RALPH"; then
  pass "should accept --skip-verify-runtime flag in ralph.sh"
else
  fail "should accept --skip-verify-runtime flag in ralph.sh"
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
