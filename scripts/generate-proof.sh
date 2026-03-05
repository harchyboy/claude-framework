#!/bin/bash
# generate-proof.sh — Generate a proof packet for a completed story
#
# Usage:
#   bash scripts/generate-proof.sh <story-id> [prd-path] [options]
#
# Options:
#   --skip-runtime    Skip runtime verification (Playwright)
#   --dev-cmd <cmd>   Dev server start command (default: auto-detect from package.json)
#   --dev-url <url>   Dev server URL (default: http://localhost:3000)
#   --timeout <sec>   Dev server startup timeout in seconds (default: 30)
#   --help            Show this help
#
# Generates:
#   proof/<story-id>/
#   ├── criteria.md        # Original acceptance criteria
#   ├── diff.patch         # Code changes for this story
#   ├── test-results.txt   # Test suite output
#   ├── verification.md    # Detailed verification report
#   ├── verdict.json       # Machine-readable verdict
#   └── screenshots/       # Evidence (if runtime verification)

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

STORY_ID="${1:-}"
PRD_PATH="${2:-}"
SKIP_RUNTIME=false
DEV_CMD=""
DEV_URL="http://localhost:3000"
DEV_TIMEOUT=30

if [[ -z "$STORY_ID" ]] || [[ "$STORY_ID" == "--help" ]]; then
  sed -n '2,16p' "$0"
  exit 0
fi

shift
[[ -n "${1:-}" ]] && [[ "$1" != --* ]] && { PRD_PATH="$1"; shift; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-runtime)  SKIP_RUNTIME=true ;;
    --dev-cmd)       DEV_CMD="$2"; shift ;;
    --dev-url)       DEV_URL="$2"; shift ;;
    --timeout)       DEV_TIMEOUT="$2"; shift ;;
    *) ;;
  esac
  shift
done

# ─── Colours ──────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
err()  { echo -e "${RED}  ❌ $1${NC}"; }

# ─── Find PRD ─────────────────────────────────────────────────────────────────

