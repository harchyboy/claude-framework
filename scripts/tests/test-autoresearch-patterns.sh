#!/bin/bash
# test-autoresearch-patterns.sh — Tests for autoresearch-inspired patterns
# Tests: immutable evaluation harness, context window hygiene, git auto-reset
# Run: bash scripts/tests/test-autoresearch-patterns.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RALPH="$REPO_ROOT/scripts/ralph.sh"
GP="$REPO_ROOT/scripts/generate-proof.sh"
VA="$REPO_ROOT/.claude/agents/verification-agent.md"

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
echo "TEST: Autoresearch-Inspired Patterns"
echo "═══════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# Feature 1: Immutable Evaluation Harness
# ═══════════════════════════════════════════════════════════════════════════

echo "── Feature 1: Immutable Evaluation Harness ──"

echo ""
echo "  ralph.sh:"

if grep -qE 'ralph_lock_criteria\(\)' "$RALPH"; then
  pass "should have ralph_lock_criteria() function"
else
  fail "should have ralph_lock_criteria() function"
fi

if grep -qE 'ralph_verify_criteria_integrity\(\)' "$RALPH"; then
  pass "should have ralph_verify_criteria_integrity() function"
else
  fail "should have ralph_verify_criteria_integrity() function"
fi

if grep -qE 'CRITERIA_LOCK_DIR' "$RALPH"; then
  pass "should define CRITERIA_LOCK_DIR"
else
  fail "should define CRITERIA_LOCK_DIR"
fi

if grep -qE '\.ralph-lock' "$RALPH"; then
  pass "should use .ralph-lock directory"
else
  fail "should use .ralph-lock directory"
fi

if grep -qE 'sha256' "$RALPH"; then
  pass "should use SHA-256 checksums for criteria integrity"
else
  fail "should use SHA-256 checksums for criteria integrity"
fi

if grep -qE 'lock_checksum' "$RALPH"; then
  pass "should store lock checksum file"
else
  fail "should store lock checksum file"
fi

if grep -qE 'criteria\.json' "$RALPH"; then
  pass "should write per-story criteria.json files"
else
  fail "should write per-story criteria.json files"
fi

if grep -qE 'locked-criteria' "$RALPH"; then
  pass "should pass --locked-criteria to generate-proof.sh"
else
  fail "should pass --locked-criteria to generate-proof.sh"
fi

if grep -qE 'CRITERIA TAMPERED' "$RALPH"; then
  pass "should detect criteria tampering"
else
  fail "should detect criteria tampering"
fi

if grep -qE 'ralph_lock_criteria.*PRD_DIR' "$RALPH"; then
  pass "should call ralph_lock_criteria on startup"
else
  fail "should call ralph_lock_criteria on startup"
fi

echo ""
echo "  generate-proof.sh:"

if grep -qE '^\s+--locked-criteria\)' "$GP"; then
  pass "should accept --locked-criteria flag"
else
  fail "should accept --locked-criteria flag"
fi

if grep -qE 'LOCKED_CRITERIA' "$GP"; then
  pass "should track LOCKED_CRITERIA variable"
else
  fail "should track LOCKED_CRITERIA variable"
fi

if grep -qE 'CRITERIA_SOURCE' "$GP"; then
  pass "should track criteria source (locked vs prd)"
else
  fail "should track criteria source (locked vs prd)"
fi

if grep -qE 'locked_at' "$GP"; then
  pass "should show locked timestamp in criteria.md"
else
  fail "should show locked timestamp in criteria.md"
fi

if grep -qE 'locked\.criteria' "$GP" && grep -qE 'story\.acceptanceCriteria.*locked' "$GP"; then
  pass "should override acceptanceCriteria with locked version in verdict"
else
  fail "should override acceptanceCriteria with locked version in verdict"
fi

echo ""
echo "  verification-agent.md:"

