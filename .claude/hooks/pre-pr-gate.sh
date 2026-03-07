#!/usr/bin/env bash
set -euo pipefail

# Pre-PR quality gate — PreToolUse (PR creation)
# Detects stack, runs tests + coverage + lint. Blocks PR if any check fails.
# Exit 2 = block, Exit 0 = allow.
# Full output goes to log files; only summaries go to stdout.

COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"
MUTATION_TESTING="${MUTATION_TESTING:-false}"
LOG_DIR=".claude/hooks/logs"
mkdir -p "$LOG_DIR"

PASS=true

detect_stack() {
  if [[ -f "package.json" ]]; then
    echo "node"
  elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
    echo "python"
  elif [[ -f "Cargo.toml" ]]; then
    echo "rust"
  else
    echo "unknown"
  fi
}

STACK=$(detect_stack)

run_tests() {
  echo "--- Running tests ---"
  case "$STACK" in
    node)
      if npx --yes jest --version &>/dev/null 2>&1; then
        npx jest --coverage --coverageReporters=text-summary 2>&1 | tee "$LOG_DIR/test-output.log" | tail -6
      elif npx vitest --version &>/dev/null 2>&1; then
        npx vitest run --coverage 2>&1 | tee "$LOG_DIR/test-output.log" | tail -6
      else
        echo "No test runner found (jest or vitest expected)"
        PASS=false
      fi
      ;;
    python)
      if command -v pytest &>/dev/null; then
        pytest --tb=short --cov --cov-report=term-summary 2>&1 | tee "$LOG_DIR/test-output.log" | tail -6
      else
        echo "pytest not found"
        PASS=false
      fi
      ;;
    rust)
      cargo test 2>&1 | tee "$LOG_DIR/test-output.log" | tail -6
      ;;
    *)
      echo "Unknown stack — cannot run tests"
      PASS=false
      ;;
  esac

  if [[ ${PIPESTATUS[0]:-0} -ne 0 ]]; then
    echo "FAIL: Tests did not pass"
    PASS=false
  fi
}

check_coverage() {
  echo "--- Checking coverage ---"
  local coverage=0

  if [[ -f "$LOG_DIR/test-output.log" ]]; then
    # Extract coverage percentage from common formats
    coverage=$(grep -oP '(?:All files|TOTAL|Statements)\s*[|:]\s*\K[0-9]+(?:\.[0-9]+)?' "$LOG_DIR/test-output.log" | head -1 || echo "0")
  fi

  if [[ -z "$coverage" ]]; then
    coverage=0
  fi

  local cov_int=${coverage%.*}
  if (( cov_int < COVERAGE_THRESHOLD )); then
    echo "FAIL: Coverage: ${coverage}% — required: ${COVERAGE_THRESHOLD}%"
    PASS=false
  else
    echo "OK: Coverage: ${coverage}% (threshold: ${COVERAGE_THRESHOLD}%)"
  fi
}

run_lint() {
  echo "--- Running lint ---"
  case "$STACK" in
    node)
      if npx eslint --version &>/dev/null 2>&1; then
        npx eslint . --max-warnings=0 2>&1 | tee "$LOG_DIR/lint-output.log" | tail -3
      elif npx biome --version &>/dev/null 2>&1; then
        npx biome check . 2>&1 | tee "$LOG_DIR/lint-output.log" | tail -3
      else
        echo "No linter found — skipping"
        return
      fi
      ;;
    python)
      if command -v ruff &>/dev/null; then
        ruff check . 2>&1 | tee "$LOG_DIR/lint-output.log" | tail -3
      elif command -v flake8 &>/dev/null; then
        flake8 . 2>&1 | tee "$LOG_DIR/lint-output.log" | tail -3
      else
        echo "No linter found — skipping"
        return
      fi
      ;;
    rust)
      cargo clippy -- -D warnings 2>&1 | tee "$LOG_DIR/lint-output.log" | tail -3
      ;;
  esac

  if [[ ${PIPESTATUS[0]:-0} -ne 0 ]]; then
    echo "FAIL: Lint errors found (see $LOG_DIR/lint-output.log)"
    PASS=false
  fi
}

run_mutation_testing() {
  if [[ "$MUTATION_TESTING" != "true" ]]; then
    return
  fi

  echo "--- Running mutation testing ---"
  case "$STACK" in
    node)
      if npx stryker --version &>/dev/null 2>&1; then
        npx stryker run 2>&1 | tee "$LOG_DIR/mutation-output.log" | tail -5
      else
        echo "Stryker not installed — skipping mutation testing"
      fi
      ;;
    python)
      if command -v mutmut &>/dev/null; then
        mutmut run 2>&1 | tee "$LOG_DIR/mutation-output.log" | tail -5
      else
        echo "mutmut not installed — skipping mutation testing"
      fi
      ;;
  esac
}

echo "=== Pre-PR Quality Gate ==="
echo "Stack: $STACK | Coverage threshold: ${COVERAGE_THRESHOLD}%"
echo ""

run_tests
check_coverage
run_lint
run_mutation_testing

echo ""
if [[ "$PASS" == "true" ]]; then
  echo "=== All checks passed ==="
  exit 0
else
  echo "=== PR BLOCKED: Fix the above failures ==="
  echo "Full logs: $LOG_DIR/"
  exit 2
fi
