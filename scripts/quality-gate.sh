#!/bin/bash
# quality-gate.sh — Pre-commit validation
# Hartz Claude Framework
#
# Usage: bash scripts/quality-gate.sh [options]
#
# Options:
#   --strict        Fail on lint warnings (not just errors)
#   --skip-tests    Skip test execution
#   --fix           Auto-fix lint issues where possible
#   --coverage      Run tests with coverage and check thresholds

set -euo pipefail

STRICT=false
SKIP_TESTS=false
AUTO_FIX=false
CHECK_COVERAGE=false
FAILED=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)     STRICT=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    --fix)        AUTO_FIX=true ;;
    --coverage)   CHECK_COVERAGE=true ;;
    *) echo "Unknown option: $1" ;;
  esac
  shift
done

# ─── Colours ────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; FAILED=true; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
info() { echo -e "${CYAN}🔍 $1${NC}"; }

echo ""
echo "═══════════════════════════════════════"
echo "QUALITY GATE"
echo "═══════════════════════════════════════"
echo ""

# ─── Secret detection ────────────────────────────────────────────────────────

info "Checking for secrets in diff..."

SECRETS_FOUND=false
PATTERNS=(
  "SUPABASE_SERVICE_ROLE_KEY"
  "sk-[a-zA-Z0-9]{32}"
  "AKIA[0-9A-Z]{16}"
  "ghp_[a-zA-Z0-9]{36}"
  "gho_[a-zA-Z0-9]{36}"
  "xoxb-[0-9]{10,}"
  "hooks\.slack\.com/services/"
  "password\s*=\s*['\"][^'\"]{8,}"
  "api_key\s*=\s*['\"][^'\"]{10,}"
  "bearer\s+[a-zA-Z0-9]{20,}"
  "-----BEGIN.*PRIVATE KEY-----"
)

# Check ALL staged changes (not just new files) for added lines only
for pattern in "${PATTERNS[@]}"; do
  if git diff --cached -U0 2>/dev/null | grep -E '^\+' | grep -v '^\+\+\+' | grep -iE "$pattern" | grep -v "NEXT_PUBLIC_" | grep -v "example" | grep -v "placeholder" | grep -q .; then
    fail "Potential secret found matching pattern: $pattern"
    SECRETS_FOUND=true
  fi
done

if [[ "$SECRETS_FOUND" == "false" ]]; then
  pass "No secrets detected in diff"
fi

# ─── TypeScript ──────────────────────────────────────────────────────────────

if [[ -f "tsconfig.json" ]]; then
  info "TypeScript type checking..."
  if npx tsc --noEmit 2>&1; then
    pass "TypeScript: no type errors"
  else
    fail "TypeScript: type errors found (run 'npx tsc --noEmit' for details)"
  fi
fi

# ─── ESLint ──────────────────────────────────────────────────────────────────

if [[ -f ".eslintrc.json" ]] || [[ -f ".eslintrc.js" ]] || [[ -f "eslint.config.js" ]] || [[ -f "eslint.config.mjs" ]]; then
  info "ESLint..."

  ESLINT_FLAGS="--max-warnings 0"
  if [[ "$AUTO_FIX" == "true" ]]; then
    ESLINT_FLAGS="$ESLINT_FLAGS --fix"
  fi
  if [[ "$STRICT" != "true" ]]; then
    ESLINT_FLAGS="--max-warnings 100"
  fi

  if npx eslint . $ESLINT_FLAGS 2>&1; then
    pass "ESLint: no issues"
  else
    if [[ "$STRICT" == "true" ]]; then
      fail "ESLint: issues found (strict mode)"
    else
      warn "ESLint: warnings found (not blocking in non-strict mode)"
    fi
  fi
fi

# ─── Tests ───────────────────────────────────────────────────────────────────

