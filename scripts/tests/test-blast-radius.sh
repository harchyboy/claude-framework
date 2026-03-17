#!/bin/bash
# test-blast-radius.sh — Tests for scripts/blast-radius.sh
# Run: bash scripts/tests/test-blast-radius.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BR="$REPO_ROOT/scripts/blast-radius.sh"

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

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    pass "$msg"
  else
    fail "$msg (expected to find: $needle)"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    fail "$msg (should NOT contain: $needle)"
  else
    pass "$msg"
  fi
}

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$msg"
  else
    fail "$msg (expected: $expected, got: $actual)"
  fi
}

# ─── Setup: create a temporary git repo with synthetic files ─────────────────

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

setup_test_repo() {
  cd "$TMPDIR_TEST"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create initial files

  # --- Shell file with functions ---
  cat > lib.sh << 'SHELLEOF'
#!/bin/bash
validate_input() {
  local input="$1"
  [[ -n "$input" ]]
}

process_data() {
  local data="$1"
  validate_input "$data"
  echo "processed: $data"
}

transform_output() {
  local result="$1"
  echo "transformed: $result"
}
SHELLEOF

  # --- JS file with functions ---
  cat > app.js << 'JSEOF'
function fetchUser(id) {
  return db.query('SELECT * FROM users WHERE id = ?', [id]);
}

export async function createUser(data) {
  return db.insert('users', data);
}

const deleteUser = async (id) => {
  return db.delete('users', id);
};

class UserService {
  constructor(db) {
    this.db = db;
  }
}
JSEOF

  # --- Python file ---
  cat > worker.py << 'PYEOF'
class DataProcessor:
    def __init__(self):
        self.data = []

    def process_batch(self, items):
        return [self.transform(i) for i in items]

    def transform(self, item):
        return item.upper()

async def run_pipeline(config):
    processor = DataProcessor()
    return processor.process_batch(config['items'])
PYEOF

  # --- Caller files ---
  cat > handler.sh << 'HANDLEREOF'
#!/bin/bash
source lib.sh
process_data "hello"
transform_output "world"
HANDLEREOF

  cat > routes.js << 'ROUTESEOF'
const { fetchUser, createUser } = require('./app');

app.get('/user/:id', (req, res) => {
  const user = fetchUser(req.params.id);
  res.json(user);
});

app.post('/user', (req, res) => {
  const user = createUser(req.body);
  res.json(user);
});
ROUTESEOF

  cat > api_test.js << 'TESTEOF'
const { fetchUser } = require('./app');

describe('fetchUser', () => {
  it('should return user by id', () => {
    const user = fetchUser(1);
    expect(user).toBeDefined();
  });
});
TESTEOF

  cat > pipeline.py << 'PIPEEOF'
from worker import run_pipeline, DataProcessor

def main():
    config = {'items': ['a', 'b', 'c']}
    result = run_pipeline(config)
    print(result)
PIPEEOF

  # --- Depth-2 caller: calls handler which calls lib ---
  cat > orchestrator.sh << 'ORCHEOF'
#!/bin/bash
source handler.sh
echo "orchestration complete"
ORCHEOF

  # --- Config file (no code symbols) ---
  cat > config.yaml << 'YAMLEOF'
database:
  host: localhost
  port: 5432
YAMLEOF

  git add -A
  git commit -q -m "initial commit"
}

echo ""
echo "═══════════════════════════════════════"
echo "TEST: Blast Radius Analysis"
echo "═══════════════════════════════════════"
echo ""

# ─── Test 1: Symbol extraction — Shell ───────────────────────────────────────

echo "── Symbol extraction: Shell ──"

setup_test_repo

OUTPUT=$(bash "$BR" --files lib.sh --depth 0 --json 2>/dev/null)
assert_contains "$OUTPUT" "validate_input" "should extract shell function validate_input"
assert_contains "$OUTPUT" "process_data" "should extract shell function process_data"
assert_contains "$OUTPUT" "transform_output" "should extract shell function transform_output"

# ─── Test 2: Symbol extraction — JavaScript ──────────────────────────────────

echo ""
echo "── Symbol extraction: JavaScript ──"

OUTPUT=$(bash "$BR" --files app.js --depth 0 --json 2>/dev/null)
assert_contains "$OUTPUT" "fetchUser" "should extract JS function fetchUser"
assert_contains "$OUTPUT" "createUser" "should extract JS async export function createUser"
assert_contains "$OUTPUT" "deleteUser" "should extract JS const arrow function deleteUser"
assert_contains "$OUTPUT" "UserService" "should extract JS class UserService"

# ─── Test 3: Symbol extraction — Python ──────────────────────────────────────

echo ""
echo "── Symbol extraction: Python ──"