if grep -qE 'locked.*immutable.*cannot be gamed' "$VA"; then
  pass "should instruct agent to use locked criteria"
else
  fail "should instruct agent to use locked criteria"
fi

if grep -qE 'Never read criteria from.*prd\.json.*directly' "$VA"; then
  pass "should prohibit reading criteria from prd.json"
else
  fail "should prohibit reading criteria from prd.json"
fi

# Functional test: lock/verify roundtrip
echo ""
echo "  Functional:"

TMPDIR_LOCK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCK"' EXIT

# Create a fake PRD
cat > "$TMPDIR_LOCK/prd.json" <<'PRDEOF'
{
  "branchName": "test",
  "userStories": [
    {
      "id": "US-TEST",
      "title": "Test story",
      "description": "A test",
      "acceptanceCriteria": ["Criterion A", "Criterion B"],
      "passes": false
    }
  ]
}
PRDEOF

# Run lock function in isolation
ORIG_DIR=$(pwd)
cd "$TMPDIR_LOCK"
LOCK_OUTPUT=$(bash -c "
  mkdir -p .ralph-lock
  node -e \"
    const crypto = require('crypto');
    const fs = require('fs');
    const prd = JSON.parse(fs.readFileSync('prd.json', 'utf8'));
    const allCriteria = [];
    prd.userStories.forEach(story => {
      const locked = {
        story_id: story.id,
        title: story.title,
        criteria: story.acceptanceCriteria || [],
        locked_at: new Date().toISOString()
      };
      fs.writeFileSync('.ralph-lock/' + story.id + '.criteria.json', JSON.stringify(locked, null, 2));
      allCriteria.push({id: story.id, criteria: story.acceptanceCriteria});
    });
    const hash = crypto.createHash('sha256').update(JSON.stringify(allCriteria)).digest('hex');
    fs.writeFileSync('.ralph-lock/.lock_checksum', hash);
    console.log('LOCKED:' + hash);
  \"
" 2>&1)

if echo "$LOCK_OUTPUT" | grep -q "LOCKED:"; then
  pass "should create locked criteria file with checksum"
else
  fail "should create locked criteria file with checksum"
fi

if [[ -f ".ralph-lock/US-TEST.criteria.json" ]]; then
  pass "should write per-story criteria file"
  # Verify content
  LOCKED_CONTENT=$(node -e "
    const l = JSON.parse(require('fs').readFileSync('.ralph-lock/US-TEST.criteria.json','utf8'));
    if (l.story_id === 'US-TEST' && l.criteria.length === 2 && l.criteria[0] === 'Criterion A') console.log('VALID');
  " 2>/dev/null || echo "INVALID")
  if [[ "$LOCKED_CONTENT" == "VALID" ]]; then
    pass "should preserve exact criteria in locked file"
  else
    fail "should preserve exact criteria in locked file"
  fi
else
  fail "should write per-story criteria file"
  fail "should preserve exact criteria in locked file"
fi
cd "$ORIG_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# Feature 2: Context Window Hygiene
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "── Feature 2: Context Window Hygiene ──"

echo ""
echo "  ralph.sh:"

# No tee on Claude output
if grep -qE 'run_claude >.*LOG_FILE.*2>&1 &' "$RALPH"; then
  pass "should redirect Claude output to file (not tee)"
else
  fail "should redirect Claude output to file (not tee)"
fi

if ! grep -qE 'run_claude.*tee' "$RALPH"; then
  pass "should not pipe Claude output through tee"
else
  fail "should not pipe Claude output through tee"
fi

# No tee on verification
if grep -qE 'generate-proof\.sh.*>>.*LOG_FILE.*2>&1' "$RALPH"; then
  pass "should redirect verification output to file (not tee)"
else
  fail "should redirect verification output to file (not tee)"
fi

# Verdict extraction
if grep -qE 'ralph_extract_verdict' "$RALPH"; then
  pass "should have ralph_extract_verdict function"
else
  fail "should have ralph_extract_verdict function"
fi

if grep -qE 'Iteration results' "$RALPH"; then
  pass "should show extracted verdict lines after iteration"
else
  fail "should show extracted verdict lines after iteration"
fi

# grep -P fix
if ! grep -qE 'grep -oP' "$RALPH"; then
  pass "should not use grep -oP (shell-scripts.md violation)"
else
  fail "should not use grep -oP (shell-scripts.md violation)"
fi

if grep -qE "grep -oE.*cost.*sed" "$RALPH"; then
  pass "should extract cost using grep -oE + sed (portable)"
else
  fail "should extract cost using grep -oE + sed (portable)"
fi

echo ""
echo "  generate-proof.sh:"

# No tee on test output
if ! grep -q 'tee.*TEST_OUTPUT' "$GP"; then
  pass "should not pipe test output through tee"
else
  fail "should not pipe test output through tee"
fi

if ! grep -q 'tee.*playwright' "$GP"; then
  pass "should not pipe playwright output through tee"
else
  fail "should not pipe playwright output through tee"
fi

if grep -qE '>"?\$.*TEST_OUTPUT.*2>&1' "$GP"; then
  pass "should redirect test output to file"
else
  fail "should redirect test output to file"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Feature 3: Git Auto-Reset on Failure
# ═══════════════════════════════════════════════════════════════════════════

echo ""
echo "── Feature 3: Git Auto-Reset on Failure ──"

echo ""
echo "  ralph.sh:"

if grep -qE 'ralph_reset_failed_story\(\)' "$RALPH"; then
  pass "should have ralph_reset_failed_story() function"
else
  fail "should have ralph_reset_failed_story() function"
fi

if grep -qE 'AUTO_RESET=true' "$RALPH"; then
  pass "should default AUTO_RESET=true"
else
  fail "should default AUTO_RESET=true"
fi

if grep -qE '^\s+--no-reset\)' "$RALPH"; then
  pass "should accept --no-reset flag"
else
  fail "should accept --no-reset flag"
fi

if grep -qE 'RALPH_PRE_STORY_HEAD' "$RALPH"; then
  pass "should record HEAD before story starts"
else
  fail "should record HEAD before story starts"
fi

if grep -qE 'git rev-parse HEAD' "$RALPH" && grep -qE 'RALPH_PRE_STORY_HEAD' "$RALPH"; then
  pass "should capture pre-story HEAD via git rev-parse"
else
  fail "should capture pre-story HEAD via git rev-parse"
fi

if grep -qE 'git reset --hard.*pre_head' "$RALPH"; then
  pass "should git reset --hard to pre-story HEAD on failure"
else
  fail "should git reset --hard to pre-story HEAD on failure"
fi

if grep -qE 'git worktree remove.*force' "$RALPH" && grep -qE 'git branch -D' "$RALPH"; then
  pass "should remove worktree and branch on failure"
else
  fail "should remove worktree and branch on failure"
fi

if grep -qE 'story\.passes.*false' "$RALPH" && grep -qE 'ralph_reset_failed_story' "$RALPH"; then
  pass "should unmark story as passed on reset"
else
  fail "should unmark story as passed on reset"
fi

# Reset called on verification failure
if grep -B2 -A2 'ralph_reset_failed_story' "$RALPH" | grep -q 'Verification failed'; then
  pass "should call reset on verification failure"
else
  fail "should call reset on verification failure"
fi

# Reset called on quality gate failure
if grep -B2 -A2 'ralph_reset_failed_story' "$RALPH" | grep -q 'Quality gate failed'; then
  pass "should call reset on quality gate failure"
else
  fail "should call reset on quality gate failure"
fi

if grep -qE 'story_reset.*verification_failed' "$RALPH"; then
  pass "should emit story_reset event with reason"
else
  fail "should emit story_reset event with reason"
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