if [[ "$SKIP_TESTS" != "true" ]]; then
  # Detect test runner
  if [[ -f "vitest.config.ts" ]] || [[ -f "vitest.config.js" ]]; then
    info "Vitest..."
    if npx vitest run 2>&1; then
      pass "Vitest: all tests passing"
    else
      fail "Vitest: tests failing — ERROR: tests failed"
    fi
  elif [[ -f "jest.config.ts" ]] || [[ -f "jest.config.js" ]]; then
    info "Jest..."
    if npx jest --passWithNoTests 2>&1; then
      pass "Jest: all tests passing"
    else
      fail "Jest: tests failing — ERROR: tests failed"
    fi
  else
    warn "No test runner detected (vitest or jest config not found)"
  fi
fi

# ─── Coverage check ──────────────────────────────────────────────────────────

if [[ "$CHECK_COVERAGE" == "true" ]] && [[ "$SKIP_TESTS" != "true" ]]; then
  info "Coverage threshold check..."

  COVERAGE_OUTPUT=""

  if [[ -f "vitest.config.ts" ]] || [[ -f "vitest.config.js" ]]; then
    COVERAGE_OUTPUT=$(npx vitest run --coverage --reporter=json 2>/dev/null || true)
  elif [[ -f "jest.config.ts" ]] || [[ -f "jest.config.js" ]]; then
    COVERAGE_OUTPUT=$(npx jest --coverage --coverageReporters=json-summary --passWithNoTests 2>/dev/null || true)
  fi

  # Parse coverage from json-summary if it exists
  COVERAGE_FILE=""
  if [[ -f "coverage/coverage-summary.json" ]]; then
    COVERAGE_FILE="coverage/coverage-summary.json"
  elif [[ -f "coverage/coverage-final.json" ]]; then
    COVERAGE_FILE="coverage/coverage-final.json"
  fi

  if [[ -n "$COVERAGE_FILE" ]] && command -v node > /dev/null 2>&1; then
    COVERAGE_RESULT=$(node -e "
      const cov = require('./' + process.argv[1]);
      const total = cov.total || {};
      const lines = total.lines ? total.lines.pct : 0;
      const branches = total.branches ? total.branches.pct : 0;
      const functions = total.functions ? total.functions.pct : 0;
      const stmts = total.statements ? total.statements.pct : 0;
      console.log(JSON.stringify({ lines, branches, functions, stmts }));
    " "$COVERAGE_FILE" 2>/dev/null || echo '{}')

    if [[ "$COVERAGE_RESULT" != "{}" ]]; then
      LINES_PCT=$(echo "$COVERAGE_RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.lines||0)")
      STMTS_PCT=$(echo "$COVERAGE_RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.stmts||0)")

      echo "  Lines:      ${LINES_PCT}%"
      echo "  Statements: ${STMTS_PCT}%"

      # Threshold: 60% minimum (configurable projects can override)
      THRESHOLD=60
      BELOW=$(node -e "console.log($LINES_PCT < $THRESHOLD || $STMTS_PCT < $THRESHOLD ? 'YES' : 'NO')")
      if [[ "$BELOW" == "YES" ]]; then
        fail "Coverage below ${THRESHOLD}% threshold — ERROR: coverage too low"
      else
        pass "Coverage meets ${THRESHOLD}% threshold"
      fi
    else
      warn "Could not parse coverage report"
    fi
  else
    warn "No coverage report generated (ensure coverage reporter is configured)"
  fi
fi

# ─── Build check (optional, only if build script exists) ─────────────────────

if command -v jq > /dev/null 2>&1 && [[ -f "package.json" ]]; then
  HAS_BUILD=$(jq -r '.scripts.build // empty' package.json 2>/dev/null)
  if [[ -n "$HAS_BUILD" ]]; then
    info "Build check..."
    if npm run build 2>&1 | tail -5; then
      pass "Build: successful"
    else
      fail "Build: failed — ERROR: build failed"
    fi
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "───────────────────────────────────────"

if [[ "$FAILED" == "true" ]]; then
  echo -e "${RED}QUALITY GATE: FAILED${NC}"
  echo ""
  echo "Fix all errors before committing."
  echo "Search 'ERROR:' in output above for machine-parseable failures."
  exit 1
else
  echo -e "${GREEN}QUALITY GATE: PASSED${NC}"
  exit 0
fi