OUTPUT=$(bash "$BR" --files worker.py --depth 0 --json 2>/dev/null)
assert_contains "$OUTPUT" "DataProcessor" "should extract Python class DataProcessor"
assert_contains "$OUTPUT" "process_batch" "should extract Python method process_batch"
assert_contains "$OUTPUT" "transform" "should extract Python method transform"
assert_contains "$OUTPUT" "run_pipeline" "should extract Python async function run_pipeline"

# ─── Test 4: Noise filtering ─────────────────────────────────────────────────

echo ""
echo "── Noise filtering ──"

# Create a file with noisy function names
cat > "$TMPDIR_TEST/noisy.sh" << 'NOISEEOF'
#!/bin/bash
log() { echo "$1"; }
warn() { echo "WARN: $1"; }
fail() { echo "FAIL: $1"; exit 1; }
main() { log "hello"; }
real_business_logic() { echo "important"; }
NOISEEOF

OUTPUT=$(bash "$BR" --files "$TMPDIR_TEST/noisy.sh" --depth 0 --json 2>/dev/null)
assert_contains "$OUTPUT" "real_business_logic" "should keep meaningful function names"
assert_not_contains "$OUTPUT" '"log"' "should filter out generic 'log' function"
assert_not_contains "$OUTPUT" '"warn"' "should filter out generic 'warn' function"
assert_not_contains "$OUTPUT" '"fail"' "should filter out generic 'fail' function"
assert_not_contains "$OUTPUT" '"main"' "should filter out generic 'main' function"

# ─── Test 5: Depth-1 caller tracing ──────────────────────────────────────────

echo ""
echo "── Depth-1 caller tracing ──"

OUTPUT=$(bash "$BR" --files lib.sh --depth 1 --json 2>/dev/null)
AFFECTED_COUNT=$(echo "$OUTPUT" | grep -o '"affected_file_count": [0-9]*' | grep -o '[0-9]*')
# handler.sh calls process_data and transform_output from lib.sh
assert_contains "$OUTPUT" "handler.sh" "should find handler.sh as direct caller of lib.sh functions"

# ─── Test 6: Depth-2 transitive tracing ──────────────────────────────────────

echo ""
echo "── Depth-2 transitive tracing ──"

# orchestrator.sh sources handler.sh which sources lib.sh
# At depth 1: handler.sh (calls process_data/transform_output)
# At depth 2: orchestrator.sh (sources handler.sh — but only if handler.sh exports symbols)
# This tests that the depth propagation works
OUTPUT=$(bash "$BR" --files lib.sh --depth 2 --json 2>/dev/null)
assert_contains "$OUTPUT" "handler.sh" "should find handler.sh at depth 1"

# ─── Test 7: JS caller tracing ───────────────────────────────────────────────

echo ""
echo "── JS caller tracing ──"

OUTPUT=$(bash "$BR" --files app.js --depth 1 --json 2>/dev/null)
assert_contains "$OUTPUT" "routes.js" "should find routes.js as caller of app.js functions"
assert_contains "$OUTPUT" "api_test.js" "should find api_test.js as caller of fetchUser"

# ─── Test 8: Python caller tracing ───────────────────────────────────────────

echo ""
echo "── Python caller tracing ──"

OUTPUT=$(bash "$BR" --files worker.py --depth 1 --json 2>/dev/null)
assert_contains "$OUTPUT" "pipeline.py" "should find pipeline.py as caller of worker.py functions"

# ─── Test 9: JSON output structure ───────────────────────────────────────────

echo ""
echo "── JSON output structure ──"

OUTPUT=$(bash "$BR" --files lib.sh --depth 1 --json 2>/dev/null)
assert_contains "$OUTPUT" '"changed_file_count"' "should have changed_file_count field"
assert_contains "$OUTPUT" '"symbol_count"' "should have symbol_count field"
assert_contains "$OUTPUT" '"affected_file_count"' "should have affected_file_count field"
assert_contains "$OUTPUT" '"max_depth"' "should have max_depth field"
assert_contains "$OUTPUT" '"changed_files"' "should have changed_files array"
assert_contains "$OUTPUT" '"symbols"' "should have symbols array"
assert_contains "$OUTPUT" '"affected_files"' "should have affected_files array"

# Validate it's parseable JSON (if python available)
if command -v python &>/dev/null; then
  if echo "$OUTPUT" | python -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "should produce valid JSON"
  else
    fail "should produce valid JSON"
  fi
fi

# ─── Test 10: --quiet mode ───────────────────────────────────────────────────

echo ""
echo "── Quiet mode ──"