if [[ -z "$PRD_PATH" ]]; then
  # Auto-discover from ralph-moss directory
  for dir in scripts/ralph-moss/prds/*/; do
    if [[ -f "$dir/prd.json" ]]; then
      if node -e "
        const prd = JSON.parse(require('fs').readFileSync('$dir/prd.json', 'utf8'));
        const story = prd.userStories.find(s => s.id === '$STORY_ID');
        process.exit(story ? 0 : 1);
      " 2>/dev/null; then
        PRD_PATH="$dir/prd.json"
        break
      fi
    fi
  done
fi

if [[ -z "$PRD_PATH" ]] || [[ ! -f "$PRD_PATH" ]]; then
  err "Could not find PRD containing story $STORY_ID"
  err "Usage: bash scripts/generate-proof.sh <story-id> [prd-path]"
  exit 1
fi

info "PRD: $PRD_PATH"
info "Story: $STORY_ID"

# ─── Create proof directory ──────────────────────────────────────────────────

PROOF_DIR="proof/$STORY_ID"
mkdir -p "$PROOF_DIR/screenshots"

# ─── Extract acceptance criteria ──────────────────────────────────────────────

echo ""
echo -e "${BOLD}Phase 1: Extracting acceptance criteria${NC}"

node -e "
  const prd = JSON.parse(require('fs').readFileSync('$PRD_PATH', 'utf8'));
  const story = prd.userStories.find(s => s.id === '$STORY_ID');
  if (!story) { console.error('Story not found: $STORY_ID'); process.exit(1); }

  let md = '# Acceptance Criteria — ' + story.id + ': ' + story.title + '\n\n';
  md += '> ' + story.description + '\n\n';
  story.acceptanceCriteria.forEach((c, i) => {
    md += (i + 1) + '. ' + c + '\n';
  });
  md += '\n## Files in Scope\n\n';
  (story.filesInScope || []).forEach(f => { md += '- ' + f + '\n'; });
  if (story.notes) md += '\n## Notes\n\n' + story.notes + '\n';

  require('fs').writeFileSync('$PROOF_DIR/criteria.md', md);
  console.log('  Extracted ' + story.acceptanceCriteria.length + ' criteria');
"
ok "Criteria extracted to $PROOF_DIR/criteria.md"

# ─── Generate diff ───────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Phase 2: Capturing code diff${NC}"

# Try to find the commit for this story
STORY_COMMIT=$(git log --all --oneline --grep="$STORY_ID" | head -1 | awk '{print $1}' || true)

if [[ -n "$STORY_COMMIT" ]]; then
  git diff "${STORY_COMMIT}^..${STORY_COMMIT}" > "$PROOF_DIR/diff.patch" 2>/dev/null || true
  info "Diff from commit: $STORY_COMMIT"
else
  # Fallback: diff against main
  git diff main...HEAD > "$PROOF_DIR/diff.patch" 2>/dev/null || \
    git diff master...HEAD > "$PROOF_DIR/diff.patch" 2>/dev/null || \
    echo "# No diff available" > "$PROOF_DIR/diff.patch"
  warn "Could not find specific commit for $STORY_ID — using branch diff"
fi

DIFF_LINES=$(wc -l < "$PROOF_DIR/diff.patch" | tr -d ' ')
ok "Diff captured ($DIFF_LINES lines) to $PROOF_DIR/diff.patch"

# ─── Run tests ────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Phase 3: Running test suite${NC}"

TEST_EXIT=0
TEST_OUTPUT="$PROOF_DIR/test-results.txt"

# Auto-detect test runner
if [[ -f "package.json" ]]; then
  HAS_VITEST=$(node -e "const p=require('./package.json'); console.log((p.devDependencies||{}).vitest || (p.dependencies||{}).vitest ? 'yes' : 'no')" 2>/dev/null || echo "no")
  HAS_JEST=$(node -e "const p=require('./package.json'); console.log((p.devDependencies||{}).jest || (p.dependencies||{}).jest ? 'yes' : 'no')" 2>/dev/null || echo "no")

  if [[ "$HAS_VITEST" == "yes" ]]; then
    info "Running Vitest..."
    npx vitest run --reporter=verbose 2>&1 | tee "$TEST_OUTPUT" || TEST_EXIT=$?
  elif [[ "$HAS_JEST" == "yes" ]]; then
    info "Running Jest..."
    npx jest --verbose 2>&1 | tee "$TEST_OUTPUT" || TEST_EXIT=$?
  elif npm test --if-present 2>/dev/null; then
    info "Running npm test..."
    npm test 2>&1 | tee "$TEST_OUTPUT" || TEST_EXIT=$?
  else
    echo "No test runner detected" > "$TEST_OUTPUT"
    warn "No test runner found"
  fi
elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "pytest.ini" ]]; then
  info "Running pytest..."
  python -m pytest -v 2>&1 | tee "$TEST_OUTPUT" || TEST_EXIT=$?
else
  echo "No test framework detected" > "$TEST_OUTPUT"
  warn "No test framework detected"
fi

if [[ "$TEST_EXIT" -eq 0 ]]; then
  ok "Tests passed"
else
  err "Tests failed (exit code: $TEST_EXIT)"
fi

# ─── TypeScript check ─────────────────────────────────────────────────────────

if [[ -f "tsconfig.json" ]]; then
  echo ""
  echo -e "${BOLD}Phase 3b: TypeScript compilation${NC}"
  TSC_OUTPUT=""
  if TSC_OUTPUT=$(npx tsc --noEmit 2>&1); then
    ok "TypeScript compiles cleanly"
    echo "TypeScript: PASS" >> "$TEST_OUTPUT"
  else
    err "TypeScript compilation errors"
    echo "" >> "$TEST_OUTPUT"
    echo "=== TypeScript Errors ===" >> "$TEST_OUTPUT"
    echo "$TSC_OUTPUT" >> "$TEST_OUTPUT"
  fi
fi

# ─── Generate verdict ────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Phase 4: Generating verdict${NC}"

# Build a basic verdict from test results
node -e "
  const fs = require('fs');
  const prd = JSON.parse(fs.readFileSync('$PRD_PATH', 'utf8'));
  const story = prd.userStories.find(s => s.id === '$STORY_ID');

  const testsPassed = $TEST_EXIT === 0;
  const testOutput = fs.readFileSync('$PROOF_DIR/test-results.txt', 'utf8');
  const diffContent = fs.readFileSync('$PROOF_DIR/diff.patch', 'utf8');
  const hasChanges = diffContent.length > 50;

  // Basic static analysis of criteria
  const results = story.acceptanceCriteria.map((criterion, i) => {
    let status = 'UNTESTABLE';
    let evidence = 'Requires manual or runtime verification';

    // Check if criterion mentions TypeScript or tests
    if (/typescript compiles/i.test(criterion)) {
      const tscFailed = testOutput.includes('TypeScript Errors');
      status = tscFailed ? 'FAIL' : (hasChanges ? 'PASS' : 'UNTESTABLE');
      evidence = tscFailed ? 'TypeScript compilation errors found' : 'TypeScript compiles without errors';
    } else if (/existing tests pass/i.test(criterion) || /all.*tests pass/i.test(criterion)) {
      status = testsPassed ? 'PASS' : 'FAIL';
      evidence = testsPassed ? 'Test suite passed' : 'Test suite failed';
    } else if (/unit tests? cover/i.test(criterion)) {
      // Check if test files exist
      const hasTests = testOutput.length > 100 && testsPassed;
      status = hasTests ? 'PARTIAL' : 'UNTESTABLE';
      evidence = hasTests ? 'Tests exist and pass (coverage not independently verified)' : 'Could not verify test coverage';
    }

    return {
      criterion,
      status,
      evidence,
      screenshot: null
    };
  });

  const passCount = results.filter(r => r.status === 'PASS').length;
  const failCount = results.filter(r => r.status === 'FAIL').length;
  const totalCount = results.length;

  // Calculate confidence
  let confidence = 0;
  if (failCount > 0) {
    confidence = Math.max(0.1, (passCount / totalCount) * 0.5);
  } else if (passCount === totalCount) {
    confidence = 0.95;
  } else {
    confidence = 0.5 + (passCount / totalCount) * 0.4;
  }

  // Static-only verification caps confidence
  confidence = Math.min(confidence, 0.85);

  const verdict = {
    story_id: '$STORY_ID',
    story_title: story.title,
    verdict: failCount === 0 ? 'PASS' : 'FAIL',
    confidence: Math.round(confidence * 100) / 100,
    verification_type: 'static',
    timestamp: new Date().toISOString(),
    criteria_results: results,
    issues_found: results.filter(r => r.status === 'FAIL').map(r => r.criterion),
    summary: {
      total: totalCount,
      passed: passCount,
      failed: failCount,
      partial: results.filter(r => r.status === 'PARTIAL').length,
      untestable: results.filter(r => r.status === 'UNTESTABLE').length
    }
  };

  fs.writeFileSync('$PROOF_DIR/verdict.json', JSON.stringify(verdict, null, 2));

  // Generate verification.md
  let md = '# Verification Report — ' + story.id + ': ' + story.title + '\n\n';
  md += '**Verdict:** ' + verdict.verdict + '\n';
  md += '**Confidence:** ' + verdict.confidence + '\n';
  md += '**Verification type:** Static (code + tests only)\n';
  md += '**Timestamp:** ' + verdict.timestamp + '\n\n';
  md += '## Criteria Results\n\n';
  md += '| # | Criterion | Status | Evidence |\n';
  md += '|---|-----------|--------|----------|\n';
  results.forEach((r, i) => {
    const icon = r.status === 'PASS' ? 'PASS' : r.status === 'FAIL' ? 'FAIL' : r.status === 'PARTIAL' ? 'PARTIAL' : 'N/A';
    md += '| ' + (i+1) + ' | ' + r.criterion.replace(/\|/g, '/') + ' | ' + icon + ' | ' + r.evidence + ' |\n';
  });
  md += '\n## Test Results\n\n';
  md += 'Exit code: ' + $TEST_EXIT + '\n\n';
  if (testOutput.length > 0) {
    md += '<details><summary>Full test output</summary>\n\n\`\`\`\n' + testOutput.substring(0, 5000) + '\n\`\`\`\n</details>\n';
  }

  fs.writeFileSync('$PROOF_DIR/verification.md', md);

  // Output summary
  console.log('  Story: ' + story.id + ' — ' + story.title);
  console.log('  Verdict: ' + verdict.verdict + ' (confidence: ' + verdict.confidence + ')');
  console.log('  Criteria: ' + passCount + ' passed, ' + failCount + ' failed, ' + (totalCount - passCount - failCount) + ' unverified');
"

ok "Proof packet generated at $PROOF_DIR/"

echo ""
echo -e "${BOLD}Proof packet contents:${NC}"
ls -la "$PROOF_DIR/"
echo ""

# ─── Add to review queue ─────────────────────────────────────────────────────

REVIEW_QUEUE_DIR="$HOME/.hartz-claude-framework/review-queue"
mkdir -p "$REVIEW_QUEUE_DIR"

PROJECT_NAME=$(basename "$(pwd)")
CONFIDENCE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROOF_DIR/verdict.json','utf8')).confidence)")
VERDICT_STATUS=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PROOF_DIR/verdict.json','utf8')).verdict)")

node -e "
  const entry = {
    story_id: '$STORY_ID',
    project: '$PROJECT_NAME',
    proof_path: '$(pwd)/$PROOF_DIR',
    confidence: $CONFIDENCE,
    verdict: '$VERDICT_STATUS',
    timestamp: new Date().toISOString(),
    reviewed: false
  };
  require('fs').writeFileSync(
    '$REVIEW_QUEUE_DIR/${PROJECT_NAME}_${STORY_ID}.json',
    JSON.stringify(entry, null, 2)
  );
"
ok "Added to review queue ($REVIEW_QUEUE_DIR/)"

# ─── Recommendation ──────────────────────────────────────────────────────────

echo ""
if (( $(echo "$CONFIDENCE >= 0.9" | bc -l 2>/dev/null || node -e "console.log($CONFIDENCE >= 0.9 ? 1 : 0)") )); then
  echo -e "${GREEN}${BOLD}  HIGH CONFIDENCE — auto-merge candidate${NC}"
elif (( $(echo "$CONFIDENCE >= 0.7" | bc -l 2>/dev/null || node -e "console.log($CONFIDENCE >= 0.7 ? 1 : 0)") )); then
  echo -e "${YELLOW}${BOLD}  MEDIUM CONFIDENCE — queued for human review${NC}"
else
  echo -e "${RED}${BOLD}  LOW CONFIDENCE — needs attention before merge${NC}"
fi
echo ""
