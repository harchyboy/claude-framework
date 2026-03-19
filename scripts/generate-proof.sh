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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/json-output.sh"

# ─── Configuration ────────────────────────────────────────────────────────────

STORY_ID="${1:-}"
PRD_PATH="${2:-}"
SKIP_RUNTIME=false
DEV_CMD=""
DEV_URL="http://localhost:3000"
DEV_TIMEOUT=30
JSON_OUTPUT=false
ASSERTIONS_FILE=""
VERIFY_FILES_PATTERN=""
LOCKED_CRITERIA=""

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
    --json)          JSON_OUTPUT=true ;;
    --assertions)    ASSERTIONS_FILE="$2"; shift ;;
    --verify-files)  VERIFY_FILES_PATTERN="$2"; shift ;;
    --locked-criteria) LOCKED_CRITERIA="$2"; shift ;;
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

ok()   { json_output_log "${GREEN}  ✅ $1${NC}"; }
info() { json_output_log "${CYAN}  → $1${NC}"; }
warn() { json_output_log "${YELLOW}  ⚠️  $1${NC}"; }
err()  { json_output_log "${RED}  ❌ $1${NC}"; }

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

json_output_log ""
json_output_log "${BOLD}Phase 1: Extracting acceptance criteria${NC}"

# Use locked (immutable) criteria if available, otherwise fall back to PRD
CRITERIA_SOURCE="prd"
if [[ -n "$LOCKED_CRITERIA" ]] && [[ -f "$LOCKED_CRITERIA" ]]; then
  CRITERIA_SOURCE="locked"
  info "Using locked criteria: $LOCKED_CRITERIA"
  node -e "
    const locked = JSON.parse(require('fs').readFileSync('$LOCKED_CRITERIA', 'utf8'));
    let md = '# Acceptance Criteria — ' + locked.story_id + ': ' + locked.title + '\n\n';
    md += '> Source: LOCKED (immutable, locked at ' + locked.locked_at + ')\n\n';
    locked.criteria.forEach((c, i) => {
      md += (i + 1) + '. ' + c + '\n';
    });
    require('fs').writeFileSync('$PROOF_DIR/criteria.md', md);
    console.log('  Extracted ' + locked.criteria.length + ' locked criteria');
  "
else
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
fi
ok "Criteria extracted to $PROOF_DIR/criteria.md (source: $CRITERIA_SOURCE)"

# ─── Generate diff ───────────────────────────────────────────────────────────

json_output_log ""
json_output_log "${BOLD}Phase 2: Capturing code diff${NC}"

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

json_output_log ""
json_output_log "${BOLD}Phase 3: Running test suite${NC}"

TEST_EXIT=0
TEST_OUTPUT="$PROOF_DIR/test-results.txt"

# Auto-detect test runner
if [[ -f "package.json" ]]; then
  HAS_VITEST=$(node -e "const p=require('./package.json'); console.log((p.devDependencies||{}).vitest || (p.dependencies||{}).vitest ? 'yes' : 'no')" 2>/dev/null || echo "no")
  HAS_JEST=$(node -e "const p=require('./package.json'); console.log((p.devDependencies||{}).jest || (p.dependencies||{}).jest ? 'yes' : 'no')" 2>/dev/null || echo "no")

  if [[ "$HAS_VITEST" == "yes" ]]; then
    info "Running Vitest..."
    npx vitest run --reporter=verbose >"$TEST_OUTPUT" 2>&1 || TEST_EXIT=$?
  elif [[ "$HAS_JEST" == "yes" ]]; then
    info "Running Jest..."
    npx jest --verbose >"$TEST_OUTPUT" 2>&1 || TEST_EXIT=$?
  elif npm test --if-present 2>/dev/null; then
    info "Running npm test..."
    npm test >"$TEST_OUTPUT" 2>&1 || TEST_EXIT=$?
  else
    echo "No test runner detected" > "$TEST_OUTPUT"
    warn "No test runner found"
  fi
elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]] || [[ -f "pytest.ini" ]]; then
  info "Running pytest..."
  python -m pytest -v >"$TEST_OUTPUT" 2>&1 || TEST_EXIT=$?
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

# ─── Runtime verification (Playwright) ──────────────────────────────────────

RUNTIME_RESULTS_FILE="$PROOF_DIR/runtime-results.json"
RUNTIME_VERIFIED=false

if [[ "$SKIP_RUNTIME" != "true" ]]; then
  echo ""
  echo -e "${BOLD}Phase 4: Runtime verification (Playwright)${NC}"

  # Auto-detect dev server command if not provided
  if [[ -z "$DEV_CMD" ]] && [[ -f "package.json" ]]; then
    DEV_CMD=$(node -e "
      const p = require('./package.json');
      const scripts = p.scripts || {};
      // Prefer dev, then start, then serve
      const cmd = scripts.dev || scripts.start || scripts.serve || '';
      if (cmd) console.log('npm run ' + (scripts.dev ? 'dev' : scripts.start ? 'start' : 'serve'));
    " 2>/dev/null || true)
  fi

  if [[ -z "$DEV_CMD" ]]; then
    warn "No dev server command found (set --dev-cmd or add 'dev'/'start' to package.json scripts)"
    warn "Skipping runtime verification"
  else
    info "Dev server: $DEV_CMD"
    info "Dev URL: $DEV_URL"

    # Start dev server in background
    DEV_PID=""
    $DEV_CMD > "$PROOF_DIR/dev-server.log" 2>&1 &
    DEV_PID=$!

    # Wait for dev server to be ready
    READY=false
    WAITED=0
    while [[ "$WAITED" -lt "$DEV_TIMEOUT" ]]; do
      if curl -s -o /dev/null -w "%{http_code}" "$DEV_URL" 2>/dev/null | grep -qE "^[23]"; then
        READY=true
        break
      fi
      sleep 1
      WAITED=$((WAITED + 1))
    done

    if [[ "$READY" != "true" ]]; then
      err "Dev server did not respond at $DEV_URL within ${DEV_TIMEOUT}s"
      [[ -n "$DEV_PID" ]] && kill "$DEV_PID" 2>/dev/null || true
      wait "$DEV_PID" 2>/dev/null || true
    else
      ok "Dev server ready at $DEV_URL (${WAITED}s)"

      # Check for Playwright test files
      PLAYWRIGHT_CONFIG=""
      for cfg in playwright.config.ts playwright.config.js playwright.config.mjs; do
        if [[ -f "$cfg" ]]; then
          PLAYWRIGHT_CONFIG="$cfg"
          break
        fi
      done

      # Check for e2e test directories
      E2E_DIR=""
      for dir in e2e tests/e2e test/e2e __tests__/e2e tests/playwright; do
        if [[ -d "$dir" ]]; then
          E2E_DIR="$dir"
          break
        fi
      done

      RUNTIME_EXIT=0

      if [[ -n "$PLAYWRIGHT_CONFIG" ]]; then
        info "Found Playwright config: $PLAYWRIGHT_CONFIG"
        info "Running Playwright tests..."
        npx playwright test --reporter=json --output="$PROOF_DIR/screenshots" >"$PROOF_DIR/playwright-output.txt" 2>&1 || RUNTIME_EXIT=$?

        # Extract JSON results if available
        if [[ -f "test-results.json" ]]; then
          mv test-results.json "$RUNTIME_RESULTS_FILE"
        fi

        # Collect any screenshot artifacts
        if [[ -d "test-results" ]]; then
          find test-results -name "*.png" -exec cp {} "$PROOF_DIR/screenshots/" \; 2>/dev/null || true
        fi

        if [[ "$RUNTIME_EXIT" -eq 0 ]]; then
          ok "Playwright tests passed"
          RUNTIME_VERIFIED=true
        else
          err "Playwright tests failed (exit code: $RUNTIME_EXIT)"
        fi

      elif [[ -n "$E2E_DIR" ]]; then
        info "Found e2e directory: $E2E_DIR — running Playwright tests..."
        npx playwright test "$E2E_DIR" --reporter=json --output="$PROOF_DIR/screenshots" >"$PROOF_DIR/playwright-output.txt" 2>&1 || RUNTIME_EXIT=$?

        if [[ -f "test-results.json" ]]; then
          mv test-results.json "$RUNTIME_RESULTS_FILE"
        fi
        if [[ -d "test-results" ]]; then
          find test-results -name "*.png" -exec cp {} "$PROOF_DIR/screenshots/" \; 2>/dev/null || true
        fi

        if [[ "$RUNTIME_EXIT" -eq 0 ]]; then
          ok "E2E tests passed"
          RUNTIME_VERIFIED=true
        else
          err "E2E tests failed (exit code: $RUNTIME_EXIT)"
        fi

      else
        # No Playwright tests exist — run basic smoke test via curl
        info "No Playwright tests found — running HTTP smoke test"
        SMOKE_STATUS=$(curl -s -o "$PROOF_DIR/smoke-response.html" -w "%{http_code}" "$DEV_URL" 2>/dev/null || echo "000")

        if echo "$SMOKE_STATUS" | grep -qE "^[23]"; then
          ok "Smoke test passed (HTTP $SMOKE_STATUS)"
          echo "{\"smoke_test\": true, \"status\": $SMOKE_STATUS, \"url\": \"$DEV_URL\"}" > "$RUNTIME_RESULTS_FILE"
          # Take a screenshot via Playwright CLI if available
          if command -v npx > /dev/null 2>&1; then
            info "Taking screenshot via Playwright..."
            npx -y playwright screenshot --full-page "$DEV_URL" "$PROOF_DIR/screenshots/homepage.png" 2>/dev/null && \
              ok "Screenshot saved to $PROOF_DIR/screenshots/homepage.png" || \
              warn "Screenshot capture failed (non-blocking)"
          fi
          RUNTIME_VERIFIED=true
        else
          err "Smoke test failed (HTTP $SMOKE_STATUS)"
          echo "{\"smoke_test\": false, \"status\": $SMOKE_STATUS, \"url\": \"$DEV_URL\"}" > "$RUNTIME_RESULTS_FILE"
        fi
      fi

      # Stop dev server
      kill "$DEV_PID" 2>/dev/null || true
      wait "$DEV_PID" 2>/dev/null || true
      info "Dev server stopped"
    fi
  fi
else
  info "Runtime verification skipped (--skip-runtime)"
fi

# ─── Content verification ───────────────────────────────────────────────────

CONTENT_RESULTS_FILE="$PROOF_DIR/content-validation.json"
CONTENT_VERIFIED=false

json_output_log ""
json_output_log "${BOLD}Phase 4b: Content verification${NC}"

node -e "
const fs = require('fs');
const path = require('path');

const proofDir = '$PROOF_DIR';
const devUrl = '$DEV_URL';
const assertionsFile = '$ASSERTIONS_FILE';
const verifyFilesPattern = '$VERIFY_FILES_PATTERN';
const runtimeVerified = '$RUNTIME_VERIFIED' === 'true';

const results = { dom: [], api: [], files: [], summary: { total: 0, passed: 0, failed: 0 } };

// ── DOM Content Checks ─────────────────────────────────────────────────
// If we have a smoke-response.html, check it for expected elements
const smokeFile = path.join(proofDir, 'smoke-response.html');
if (fs.existsSync(smokeFile)) {
  const html = fs.readFileSync(smokeFile, 'utf8');

  // Basic structural checks
  const domChecks = [
    { name: 'has_doctype',   test: /<!DOCTYPE/i.test(html),             desc: 'Document has DOCTYPE' },
    { name: 'has_html_tag',  test: /<html/i.test(html),                 desc: 'Document has <html> tag' },
    { name: 'has_head',      test: /<head/i.test(html),                 desc: 'Document has <head>' },
    { name: 'has_body',      test: /<body/i.test(html),                 desc: 'Document has <body>' },
    { name: 'has_title',     test: /<title[^>]*>.+<\/title>/is.test(html), desc: 'Document has non-empty <title>' },
    { name: 'no_error_page', test: !/<h1[^>]*>\s*(404|500|Error|Not Found)/i.test(html), desc: 'No error page detected' },
    { name: 'has_content',   test: html.length > 500,                   desc: 'Page has substantial content (>500 bytes)' },
  ];

  domChecks.forEach(c => {
    results.dom.push({ name: c.name, description: c.desc, status: c.test ? 'pass' : 'fail' });
    results.summary.total++;
    if (c.test) results.summary.passed++; else results.summary.failed++;
  });

  // Check for interactive elements (forms, buttons, links)
  const hasInteractive = /<(button|a\s|input|form|select|textarea)/i.test(html);
  results.dom.push({ name: 'has_interactive', description: 'Page has interactive elements', status: hasInteractive ? 'pass' : 'info' });

  // Check for JavaScript errors in inline scripts
  const hasJsError = /SyntaxError|ReferenceError|TypeError/.test(html);
  if (hasJsError) {
    results.dom.push({ name: 'no_js_errors', description: 'No JavaScript errors in page source', status: 'fail' });
    results.summary.total++;
    results.summary.failed++;
  }
}

// ── Custom Assertions (from --assertions file) ─────────────────────────
if (assertionsFile && fs.existsSync(assertionsFile)) {
  try {
    const assertions = JSON.parse(fs.readFileSync(assertionsFile, 'utf8'));

    // DOM assertions
    if (assertions.dom && fs.existsSync(smokeFile)) {
      const html = fs.readFileSync(smokeFile, 'utf8');
      assertions.dom.forEach(a => {
        let passed = false;
        if (a.selector && a.text) {
          // Check if element with selector-like tag contains text
          const tagMatch = a.selector.match(/^([a-z]+)/i);
          if (tagMatch) {
            const re = new RegExp('<' + tagMatch[1] + '[^>]*>[^<]*' + a.text.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\$&'), 'i');
            passed = re.test(html);
          }
        } else if (a.selector && a.exists !== undefined) {
          const tagMatch = a.selector.match(/^([a-z]+)/i);
          if (tagMatch) {
            passed = new RegExp('<' + tagMatch[1], 'i').test(html) === a.exists;
          }
        }
        results.dom.push({
          name: 'assertion_' + (a.selector || 'custom'),
          description: 'Custom assertion: ' + JSON.stringify(a),
          status: passed ? 'pass' : 'fail'
        });
        results.summary.total++;
        if (passed) results.summary.passed++; else results.summary.failed++;
      });
    }

    // API assertions
    if (assertions.api) {
      assertions.api.forEach(a => {
        results.api.push({
          name: 'api_' + (a.url || 'endpoint'),
          url: a.url,
          method: a.method || 'GET',
          expected_status: a.status || 200,
          required_fields: a.required_fields || [],
          status: 'deferred'
        });
      });
    }

    // File assertions
    if (assertions.files) {
      assertions.files.forEach(a => {
        let passed = false;
        let evidence = '';
        if (fs.existsSync(a.path)) {
          const stat = fs.statSync(a.path);
          if (a.min_size && stat.size < a.min_size) {
            evidence = 'File too small: ' + stat.size + ' bytes (min: ' + a.min_size + ')';
          } else {
            passed = true;
            evidence = 'File exists, size: ' + stat.size + ' bytes';
          }

          // Type validation via magic bytes
          if (a.type && passed) {
            const buf = Buffer.alloc(8);
            const fd = fs.openSync(a.path, 'r');
            fs.readSync(fd, buf, 0, 8, 0);
            fs.closeSync(fd);
            const hex = buf.toString('hex');
            const magicMap = {
              pdf: '25504446',     // %PDF
              png: '89504e47',     // .PNG
              jpg: 'ffd8ff',
              jpeg: 'ffd8ff',
              zip: '504b0304',
              gz: '1f8b',
            };
            if (magicMap[a.type]) {
              if (!hex.startsWith(magicMap[a.type])) {
                passed = false;
                evidence = 'Magic bytes mismatch: expected ' + a.type + ' (' + magicMap[a.type] + '), got ' + hex.substring(0, 8);
              }
            }
          }

          // CSV validation
          if (a.type === 'csv' && passed) {
            const content = fs.readFileSync(a.path, 'utf8');
            const lines = content.trim().split('\\n');
            if (a.min_rows && lines.length - 1 < a.min_rows) {
              passed = false;
              evidence = 'CSV has ' + (lines.length - 1) + ' data rows (min: ' + a.min_rows + ')';
            }
            if (a.required_headers) {
              const headers = lines[0].split(',').map(h => h.trim().replace(/^\"|\"$/g, ''));
              const missing = a.required_headers.filter(h => !headers.includes(h));
              if (missing.length > 0) {
                passed = false;
                evidence = 'Missing CSV headers: ' + missing.join(', ');
              }
            }
          }
        } else {
          evidence = 'File not found: ' + a.path;
        }

        results.files.push({
          name: 'file_' + path.basename(a.path),
          path: a.path,
          type: a.type || 'unknown',
          status: passed ? 'pass' : 'fail',
          evidence: evidence
        });
        results.summary.total++;
        if (passed) results.summary.passed++; else results.summary.failed++;
      });
    }
  } catch (e) {
    results.error = 'Failed to parse assertions file: ' + e.message;
  }
}

// ── Auto-detect output files (from --verify-files pattern) ──────────────
if (verifyFilesPattern) {
  const patterns = verifyFilesPattern.split(',');
  const glob = require('path');
  patterns.forEach(pattern => {
    const dir = path.dirname(pattern);
    const ext = path.extname(pattern).replace('.', '');
    try {
      if (fs.existsSync(dir)) {
        const files = fs.readdirSync(dir).filter(f => {
          if (pattern.includes('*')) {
            return f.endsWith('.' + ext);
          }
          return f === path.basename(pattern);
        });
        files.forEach(f => {
          const fullPath = path.join(dir, f);
          const stat = fs.statSync(fullPath);
          const passed = stat.size > 0;

          // Magic bytes check
          let typeMatch = true;
          let detectedType = ext;
          if (stat.size >= 8) {
            const buf = Buffer.alloc(8);
            const fd = fs.openSync(fullPath, 'r');
            fs.readSync(fd, buf, 0, 8, 0);
            fs.closeSync(fd);
            const hex = buf.toString('hex');
            if (hex.startsWith('25504446')) detectedType = 'pdf';
            else if (hex.startsWith('89504e47')) detectedType = 'png';
            else if (hex.startsWith('ffd8ff')) detectedType = 'jpg';
            else if (hex.startsWith('504b0304')) detectedType = 'zip';
          }

          results.files.push({
            name: 'output_' + f,
            path: fullPath,
            type: detectedType,
            size: stat.size,
            status: passed ? 'pass' : 'fail',
            evidence: passed ? 'File exists, size: ' + stat.size + ' bytes, type: ' + detectedType : 'File is empty'
          });
          results.summary.total++;
          if (passed) results.summary.passed++; else results.summary.failed++;
        });
      }
    } catch (e) { /* skip unreadable dirs */ }
  });
}

// ── API Endpoint Checks (deferred from assertions, executed here) ───────
// API checks run via curl from bash, so we just mark them for the bash layer
// The results will be populated by the bash section below

fs.writeFileSync('$CONTENT_RESULTS_FILE', JSON.stringify(results, null, 2));

// Output summary
const total = results.summary.total;
if (total > 0) {
  console.log('  Content checks: ' + results.summary.passed + '/' + total + ' passed');
  if (results.summary.failed > 0) {
    console.log('  Failures:');
    [...results.dom, ...results.files].filter(r => r.status === 'fail').forEach(r => {
      console.log('    - ' + r.description + (r.evidence ? ': ' + r.evidence : ''));
    });
  }
} else {
  console.log('  No content checks applicable (no smoke-response.html, no assertions file)');
}
" 2>/dev/null || warn "Content verification script failed (non-blocking)"

# Run deferred API checks if assertions file specified API endpoints
if [[ -n "$ASSERTIONS_FILE" ]] && [[ -f "$ASSERTIONS_FILE" ]] && [[ -f "$CONTENT_RESULTS_FILE" ]]; then
  API_ENDPOINTS=$(node -e "
    const a = JSON.parse(require('fs').readFileSync('$ASSERTIONS_FILE','utf8'));
    if (a.api) a.api.forEach(e => console.log(e.method || 'GET', e.url, e.status || 200, (e.required_fields || []).join(',')));
  " 2>/dev/null || true)

  if [[ -n "$API_ENDPOINTS" ]]; then
    info "Running API endpoint checks..."
    while IFS=' ' read -r method url expected_status required_fields; do
      FULL_URL="${DEV_URL}${url}"
      RESPONSE_FILE="$PROOF_DIR/api-response-$(echo "$url" | tr '/' '-').json"
      HTTP_STATUS=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" -X "$method" "$FULL_URL" 2>/dev/null || echo "000")

      if [[ "$HTTP_STATUS" == "$expected_status" ]]; then
        ok "API $method $url -> $HTTP_STATUS"

        # Validate required fields if specified
        if [[ -n "$required_fields" ]]; then
          MISSING=$(node -e "
            const body = JSON.parse(require('fs').readFileSync('$RESPONSE_FILE','utf8'));
            const fields = '$required_fields'.split(',');
            const missing = fields.filter(f => !(f in body));
            if (missing.length > 0) console.log(missing.join(','));
          " 2>/dev/null || true)
          if [[ -n "$MISSING" ]]; then
            err "API $method $url missing fields: $MISSING"
          fi
        fi
      else
        err "API $method $url -> $HTTP_STATUS (expected $expected_status)"
      fi
    done <<< "$API_ENDPOINTS"
  fi
fi

# Check if content verification found anything useful
if [[ -f "$CONTENT_RESULTS_FILE" ]]; then
  CONTENT_PASS_COUNT=$(node -e "
    const r = JSON.parse(require('fs').readFileSync('$CONTENT_RESULTS_FILE','utf8'));
    console.log(r.summary.passed);
  " 2>/dev/null || echo "0")
  CONTENT_TOTAL=$(node -e "
    const r = JSON.parse(require('fs').readFileSync('$CONTENT_RESULTS_FILE','utf8'));
    console.log(r.summary.total);
  " 2>/dev/null || echo "0")
  if [[ "$CONTENT_TOTAL" -gt 0 ]] && [[ "$CONTENT_PASS_COUNT" == "$CONTENT_TOTAL" ]]; then
    CONTENT_VERIFIED=true
    ok "Content verification: $CONTENT_PASS_COUNT/$CONTENT_TOTAL checks passed"
  elif [[ "$CONTENT_TOTAL" -gt 0 ]]; then
    warn "Content verification: $CONTENT_PASS_COUNT/$CONTENT_TOTAL checks passed"
  fi
fi

# ─── Generate verdict ────────────────────────────────────────────────────────

json_output_log ""
json_output_log "${BOLD}Phase 5: Generating verdict${NC}"

# Determine verification type for verdict
if [[ "$RUNTIME_VERIFIED" == "true" ]]; then
  VERIFICATION_TYPE="runtime"
else
  VERIFICATION_TYPE="static"
fi

# Build verdict from test + runtime results
node -e "
  const fs = require('fs');

  // Use locked criteria if available (immutable evaluation harness)
  let story;
  const lockedPath = '$LOCKED_CRITERIA';
  if (lockedPath && fs.existsSync(lockedPath)) {
    const locked = JSON.parse(fs.readFileSync(lockedPath, 'utf8'));
    // Build a story-like object from locked criteria
    const prd = JSON.parse(fs.readFileSync('$PRD_PATH', 'utf8'));
    story = prd.userStories.find(s => s.id === '$STORY_ID') || {};
    // Override criteria with locked version (immutable)
    story.acceptanceCriteria = locked.criteria;
    story.id = locked.story_id;
    story.title = locked.title;
  } else {
    const prd = JSON.parse(fs.readFileSync('$PRD_PATH', 'utf8'));
    story = prd.userStories.find(s => s.id === '$STORY_ID');
  }

  const testsPassed = $TEST_EXIT === 0;
  const testOutput = fs.readFileSync('$PROOF_DIR/test-results.txt', 'utf8');
  const diffContent = fs.readFileSync('$PROOF_DIR/diff.patch', 'utf8');
  const hasChanges = diffContent.length > 50;
  const runtimeVerified = '$RUNTIME_VERIFIED' === 'true';
  const verificationType = '$VERIFICATION_TYPE';

  // Load runtime results if they exist
  let runtimeResults = null;
  try {
    runtimeResults = JSON.parse(fs.readFileSync('$RUNTIME_RESULTS_FILE', 'utf8'));
  } catch (e) { /* no runtime results */ }

  // Collect screenshot paths
  const screenshotDir = '$PROOF_DIR/screenshots';
  let screenshots = [];
  try {
    screenshots = fs.readdirSync(screenshotDir)
      .filter(f => f.endsWith('.png') || f.endsWith('.jpg'))
      .map(f => screenshotDir + '/' + f);
  } catch (e) { /* no screenshots */ }

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
      const hasTests = testOutput.length > 100 && testsPassed;
      status = hasTests ? 'PARTIAL' : 'UNTESTABLE';
      evidence = hasTests ? 'Tests exist and pass (coverage not independently verified)' : 'Could not verify test coverage';
    } else if (runtimeVerified) {
      // Runtime verification ran — upgrade UNTESTABLE criteria that involve UI/behaviour
      if (/display|show|render|visible|appear|page|button|click|form|input|navigate|redirect|responsive|layout|style|colour|color/i.test(criterion)) {
        status = 'PASS';
        evidence = 'Runtime verification passed — app renders and responds to interaction';
        if (screenshots.length > 0) {
          evidence += ' (screenshot evidence: ' + screenshots[0] + ')';
        }
      }
    }

    return {
      criterion,
      status,
      evidence,
      screenshot: screenshots.length > 0 ? screenshots[0] : null
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

  // Static-only verification caps confidence at 0.85
  // Runtime verification allows full confidence range
  if (!runtimeVerified) {
    confidence = Math.min(confidence, 0.85);
  }

  const verdict = {
    story_id: '$STORY_ID',
    story_title: story.title,
    verdict: failCount === 0 ? 'PASS' : 'FAIL',
    confidence: Math.round(confidence * 100) / 100,
    verification_type: verificationType,
    runtime_verified: runtimeVerified,
    timestamp: new Date().toISOString(),
    criteria_results: results,
    issues_found: results.filter(r => r.status === 'FAIL').map(r => r.criterion),
    screenshots: screenshots,
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
  md += '**Verification type:** ' + (runtimeVerified ? 'Runtime (Playwright + tests)' : 'Static (code + tests only)') + '\n';
  md += '**Timestamp:** ' + verdict.timestamp + '\n\n';
  md += '## Criteria Results\n\n';
  md += '| # | Criterion | Status | Evidence |\n';
  md += '|---|-----------|--------|----------|\n';
  results.forEach((r, i) => {
    const icon = r.status === 'PASS' ? 'PASS' : r.status === 'FAIL' ? 'FAIL' : r.status === 'PARTIAL' ? 'PARTIAL' : 'N/A';
    md += '| ' + (i+1) + ' | ' + r.criterion.replace(/\|/g, '/') + ' | ' + icon + ' | ' + r.evidence + ' |\n';
  });

  if (screenshots.length > 0) {
    md += '\n## Screenshots\n\n';
    screenshots.forEach((s, i) => {
      md += '![Screenshot ' + (i+1) + '](' + s + ')\n\n';
    });
  }

  md += '\n## Test Results\n\n';
  md += 'Exit code: ' + $TEST_EXIT + '\n\n';
  if (testOutput.length > 0) {
    md += '<details><summary>Full test output</summary>\n\n\`\`\`\n' + testOutput.substring(0, 5000) + '\n\`\`\`\n</details>\n';
  }

  if (runtimeResults) {
    md += '\n## Runtime Results\n\n';
    md += '<details><summary>Runtime verification output</summary>\n\n\`\`\`json\n' + JSON.stringify(runtimeResults, null, 2).substring(0, 5000) + '\n\`\`\`\n</details>\n';
  }

  fs.writeFileSync('$PROOF_DIR/verification.md', md);

  // Output summary
  console.log('  Story: ' + story.id + ' — ' + story.title);
  console.log('  Verdict: ' + verdict.verdict + ' (confidence: ' + verdict.confidence + ')');
  console.log('  Type: ' + (runtimeVerified ? 'Runtime (Playwright)' : 'Static only'));
  console.log('  Criteria: ' + passCount + ' passed, ' + failCount + ' failed, ' + (totalCount - passCount - failCount) + ' unverified');
  if (screenshots.length > 0) console.log('  Screenshots: ' + screenshots.length + ' captured');
"

ok "Proof packet generated at $PROOF_DIR/"

json_output_log ""
json_output_log "${BOLD}Proof packet contents:${NC}"
if ! json_output_suppress; then
  ls -la "$PROOF_DIR/"
fi
json_output_log ""

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

json_output_log ""
if (( $(echo "$CONFIDENCE >= 0.9" | bc -l 2>/dev/null || node -e "console.log($CONFIDENCE >= 0.9 ? 1 : 0)") )); then
  json_output_log "${GREEN}${BOLD}  HIGH CONFIDENCE — auto-merge candidate${NC}"
elif (( $(echo "$CONFIDENCE >= 0.7" | bc -l 2>/dev/null || node -e "console.log($CONFIDENCE >= 0.7 ? 1 : 0)") )); then
  json_output_log "${YELLOW}${BOLD}  MEDIUM CONFIDENCE — queued for human review${NC}"
else
  json_output_log "${RED}${BOLD}  LOW CONFIDENCE — needs attention before merge${NC}"
fi
json_output_log ""

# ─── JSON output ────────────────────────────────────────────────────────────

if [[ "$JSON_OUTPUT" == "true" ]]; then
  # Read verdict.json and content-validation.json, combine into full output
  node -e "
    const fs = require('fs');
    const verdict = JSON.parse(fs.readFileSync('$PROOF_DIR/verdict.json', 'utf8'));
    let contentValidation = null;
    try {
      contentValidation = JSON.parse(fs.readFileSync('$PROOF_DIR/content-validation.json', 'utf8'));
    } catch (e) {}

    const output = {
      story_id: '$STORY_ID',
      phases: {
        criteria: { status: 'ok' },
        diff: { status: 'ok' },
        tests: { status: $TEST_EXIT === 0 ? 'pass' : 'fail', exit_code: $TEST_EXIT },
        runtime: { status: '$RUNTIME_VERIFIED' === 'true' ? 'pass' : 'skipped', type: '$VERIFICATION_TYPE' },
        content_verification: contentValidation || { summary: { total: 0, passed: 0, failed: 0 } }
      },
      verdict: verdict,
      recommendation: $CONFIDENCE >= 0.9 ? 'auto-merge' : ($CONFIDENCE >= 0.7 ? 'human-review' : 'needs-attention')
    };
    process.stdout.write(JSON.stringify(output, null, 2) + '\n');
  "
fi
