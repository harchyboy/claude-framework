#!/bin/bash
# test-consensus-gate.sh — Tests for consensus-gate.sh
# Run: bash scripts/tests/test-consensus-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATE="$REPO_ROOT/scripts/consensus-gate.sh"

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
echo "TEST: Consensus Gate"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: Unanimous approve ───────────────────────────────────────────────

echo "── Test 1: Unanimous approve ──"

cat > "$TMPDIR_TEST/test1.json" <<'EOF'
{
  "agents": [
    { "name": "agent-1", "verdict": "APPROVE", "p1_count": 0 },
    { "name": "agent-2", "verdict": "APPROVE", "p1_count": 0 },
    { "name": "agent-3", "verdict": "APPROVE", "p1_count": 0 }
  ]
}
EOF

if bash "$GATE" --quiet --json "$TMPDIR_TEST/test1.json"; then
  pass "should return exit 0 (APPROVED) when all agents APPROVE with no P1s"
else
  fail "should return exit 0 (APPROVED) when all agents APPROVE with no P1s"
fi

# ─── Test 2: Below threshold ─────────────────────────────────────────────────

echo ""
echo "── Test 2: Below threshold (33% < 75%) ──"

cat > "$TMPDIR_TEST/test2.json" <<'EOF'
{
  "agents": [
    { "name": "agent-1", "verdict": "APPROVE",         "p1_count": 0 },
    { "name": "agent-2", "verdict": "REQUEST_CHANGES", "p1_count": 0 },
    { "name": "agent-3", "verdict": "REQUEST_CHANGES", "p1_count": 0 }
  ]
}
EOF

if bash "$GATE" --quiet --json "$TMPDIR_TEST/test2.json"; then
  fail "should return exit 1 (BLOCKED) when approval rate is 33% < 75% threshold"
else
  pass "should return exit 1 (BLOCKED) when approval rate is 33% < 75% threshold"
fi

# ─── Test 3: Exactly at threshold ────────────────────────────────────────────

echo ""
echo "── Test 3: Exactly at threshold (75% = 75%) ──"

cat > "$TMPDIR_TEST/test3.json" <<'EOF'
{
  "agents": [
    { "name": "agent-1", "verdict": "APPROVE",         "p1_count": 0 },
    { "name": "agent-2", "verdict": "APPROVE",         "p1_count": 0 },
    { "name": "agent-3", "verdict": "APPROVE",         "p1_count": 0 },
    { "name": "agent-4", "verdict": "REQUEST_CHANGES", "p1_count": 0 }
  ]
}
EOF

if bash "$GATE" --quiet --json "$TMPDIR_TEST/test3.json"; then
  pass "should return exit 0 (APPROVED) when approval rate is exactly 75% = threshold"
else
  fail "should return exit 0 (APPROVED) when approval rate is exactly 75% = threshold"
fi

# ─── Test 4: All abstain ─────────────────────────────────────────────────────

echo ""
echo "── Test 4: All abstain ──"

cat > "$TMPDIR_TEST/test4.json" <<'EOF'
{
  "agents": [
    { "name": "agent-1", "verdict": "ABSTAIN", "p1_count": 0 },
    { "name": "agent-2", "verdict": "ABSTAIN", "p1_count": 0 },
    { "name": "agent-3", "verdict": "ABSTAIN", "p1_count": 0 }
  ]
}
EOF

if bash "$GATE" --quiet --json "$TMPDIR_TEST/test4.json"; then
  fail "should return exit 1 (BLOCKED) when all agents ABSTAIN"
else
  pass "should return exit 1 (BLOCKED) when all agents ABSTAIN"
fi

# ─── Test 5: P1 veto override ────────────────────────────────────────────────

echo ""
echo "── Test 5: P1 veto override ──"

cat > "$TMPDIR_TEST/test5.json" <<'EOF'
{
  "agents": [
    { "name": "agent-1", "verdict": "APPROVE",         "p1_count": 0 },
    { "name": "agent-2", "verdict": "APPROVE",         "p1_count": 0 },
    { "name": "agent-3", "verdict": "REQUEST_CHANGES", "p1_count": 1 }
  ]
}
EOF

if bash "$GATE" --quiet --json "$TMPDIR_TEST/test5.json"; then
  fail "should return exit 1 (BLOCKED) when any agent reports p1_count > 0"
else
  pass "should return exit 1 (BLOCKED) when any agent reports p1_count > 0"
fi

# ─── Test 6: Custom threshold ────────────────────────────────────────────────

echo ""
echo "── Test 6: Custom threshold (--threshold 50) ──"

cat > "$TMPDIR_TEST/test6.json" <<'EOF'
{
  "agents": [
    { "name": "agent-1", "verdict": "APPROVE",         "p1_count": 0 },
    { "name": "agent-2", "verdict": "REQUEST_CHANGES", "p1_count": 0 }
  ]
}
EOF

if bash "$GATE" --quiet --threshold 50 --json "$TMPDIR_TEST/test6.json"; then
  pass "should return exit 0 (APPROVED) when approval rate meets custom --threshold 50"
else
  fail "should return exit 0 (APPROVED) when approval rate meets custom --threshold 50"
fi

# ─── Test 7: Empty agents array ──────────────────────────────────────────────

echo ""
echo "── Test 7: Empty agents array ──"

cat > "$TMPDIR_TEST/test7.json" <<'EOF'
{
  "agents": []
}
EOF

if bash "$GATE" --quiet --json "$TMPDIR_TEST/test7.json"; then
  fail "should return exit 1 (BLOCKED) when agents array is empty"
else
  pass "should return exit 1 (BLOCKED) when agents array is empty"
fi

# ─── Test 8: Stdin pipe ──────────────────────────────────────────────────────

echo ""
echo "── Test 8: Stdin pipe ──"

STDIN_JSON='{"agents":[{"name":"agent-1","verdict":"APPROVE","p1_count":0},{"name":"agent-2","verdict":"APPROVE","p1_count":0},{"name":"agent-3","verdict":"APPROVE","p1_count":0}]}'

if echo "$STDIN_JSON" | bash "$GATE" --quiet; then
  pass "should return exit 0 (APPROVED) when valid JSON is piped via stdin"
else
  fail "should return exit 0 (APPROVED) when valid JSON is piped via stdin"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

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