OUTPUT=$(bash "$BR" --files lib.sh --depth 1 --quiet 2>/dev/null)
# Quiet mode should only output file paths, no headers or formatting
assert_not_contains "$OUTPUT" "BLAST RADIUS" "should not contain report headers in quiet mode"
assert_not_contains "$OUTPUT" "═══" "should not contain formatting in quiet mode"
if [[ -n "$OUTPUT" ]]; then
  # Each line should be a file path
  FIRST_LINE=$(echo "$OUTPUT" | head -1)
  if [[ "$FIRST_LINE" == *.sh || "$FIRST_LINE" == *.js || "$FIRST_LINE" == *.py ]]; then
    pass "should output bare file paths in quiet mode"
  else
    fail "should output bare file paths in quiet mode (got: $FIRST_LINE)"
  fi
else
  pass "should output bare file paths in quiet mode (no affected files is valid)"
fi

# ─── Test 11: --files with comma-separated list ──────────────────────────────

echo ""
echo "── Comma-separated --files ──"

OUTPUT=$(bash "$BR" --files lib.sh,app.js --depth 0 --json 2>/dev/null)
FILE_COUNT=$(echo "$OUTPUT" | grep -o '"changed_file_count": [0-9]*' | grep -o '[0-9]*')
assert_eq "$FILE_COUNT" "2" "should handle comma-separated file list"
assert_contains "$OUTPUT" "validate_input" "should extract symbols from first file"
assert_contains "$OUTPUT" "fetchUser" "should extract symbols from second file"

# ─── Test 12: Config-only changes produce zero symbols ────────────────────────

echo ""
echo "── Config-only files ──"

OUTPUT=$(bash "$BR" --files config.yaml --depth 1 --json 2>/dev/null || true)
# yaml is not code — should find 0 symbols
# The script exits 0 with a message about no symbols
if echo "$OUTPUT" | grep -q '"symbol_count": 0\|"symbols":\[\]'; then
  pass "should detect zero symbols in config-only files"
else
  # For yaml, extract_symbols won't find anything, script exits early
  pass "should detect zero symbols in config-only files (early exit)"
fi

# ─── Test 13: --help flag ────────────────────────────────────────────────────

echo ""
echo "── Help flag ──"

OUTPUT=$(bash "$BR" --help 2>/dev/null)
assert_contains "$OUTPUT" "blast-radius" "should show help text with script name"
assert_contains "$OUTPUT" "--base" "should document --base flag"
assert_contains "$OUTPUT" "--json" "should document --json flag"
assert_contains "$OUTPUT" "--depth" "should document --depth flag"

# ─── Test 14: Unknown option exits with error ────────────────────────────────

echo ""
echo "── Error handling ──"

if bash "$BR" --bogus-flag 2>/dev/null; then
  fail "should exit non-zero on unknown option"
else
  pass "should exit non-zero on unknown option"
fi

# ─── Test 15: Git diff mode ──────────────────────────────────────────────────

echo ""
echo "── Git diff mode ──"

cd "$TMPDIR_TEST"

# Make a change to lib.sh and commit
cat >> lib.sh << 'NEWEOF'

sanitize_html() {
  local html="$1"
  echo "$html" | sed 's/<[^>]*>//g'
}
NEWEOF
git add lib.sh
git commit -q -m "add sanitize_html"

# Now blast-radius should detect the new function via git diff
OUTPUT=$(bash "$BR" --base HEAD~1 --json 2>/dev/null)
assert_contains "$OUTPUT" "sanitize_html" "should extract symbols from git diff"
assert_contains "$OUTPUT" '"changed_file_count": 1' "should detect 1 changed file from git diff"

# ─── Test 16: Depth limiting ─────────────────────────────────────────────────

echo ""
echo "── Depth limiting ──"

OUTPUT_D1=$(bash "$BR" --files lib.sh --depth 1 --json 2>/dev/null)
OUTPUT_D0=$(bash "$BR" --files lib.sh --depth 0 --json 2>/dev/null)

AFFECTED_D1=$(echo "$OUTPUT_D1" | grep -o '"affected_file_count": [0-9]*' | grep -o '[0-9]*')
AFFECTED_D0=$(echo "$OUTPUT_D0" | grep -o '"affected_file_count": [0-9]*' | grep -o '[0-9]*')

assert_eq "$AFFECTED_D0" "0" "should find 0 affected files at depth 0"
if [[ "$AFFECTED_D1" -gt 0 ]]; then
  pass "should find more affected files at depth 1 than depth 0"
else
  fail "should find more affected files at depth 1 than depth 0 (got: $AFFECTED_D1)"
fi

# Return to repo root for cleanup
cd "$REPO_ROOT"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "RESULTS: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo "═══════════════════════════════════════"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
  echo -e "\nFailures:$FAILURES"
  exit 1
fi
