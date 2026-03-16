#!/bin/bash
# ralph.sh — Autonomous PRD-driven development loop
# Hartz Claude Framework — synthesised from Anthropic's C compiler project + harchyboy/ralph-moss
#
# Usage: bash scripts/ralph.sh [max_iterations] [options]
#
# Options:
#   --max-plan          Track iterations not cost (Anthropic Max plan users)
#   --max-cost <n>      Hard stop if total cost exceeds $n
#   --quality-gate      Run typecheck/lint/tests after each iteration
#   --review            Spawn review agent after implementation
#   --strict            Fail on lint warnings
#   --model <id>        Override Claude model (default: claude-sonnet-4-6)
#   --skip-tests        Skip tests in quality gate
#   --skip-preflight    Skip PRD validation
#   --no-cost           Disable cost tracking
#   --timeout <min>     Per-iteration timeout in minutes (default: 30)
#   --telemetry         Send telemetry events to Hartz Command API
#   --telemetry-url <u> Hartz Command server URL (default: http://localhost:3001)
#   --verify            Run independent verification after each story (generates proof packets)
#   --verify-runtime    Include Playwright runtime verification (requires running dev server)
#   --dev-cmd <cmd>     Dev server start command for runtime verification
#   --dev-url <url>     Dev server URL (default: http://localhost:3000)
#   --docker            Run Claude inside Docker container with network isolation
#   --auto-pr           Auto-create GitHub PR when verification passes (confidence >= 0.9)
#   --pr-threshold <n>  Confidence threshold for auto-PR (default: 0.9)
#   --hooks-dir <path>  Directory for lifecycle hook scripts (default: scripts/ralph-hooks/)
#   --stall-timeout <m> Kill agent if no output for N minutes (default: 5, 0=disable)
#   --no-backoff        Disable exponential backoff on story retries
#   --use-local         Enable Ollama pre-generation for test/doc stories (default: on)
#   --no-local          Disable Ollama auto-routing, always use Claude
#   --help              Show this help

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

MAX_ITERATIONS=20
USE_MAX_PLAN=false
MAX_COST=""
MODEL_OVERRIDE=""
QUALITY_GATE=false
REVIEW=false
STRICT=false
SKIP_TESTS=false
SKIP_PREFLIGHT=false
TRACK_COST=true
TOTAL_COST=0
ITER_TIMEOUT=30
TELEMETRY=false
TELEMETRY_URL="http://localhost:3001"
RUN_ID=""
VERIFY=false
VERIFY_RUNTIME=false
DEV_CMD=""
DEV_URL="http://localhost:3000"
USE_DOCKER=false
AUTO_PR=false
PR_THRESHOLD="0.9"
HOOKS_DIR="scripts/ralph-hooks/"
USE_LOCAL=true   # Auto-route local-eligible stories to Ollama when available
HOOK_TIMEOUT=60
STALL_TIMEOUT=5  # Minutes of no output before killing agent (0=disabled)
BACKOFF_ENABLED=true  # Exponential backoff on same-story retries
STALL_GRACE=60   # Seconds of grace period at startup before stall detection activates
START_TIME=$(date +%s)
STALE_LOCK_HOURS=2
CONFIG_LAST_MTIME=""   # Track ralph-config.json mtime for dynamic reload

# Override max_iterations only if first positional arg is a number
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
  MAX_ITERATIONS="$1"
  shift
fi

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-plan)      USE_MAX_PLAN=true ;;
    --max-cost)      MAX_COST="$2"; shift ;;
    --model)         MODEL_OVERRIDE="$2"; shift ;;
    --quality-gate)  QUALITY_GATE=true ;;
    --review)        REVIEW=true ;;
    --strict)        STRICT=true ;;
    --skip-tests)    SKIP_TESTS=true ;;
    --skip-preflight) SKIP_PREFLIGHT=true ;;
    --no-cost)       TRACK_COST=false ;;
    --timeout)       ITER_TIMEOUT="$2"; shift ;;
    --telemetry)     TELEMETRY=true ;;
    --telemetry-url) TELEMETRY_URL="$2"; shift ;;
    --verify)        VERIFY=true ;;
    --verify-runtime) VERIFY_RUNTIME=true; VERIFY=true ;;
    --dev-cmd)       DEV_CMD="$2"; shift ;;
    --dev-url)       DEV_URL="$2"; shift ;;
    --docker)        USE_DOCKER=true ;;
    --auto-pr)       AUTO_PR=true ;;
    --pr-threshold)  PR_THRESHOLD="$2"; shift ;;
    --hooks-dir)     HOOKS_DIR="$2"; shift ;;
    --stall-timeout) STALL_TIMEOUT="$2"; shift ;;
    --no-backoff)    BACKOFF_ENABLED=false ;;
    --use-local)     USE_LOCAL=true ;;
    --no-local)      USE_LOCAL=false ;;
    --help)
      sed -n '2,21p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# ─── Helper: count pending stories (uses node, not python3) ─────────────────

count_pending() {
  local prd_file="$1"
  node -e "
    const prd = JSON.parse(require('fs').readFileSync('$prd_file', 'utf8'));
    const pending = prd.userStories.filter(s => !s.passes && !s.stuck);
    console.log(pending.length);
  " 2>/dev/null || echo "0"
}

# ─── Helper: classify story type from title/description ──────────────────────
# Returns: test-scaffold | docs | lint-fix | boilerplate | feature (default)

classify_story() {
  local title="${1:-}"
  local desc="${2:-}"
  local combined
  combined=$(echo "$title $desc" | tr '[:upper:]' '[:lower:]')

  if echo "$combined" | grep -qE "write test|generate test|add test|unit test|spec file|test scaffold|test for|tests for"; then
    echo "test-scaffold"
  elif echo "$combined" | grep -qE "jsdoc|docstring|readme|documentation|add comment|annotate|document (the|all|public)|write doc"; then
    echo "docs"
  elif echo "$combined" | grep -qE "^lint|fix lint|fix warning|unused import|format (the|all|files)|prettier|eslint fix"; then
    echo "lint-fix"
  elif echo "$combined" | grep -qE "boilerplate|scaffold|template|stub|placeholder|crud (for|component|service)"; then
    echo "boilerplate"
  else
    echo "feature"
  fi
}

# ─── Helper: run local pre-generation for eligible stories ───────────────────
# Writes files directly, returns 0 if successful and quality gate passes

run_local_prereq() {
  local story_id="$1"
  local story_title="$2"
  local story_type="$3"
  local work_dir="${WORKTREE_PATH:-$(pwd)}"
  local scripts_dir

  # Find scripts dir relative to repo root
  if [[ -f "scripts/local-model.sh" ]]; then
    scripts_dir="scripts"
  elif [[ -f "../scripts/local-model.sh" ]]; then
    scripts_dir="../scripts"
  else
    echo "  ⚠️  local-model.sh not found — skipping local pre-generation" >&2
    return 1
  fi

  # Check Ollama is reachable
  if ! curl -sf --max-time 2 "${OLLAMA_HOST:-http://localhost:11434}/api/tags" > /dev/null 2>&1; then
    echo "  ℹ️  Ollama not available — using Claude for $story_id" >&2
    return 1
  fi

  echo "  🦙 Ollama available — attempting local pre-generation for $story_id ($story_type)"

  local PREREQ_LOG="agent_logs/local_prereq_${story_id}.log"
  mkdir -p agent_logs

  # Build a context-rich prompt for the local model
  local PREREQ_PROMPT
  PREREQ_PROMPT=$(cat <<PROMPT
You are a code generation assistant. Generate the requested output as plain code files only.
Do not include explanations, markdown formatting, or commentary outside of code comments.

Story: $story_id
Title: $story_title
Type: $story_type
Task: Generate the output for this story. Write complete, working code.

If generating test files: create the full test file skeleton with all describe/it blocks and import statements.
If generating docs: write JSDoc comments or README sections as plain text/markdown.
If generating boilerplate: write the complete skeleton file(s) with all required exports and types.

Output format: For each file, start a line with "=== FILE: path/to/file.ext ===" followed by the file content.
End each file with "=== END FILE ===".
PROMPT
)

  # Run local model
  local OUTPUT
  OUTPUT=$(bash "$scripts_dir/local-model.sh" \
    --task-type "$story_type" \
    --timeout 90 \
    - <<< "$PREREQ_PROMPT" 2>"$PREREQ_LOG") || {
    echo "  ⚠️  Local model failed — falling back to Claude" >&2
    return 1
  }

  if [[ -z "$OUTPUT" ]]; then
    echo "  ⚠️  Local model returned empty output — falling back to Claude" >&2
    return 1
  fi

  # Parse and write files from output
  local FILES_WRITTEN=0
  local CURRENT_FILE=""
  local CONTENT_BUFFER=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^===\ FILE:\ (.+)\ ===$ ]]; then
      # Write previous file if we have one
      if [[ -n "$CURRENT_FILE" && -n "$CONTENT_BUFFER" ]]; then
        mkdir -p "$(dirname "$CURRENT_FILE")"
        echo "$CONTENT_BUFFER" > "$CURRENT_FILE"
        FILES_WRITTEN=$((FILES_WRITTEN + 1))
        echo "  📝 Written: $CURRENT_FILE"
      fi
      CURRENT_FILE="${BASH_REMATCH[1]}"
      CONTENT_BUFFER=""
    elif [[ "$line" == "=== END FILE ===" ]]; then
      if [[ -n "$CURRENT_FILE" && -n "$CONTENT_BUFFER" ]]; then
        mkdir -p "$(dirname "$CURRENT_FILE")"
        echo "$CONTENT_BUFFER" > "$CURRENT_FILE"
        FILES_WRITTEN=$((FILES_WRITTEN + 1))
        echo "  📝 Written: $CURRENT_FILE"
      fi
      CURRENT_FILE=""
      CONTENT_BUFFER=""
    elif [[ -n "$CURRENT_FILE" ]]; then
      CONTENT_BUFFER+="$line"$'\n'
    fi
  done <<< "$OUTPUT"

  if [[ "$FILES_WRITTEN" -eq 0 ]]; then
    echo "  ⚠️  Local model output had no parseable files — falling back to Claude" >&2
    return 1
  fi

  echo "  ✅ Local pre-generation wrote $FILES_WRITTEN file(s)"

  # Quick quality check: if tests exist, try running them
  if [[ "$QUALITY_GATE" == "true" ]] && [[ -f "scripts/quality-gate.sh" ]]; then
    echo "  🔍 Running quality gate on local-generated files..."
    if (cd "$work_dir" && bash scripts/quality-gate.sh --skip-tests 2>&1 | tail -5); then
      echo "  ✅ Quality gate passed — local generation accepted"
      return 0
    else
      echo "  ⚠️  Quality gate failed — Claude will refine the local output"
      return 1
    fi
  fi

  return 0
}

# ─── Helper: build JSON object from key=value pairs ──────────────────────────

build_json() {
  local fields=""
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    val="${val//\"/\\\"}"
    if [[ -n "$fields" ]]; then fields="$fields, "; fi
    if [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      fields="$fields\"$key\": $val"
    elif [[ "$val" == "true" || "$val" == "false" || "$val" == "null" ]]; then
      fields="$fields\"$key\": $val"
    else
      fields="$fields\"$key\": \"$val\""
    fi
  done
  echo "{$fields}"
}

# ─── Helper: run workspace lifecycle hook ────────────────────────────────────
# Usage: run_hook <hook_name> <work_dir>
# Hooks: after_create, before_run, after_run, before_remove
# Returns 0 if hook succeeds or doesn't exist. Non-zero on hook failure.

run_hook() {
  local hook_name="$1"
  local work_dir="$2"
  local hook_script="${HOOKS_DIR}/${hook_name}.sh"

  # Hooks are optional — if dir or script missing, proceed silently
  if [[ ! -d "$HOOKS_DIR" ]]; then
    return 0
  fi

  if [[ ! -f "$hook_script" ]] || [[ ! -x "$hook_script" ]]; then
    return 0
  fi

  echo "  🪝 Running hook: ${hook_name}" >&2

  # Determine timeout command (gtimeout on macOS, timeout on Linux/MSYS)
  local timeout_cmd="timeout"
  if command -v gtimeout &>/dev/null; then
    timeout_cmd="gtimeout"
  fi

  # Run hook with timeout, passing environment variables
  # stdout/stderr captured to log file
  local hook_exit=0
  (
    export RALPH_STORY_ID="${STORY_ID:-}"
    export RALPH_ITERATION="${ITERATION:-0}"
    export RALPH_PRD_DIR="${PRD_DIR:-}"
    export RALPH_MODEL="${MODEL:-${MODEL_OVERRIDE:-claude-sonnet-4-6}}"
    cd "$work_dir"
    "$timeout_cmd" "$HOOK_TIMEOUT" bash "$hook_script"
  ) >> "${LOG_FILE:-/dev/null}" 2>&1 || hook_exit=$?

  if [[ $hook_exit -ne 0 ]]; then
    echo "  ⚠️  Hook ${hook_name} failed (exit $hook_exit)" >&2
    return $hook_exit
  fi

  echo "  ✅ Hook ${hook_name} completed" >&2
  return 0
}

# ─── Helper: stall watchdog — kill agent if no log output for N minutes ──────
# Runs as a background process alongside the iteration timeout watchdog.
# Checks log file mtime every 30 seconds. If no new bytes for stall-timeout
# minutes, kills CLAUDE_PID. Grace period prevents false stalls during startup.
#
# Overridable internals for testing:
#   STALL_TIMEOUT_SECS, STALL_GRACE_SECS, STALL_CHECK_INTERVAL

start_stall_watchdog() {
  local stall_timeout_secs="${STALL_TIMEOUT_SECS:-$((STALL_TIMEOUT * 60))}"
  local grace_secs="${STALL_GRACE_SECS:-$STALL_GRACE}"
  local check_interval="${STALL_CHECK_INTERVAL:-30}"
  local start_time
  start_time=$(date +%s)

  # Wait for grace period before starting checks
  if [[ "$grace_secs" -gt 0 ]]; then
    sleep "$grace_secs"
  fi

  while kill -0 "$CLAUDE_PID" 2>/dev/null; do
    sleep "$check_interval"

    # Check if Claude is still running after sleep
    if ! kill -0 "$CLAUDE_PID" 2>/dev/null; then
      break
    fi

    # Get log file last modified time
    local last_modified
    if [[ "$(uname -s)" == "Darwin" ]]; then
      last_modified=$(stat -f %m "$LOG_FILE" 2>/dev/null || echo "0")
    else
      # Linux / MSYS / Git Bash
      last_modified=$(stat -c %Y "$LOG_FILE" 2>/dev/null || date -r "$LOG_FILE" +%s 2>/dev/null || echo "0")
    fi

    local now
    now=$(date +%s)
    local idle_secs=$((now - last_modified))

    if [[ "$idle_secs" -ge "$stall_timeout_secs" ]]; then
      echo "  ⏸️  Stall detected: no output for $((idle_secs / 60)) minutes — killing agent" >> "$LOG_FILE"
      echo "  ⏸️  Stall detected: no output for $((idle_secs / 60)) minutes — killing agent" >&2

      # SIGTERM first for graceful shutdown
      kill "$CLAUDE_PID" 2>/dev/null || true

      # SIGKILL after 10 seconds if still running
      sleep 10
      if kill -0 "$CLAUDE_PID" 2>/dev/null; then
        kill -9 "$CLAUDE_PID" 2>/dev/null || true
      fi

      # Signal to the main loop that this was a stall exit
      echo "STALL_KILLED" > "/tmp/ralph_stall_$$"
      break
    fi
  done
}

# ─── Helper: calculate exponential backoff delay ─────────────────────────────
# Formula: min(10 * 2^(fail_count-1), 300) seconds
# Sequence: 10s, 20s, 40s, 80s, 160s, 300s, 300s...

calculate_backoff() {
  local fail_count="$1"
  local BASE_DELAY=10
  local MAX_BACKOFF=300

  # 2^(fail_count-1) via bit shift
  local exponent=$((fail_count - 1))
  local power=1
  local i
  for ((i = 0; i < exponent; i++)); do
    power=$((power * 2))
  done

  local delay=$((BASE_DELAY * power))
  if [[ "$delay" -gt "$MAX_BACKOFF" ]]; then
    delay="$MAX_BACKOFF"
  fi
  echo "$delay"
}

# ─── Helper: interruptible sleep for backoff ──────────────────────────────────
# Sleeps for N seconds but exits immediately on SIGINT (Ctrl+C)

BACKOFF_INTERRUPTED=false

backoff_sleep() {
  local duration="$1"
  local elapsed=0
  BACKOFF_INTERRUPTED=false

  while [[ "$elapsed" -lt "$duration" ]] && [[ "$BACKOFF_INTERRUPTED" == "false" ]]; do
    sleep 1 &
    local sleep_pid=$!
    trap 'BACKOFF_INTERRUPTED=true; kill $sleep_pid 2>/dev/null || true' INT
    wait "$sleep_pid" 2>/dev/null || true
    elapsed=$((elapsed + 1))
  done
}

# ─── Helper: collect proof packet after each iteration ────────────────────
# Lightweight evidence collection — runs after every Claude invocation (pass or fail).
# Saves structured JSON to agent_logs/proof-{story_id}-iter{N}.json.
# Never fails the iteration — errors are logged and skipped.
#
# Usage: collect_proof_packet <story_id> <iteration> <status> <exit_code> <duration>
# Quality gate variables (set externally): QG_TESTS_PASSED, QG_TESTS_FAILED,
#   QG_TESTS_SKIPPED, QG_LINT_ERRORS, QG_LINT_WARNINGS, QG_BUILD_CLEAN

collect_proof_packet() {
  local story_id="$1"
  local iteration="$2"
  local status="$3"
  local exit_code="$4"
  local duration="$5"
  local proof_file="agent_logs/proof-${story_id}-iter${iteration}.json"
  local work_dir="${WORKTREE_PATH:-$(pwd)}"

  mkdir -p agent_logs

  # Collect git diff stats (lightweight)
  local files_changed=0 lines_added=0 lines_removed=0
  local diff_stat
  diff_stat=$(cd "$work_dir" && git diff --stat HEAD~1 HEAD 2>/dev/null || echo "")
  if [[ -n "$diff_stat" ]]; then
    files_changed=$(echo "$diff_stat" | tail -1 | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "0")
    lines_added=$(echo "$diff_stat" | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    lines_removed=$(echo "$diff_stat" | tail -1 | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
  fi
  files_changed="${files_changed:-0}"
  lines_added="${lines_added:-0}"
  lines_removed="${lines_removed:-0}"

  # Commit count (commits ahead of main branch)
  local commit_count=0
  local main_branch
  main_branch=$(cd "$work_dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  commit_count=$(cd "$work_dir" && git rev-list --count HEAD ^"$(git merge-base HEAD main 2>/dev/null || echo HEAD)" 2>/dev/null || echo "0")

  # Timestamp
  local collected_at
  collected_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Build JSON — core fields always present
  local json_content
  json_content=$(node -e "
    const packet = {
      \"story_id\": process.argv[1],
      \"iteration\": parseInt(process.argv[2]) || 0,
      \"status\": process.argv[3],
      \"exit_code\": parseInt(process.argv[4]) || 0,
      \"duration_seconds\": parseInt(process.argv[5]) || 0,
      \"model\": process.argv[6],
      \"files_changed\": parseInt(process.argv[7]) || 0,
      \"lines_added\": parseInt(process.argv[8]) || 0,
      \"lines_removed\": parseInt(process.argv[9]) || 0,
      \"commit_count\": parseInt(process.argv[10]) || 0,
      \"collected_at\": process.argv[11]
    };

    // Quality gate fields — only if gate ran
    if (process.argv[12] === 'true') {
      packet.tests_passed = parseInt(process.argv[13]) || 0;
      packet.tests_failed = parseInt(process.argv[14]) || 0;
      packet.tests_skipped = parseInt(process.argv[15]) || 0;
      packet.lint_errors = parseInt(process.argv[16]) || 0;
      packet.lint_warnings = parseInt(process.argv[17]) || 0;
      packet.build_clean = process.argv[18] === 'true';
    }

    console.log(JSON.stringify(packet, null, 2));
  " "$story_id" "$iteration" "$status" "$exit_code" "$duration" \
    "${MODEL:-claude-sonnet-4-6}" \
    "$files_changed" "$lines_added" "$lines_removed" "$commit_count" \
    "$collected_at" \
    "${QUALITY_GATE:-false}" \
    "${QG_TESTS_PASSED:-0}" "${QG_TESTS_FAILED:-0}" "${QG_TESTS_SKIPPED:-0}" \
    "${QG_LINT_ERRORS:-0}" "${QG_LINT_WARNINGS:-0}" "${QG_BUILD_CLEAN:-false}" \
    2>/dev/null) || {
    echo "  ⚠️  Proof packet: JSON generation failed" >&2
    return 0
  }

  # Write proof packet (atomic: tmp then move)
  local tmp_file="${proof_file}.tmp"
  echo "$json_content" > "$tmp_file" && mv "$tmp_file" "$proof_file" || {
    echo "  ⚠️  Proof packet: file write failed" >&2
    rm -f "$tmp_file"
    return 0
  }

  echo "  📦 Proof packet: $proof_file"

  # POST to telemetry if enabled
  if [[ "$TELEMETRY" == "true" ]] && [[ -n "${RUN_ID:-}" ]]; then
    curl -s --connect-timeout 2 --max-time 5 \
      -X POST "${TELEMETRY_URL}/api/ralph/proof" \
      -H "Content-Type: application/json" \
      -d "$json_content" 2>/dev/null || true
  fi

  return 0
}

# ─── Helper: dynamic config reload — change settings mid-run without restart ─
# Checks for ralph-config.json in PRD_DIR at each iteration start.
# If the file exists and has changed (by mtime), reloads reloadable settings.
# Reloadable:     model, timeout, quality_gate, strict, skip_tests, review, max_cost, stall_timeout
# Non-reloadable (launch only): telemetry, telemetry_url, docker, hooks_dir
# If ralph-config.json is malformed, keeps previous config and logs a warning.
# If ralph-config.json doesn't exist, uses original launch flags (no-op).
#
# Sample ralph-config.json:
#   { "model": "claude-opus-4-6", "timeout": 45, "quality_gate": true, "stall_timeout": 10 }

load_dynamic_config() {
  local config_file="${PRD_DIR}/ralph-config.json"

  # If config file doesn't exist, proceed silently with current settings
  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  # Get file mtime for change detection
  local current_mtime
  if [[ "$(uname -s)" == "Darwin" ]]; then
    current_mtime=$(stat -f %m "$config_file" 2>/dev/null || echo "0")
  else
    current_mtime=$(stat -c %Y "$config_file" 2>/dev/null || date -r "$config_file" +%s 2>/dev/null || echo "0")
  fi

  # Skip reload if mtime unchanged
  if [[ -n "$CONFIG_LAST_MTIME" ]] && [[ "$CONFIG_LAST_MTIME" == "$current_mtime" ]]; then
    return 0
  fi

  # Parse config with node — extract reloadable settings as shell assignments
  # Reloadable keys: "model", "timeout", "quality_gate", "strict", "skip_tests", "review", "max_cost", "stall_timeout"
  # If malformed JSON, keeps previous config and logs a warning
  local shell_assignments
  shell_assignments=$(node -e "
    try {
      var cfg = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
      var reloadable = [\"model\", \"timeout\", \"quality_gate\", \"strict\", \"skip_tests\", \"review\", \"max_cost\", \"stall_timeout\"];
      for (var i = 0; i < reloadable.length; i++) {
        var k = reloadable[i];
        if (cfg[k] !== undefined) {
          console.log('CFG_' + k.toUpperCase() + '=' + String(cfg[k]));
        }
      }
    } catch (e) {
      process.stderr.write('PARSE_ERROR');
      process.exit(1);
    }
  " "$config_file" 2>/dev/null) || {
    echo "  ⚠️  Config warning: ralph-config.json is malformed — keeping previous config" >&2
    return 0
  }

  # Update mtime tracker
  CONFIG_LAST_MTIME="$current_mtime"

  # Apply changes — log each one
  local changes=""
  local val

  # model
  val=$(echo "$shell_assignments" | grep '^CFG_MODEL=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$MODEL_OVERRIDE" ]]; then
    changes="${changes}model changed from ${MODEL_OVERRIDE:-default} to $val, "
    MODEL_OVERRIDE="$val"
  fi

  # timeout
  val=$(echo "$shell_assignments" | grep '^CFG_TIMEOUT=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$ITER_TIMEOUT" ]]; then
    changes="${changes}timeout changed from ${ITER_TIMEOUT} to $val, "
    ITER_TIMEOUT="$val"
    TIMEOUT_SECONDS=$((ITER_TIMEOUT * 60))
  fi

  # quality_gate
  val=$(echo "$shell_assignments" | grep '^CFG_QUALITY_GATE=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$QUALITY_GATE" ]]; then
    changes="${changes}quality_gate changed from $QUALITY_GATE to $val, "
    QUALITY_GATE="$val"
  fi

  # strict
  val=$(echo "$shell_assignments" | grep '^CFG_STRICT=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$STRICT" ]]; then
    changes="${changes}strict changed from $STRICT to $val, "
    STRICT="$val"
  fi

  # skip_tests
  val=$(echo "$shell_assignments" | grep '^CFG_SKIP_TESTS=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$SKIP_TESTS" ]]; then
    changes="${changes}skip_tests changed from $SKIP_TESTS to $val, "
    SKIP_TESTS="$val"
  fi

  # review
  val=$(echo "$shell_assignments" | grep '^CFG_REVIEW=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$REVIEW" ]]; then
    changes="${changes}review changed from $REVIEW to $val, "
    REVIEW="$val"
  fi

  # max_cost
  val=$(echo "$shell_assignments" | grep '^CFG_MAX_COST=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$MAX_COST" ]]; then
    changes="${changes}max_cost changed from ${MAX_COST:-unset} to $val, "
    MAX_COST="$val"
  fi

  # stall_timeout
  val=$(echo "$shell_assignments" | grep '^CFG_STALL_TIMEOUT=' | head -1 | cut -d= -f2- || true)
  if [[ -n "$val" ]] && [[ "$val" != "$STALL_TIMEOUT" ]]; then
    changes="${changes}stall_timeout changed from $STALL_TIMEOUT to $val, "
    STALL_TIMEOUT="$val"
  fi

  # Log summary of changes
  if [[ -n "$changes" ]]; then
    # Remove trailing ", "
    changes="${changes%, }"
    echo "  🔄 Config reloaded: $changes"
  fi

  return 0
}

# ─── Helper: emit telemetry event via HTTP POST to Command API ───────────────

emit_ralph_event() {
  if [[ "$TELEMETRY" != "true" ]]; then return; fi

  local event_type="$1"
  shift

  case "$event_type" in
    session_start)
      local json
      json=$(build_json \
        "prd_path=${PRD_DIR}" \
        "branch_name=$(git branch --show-current 2>/dev/null || echo unknown)" \
        "model=${MODEL_OVERRIDE:-claude-sonnet-4-6}" \
        "total_stories=$(node -e "const p=JSON.parse(require('fs').readFileSync('${PRD_DIR}/prd.json','utf8'));console.log(p.userStories.length)" 2>/dev/null || echo 0)" \
        "config=$(echo "{}" | sed 's/"/\\"/g')" \
        "$@")
      local response
      response=$(curl -s --connect-timeout 2 --max-time 5 \
        -X POST "${TELEMETRY_URL}/api/ralph/runs" \
        -H "Content-Type: application/json" \
        -d "$json" 2>/dev/null) || { echo "  ⚠️  Telemetry: failed to create run" >&2; return; }
      RUN_ID=$(echo "$response" | node -e "process.stdin.on('data',d=>{try{console.log(JSON.parse(d).id)}catch{}})" 2>/dev/null || echo "")
      if [[ -n "$RUN_ID" ]]; then
        echo "  📡 Telemetry: run created (id=$RUN_ID)"
      fi
      ;;

    iteration_start)
      if [[ -z "$RUN_ID" ]]; then return; fi
      local json
      json=$(build_json \
        "story_id=${STORY_ID:-unknown}" \
        "iteration_number=${ITERATION:-0}" \
        "$@")
      local response
      response=$(curl -s --connect-timeout 2 --max-time 5 \
        -X POST "${TELEMETRY_URL}/api/ralph/runs/${RUN_ID}/iterations" \
        -H "Content-Type: application/json" \
        -d "$json" 2>/dev/null) || { echo "  ⚠️  Telemetry: failed to create iteration" >&2; return; }
      ITERATION_ID=$(echo "$response" | node -e "process.stdin.on('data',d=>{try{console.log(JSON.parse(d).id)}catch{}})" 2>/dev/null || echo "")
      ;;

    iteration_end)
      if [[ -z "$RUN_ID" || -z "$ITERATION_ID" ]]; then return; fi
      local json
      json=$(build_json \
        "status=${PREV_RESULT:-unknown}" \
        "ended_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "duration_seconds=${ITER_WALL_SECS:-0}" \
        "$@")
      curl -s --connect-timeout 2 --max-time 5 \
        -X PUT "${TELEMETRY_URL}/api/ralph/iterations/${ITERATION_ID}" \
        -H "Content-Type: application/json" \
        -d "$json" 2>/dev/null || true
      # Also update run counts
      local run_json
      run_json=$(build_json \
        "completed_stories=${STORIES_COMPLETED:-0}" \
        "$@")
      curl -s --connect-timeout 2 --max-time 5 \
        -X PUT "${TELEMETRY_URL}/api/ralph/runs/${RUN_ID}" \
        -H "Content-Type: application/json" \
        -d "$run_json" 2>/dev/null || true
      ITERATION_ID=""
      ;;

    stuck_detected)
      if [[ -z "$RUN_ID" || -z "$ITERATION_ID" ]]; then return; fi
      local json
      json=$(build_json \
        "status=stuck" \
        "ended_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "error_message=Failed ${CONSECUTIVE_SAME} consecutive attempts" \
        "$@")
      curl -s --connect-timeout 2 --max-time 5 \
        -X PUT "${TELEMETRY_URL}/api/ralph/iterations/${ITERATION_ID}" \
        -H "Content-Type: application/json" \
        -d "$json" 2>/dev/null || true
      ITERATION_ID=""
      ;;

    session_end)
      if [[ -z "$RUN_ID" ]]; then return; fi
      local json
      json=$(build_json \
        "status=completed" \
        "ended_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "completed_stories=${STORIES_COMPLETED:-0}" \
        "stuck_stories=$(node -e "const p=JSON.parse(require('fs').readFileSync('${PRD_DIR}/prd.json','utf8'));console.log(p.userStories.filter(s=>s.stuck).length)" 2>/dev/null || echo 0)" \
        "$@")
      curl -s --connect-timeout 2 --max-time 5 \
        -X PUT "${TELEMETRY_URL}/api/ralph/runs/${RUN_ID}" \
        -H "Content-Type: application/json" \
        -d "$json" 2>/dev/null || true
      echo "  📡 Telemetry: run completed (id=$RUN_ID)"
      ;;

    *)
      # Generic event — POST as-is to runs endpoint (fire-and-forget)
      if [[ -n "$RUN_ID" ]]; then
        local json
        json=$(build_json "event=$event_type" "$@")
        curl -s --connect-timeout 2 --max-time 5 \
          -X PUT "${TELEMETRY_URL}/api/ralph/runs/${RUN_ID}" \
          -H "Content-Type: application/json" \
          -d "$json" 2>/dev/null || true
      fi
      ;;
  esac
}

# ─── Helper: pick next story ID from PRD ────────────────────────────────────

pick_next_story() {
  local prd_file="$1"
  node -e "
    const prd = JSON.parse(require('fs').readFileSync('$prd_file', 'utf8'));
    const pending = prd.userStories
      .filter(s => !s.passes && !s.stuck)
      .sort((a, b) => (a.priority || 99) - (b.priority || 99));
    if (pending.length > 0) console.log(pending[0].id);
  " 2>/dev/null || echo ""
}

# ─── Helper: worktree management ────────────────────────────────────────────

WORKTREE_DIR=".worktrees"

create_worktree() {
  local story_id="$1"
  local branch_name="ralph/${story_id}"
  local worktree_path="${WORKTREE_DIR}/${story_id}"

  # Clean up if stale worktree directory exists
  if [[ -d "$worktree_path" ]]; then
    echo "  🧹 Cleaning stale worktree: $story_id" >&2
    git worktree remove "$worktree_path" --force >/dev/null 2>&1 || rm -rf "$worktree_path"
  fi

  # Clean up stale branch even if worktree directory was already removed
  if git show-ref --verify --quiet "refs/heads/${branch_name}" 2>/dev/null; then
    echo "  🧹 Cleaning stale branch: $branch_name" >&2
    git branch -D "$branch_name" >/dev/null 2>&1 || true
  fi

  mkdir -p "$WORKTREE_DIR"
  git worktree add "$worktree_path" -b "$branch_name" HEAD >/dev/null 2>&1

  # Run after_create hook — failure means worktree creation failed
  if ! run_hook "after_create" "$worktree_path"; then
    echo "  ⚠️  after_create hook failed — worktree creation failed" >&2
    git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
    git branch -D "$branch_name" 2>/dev/null || true
    return 1
  fi

  echo "$worktree_path"
}

merge_worktree() {
  local story_id="$1"
  local branch_name="ralph/${story_id}"
  local worktree_path="${WORKTREE_DIR}/${story_id}"
  local main_branch
  main_branch=$(git rev-parse --abbrev-ref HEAD)

  # Check if the worktree branch has any commits ahead
  if git log "${main_branch}..${branch_name}" --oneline 2>/dev/null | grep -q .; then
    echo "  🔀 Merging worktree branch: $branch_name"
    # Stash any uncommitted changes to prevent merge conflicts
    local stashed=false
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      git stash push -q -m "ralph-merge-${story_id}" 2>/dev/null && stashed=true
    fi
    if git merge "$branch_name" --no-edit 2>/dev/null; then
      echo "  ✅ Merge successful"
    else
      # Auto-resolve conflicts by taking the worktree (theirs) version.
      # Worktree branches contain the latest story work — safe to prefer.
      local conflicted
      conflicted=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
      if [[ -n "$conflicted" ]]; then
        for f in $conflicted; do
          git checkout --theirs "$f" 2>/dev/null && git add "$f" 2>/dev/null
          echo "  🔧 Auto-resolved conflict in $f (took worktree version)"
        done
      fi
      if git commit --no-edit 2>/dev/null; then
        echo "  ✅ Merge successful (with auto-resolved conflicts)"
      else
        echo "  ⚠️  Merge conflict — keeping worktree branch for manual resolution"
        git merge --abort 2>/dev/null || true
        [[ "$stashed" == true ]] && git stash pop -q 2>/dev/null || true
        return 1
      fi
    fi
    [[ "$stashed" == true ]] && git stash pop -q 2>/dev/null || true
  else
    echo "  ℹ️  No new commits in worktree"
  fi

  # Run before_remove hook — failure is logged but not fatal
  run_hook "before_remove" "$worktree_path" || true

  # Clean up
  git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
  git branch -D "$branch_name" 2>/dev/null || true
  return 0
}

# ─── Helper: auto-create PR via GitHub CLI ──────────────────────────────────

create_auto_pr() {
  local story_id="$1"
  local prd_file="$2"
  local confidence="$3"

  # Check gh is installed
  if ! command -v gh &>/dev/null; then
    echo "  ⚠️  gh CLI not installed — skipping auto-PR"
    return 1
  fi

  # Check gh is authenticated
  if ! gh auth status &>/dev/null 2>&1; then
    echo "  ⚠️  gh not authenticated — skipping auto-PR"
    return 1
  fi

  local current_branch
  current_branch=$(git branch --show-current)
  local default_branch
  default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | awk '{print $NF}')
  default_branch="${default_branch:-main}"

  # Don't create PR if we're on the default branch
  if [[ "$current_branch" == "$default_branch" ]]; then
    echo "  ℹ️  On default branch ($default_branch) — skipping auto-PR"
    return 0
  fi

  # Push first
  git push origin "$current_branch" 2>/dev/null || {
    echo "  ⚠️  Push failed — skipping auto-PR"
    return 1
  }

  # Build PR body from story info and proof packet
  local story_title
  story_title=$(node -e "
    const prd = JSON.parse(require('fs').readFileSync('$prd_file', 'utf8'));
    const story = prd.userStories.find(s => s.id === '$story_id');
    if (story) console.log(story.title);
  " 2>/dev/null || echo "$story_id")

  local story_desc
  story_desc=$(node -e "
    const prd = JSON.parse(require('fs').readFileSync('$prd_file', 'utf8'));
    const story = prd.userStories.find(s => s.id === '$story_id');
    if (story) {
      console.log(story.description || '');
      if (story.acceptanceCriteria) {
        console.log('');
        console.log('### Acceptance Criteria');
        story.acceptanceCriteria.forEach(c => console.log('- [x] ' + c));
      }
    }
  " 2>/dev/null || echo "")

  local proof_summary=""
  if [[ -f "proof/$story_id/verdict.json" ]]; then
    proof_summary=$(node -e "
      const v = JSON.parse(require('fs').readFileSync('proof/$story_id/verdict.json', 'utf8'));
      console.log('### Verification');
      console.log('- **Verdict:** ' + v.verdict);
      console.log('- **Confidence:** ' + v.confidence);
      if (v.criteria) {
        v.criteria.forEach(c => console.log('  - ' + (c.pass ? '✅' : '❌') + ' ' + c.name));
      }
    " 2>/dev/null || echo "")
  fi

  # Check if PR already exists for this branch
  local existing_pr
  existing_pr=$(gh pr list --head "$current_branch" --json number --jq '.[0].number' 2>/dev/null || echo "")
  if [[ -n "$existing_pr" ]]; then
    echo "  ℹ️  PR #$existing_pr already exists for $current_branch"
    return 0
  fi

  local pr_url
  pr_url=$(gh pr create \
    --title "feat: $story_title ($story_id)" \
    --body "$(cat <<EOF
## Summary
Autonomous implementation of **$story_id**: $story_title

$story_desc

$proof_summary

### Auto-PR
- **Confidence:** $confidence
- **Threshold:** $PR_THRESHOLD
- **Generated by:** Ralph Loop (Hartz Claude Framework)

> This PR was automatically created because verification passed with confidence >= $PR_THRESHOLD.
> Review the proof packet in \`proof/$story_id/\` for full verification details.

---
*🤖 Generated by [Hartz Claude Framework](https://github.com/harchyboy/claude-framework)*
EOF
)" \
    --base "$default_branch" 2>&1) || {
    echo "  ⚠️  PR creation failed: $pr_url"
    return 1
  }

  echo "  🔗 PR created: $pr_url"
  emit_ralph_event "auto_pr_created" \
    "story_id=$story_id" \
    "confidence=$confidence" \
    "pr_url=$pr_url" \
    "iteration=$ITERATION"

  return 0
}

clean_stale_worktrees() {
  if [[ ! -d "$WORKTREE_DIR" ]]; then return; fi

  local now
  now=$(date +%s)
  local threshold=$((STALE_LOCK_HOURS * 3600))

  for wt_dir in "$WORKTREE_DIR"/*/; do
    [[ ! -d "$wt_dir" ]] && continue
    local story_id
    story_id=$(basename "$wt_dir")

    local dir_age
    dir_age=$(node -e "
      const fs = require('fs');
      const stat = fs.statSync('$wt_dir');
      console.log(Math.floor((Date.now() - stat.mtimeMs) / 1000));
    " 2>/dev/null || echo "0")

    if [[ "$dir_age" -gt "$threshold" ]]; then
      echo "  🧹 Removing stale worktree: $story_id (${STALE_LOCK_HOURS}h+ old)"
      git worktree remove "$wt_dir" --force 2>/dev/null || rm -rf "$wt_dir"
      git branch -D "ralph/${story_id}" 2>/dev/null || true
    fi
  done
}

# ─── Find PRD ────────────────────────────────────────────────────────────────

PRD_DIR=""
AGENT_PROMPT=""

# Look for PRDs with incomplete stories
for dir in scripts/ralph-moss/prds/*/; do
  if [[ -f "$dir/prd.json" ]]; then
    incomplete=$(count_pending "$dir/prd.json")
    if [[ "$incomplete" -gt 0 ]]; then
      PRD_DIR="$dir"
      AGENT_PROMPT="$dir/AGENT_PROMPT.md"
      break
    fi
  fi
done

if [[ -z "$PRD_DIR" ]]; then
  echo "❌ No PRDs with incomplete stories found."
  echo "   Create a PRD first: /prd or /bugfix in Claude Code"
  exit 1
fi

echo "📋 Found PRD: $PRD_DIR"

# ─── Preflight ───────────────────────────────────────────────────────────────

if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
  echo "🔍 Running preflight checks..."

  # Check PRD JSON is valid
  node -e "
    const prd = JSON.parse(require('fs').readFileSync('${PRD_DIR}/prd.json', 'utf8'));
    const required = ['project', 'branchName', 'description', 'userStories'];
    for (const field of required) {
      if (!(field in prd)) { console.log('ERROR: Missing required field: ' + field); process.exit(1); }
    }
    for (const story of prd.userStories) {
      if ((story.acceptanceCriteria || []).length < 2) {
        console.log('WARNING: Story ' + story.id + ' has fewer than 2 acceptance criteria');
      }
    }
    const pending = prd.userStories.filter(s => !s.passes);
    console.log('✅ PRD valid: ' + pending.length + ' stories pending');
  " || exit 1

  # Check git is clean (warn only, never block)
  if ! git diff --quiet 2>/dev/null; then
    echo "⚠️ Working directory has uncommitted changes — continuing anyway"
  fi

  # Ensure branch exists
  BRANCH_NAME=$(node -e "const p=JSON.parse(require('fs').readFileSync('${PRD_DIR}/prd.json','utf8'));console.log(p.branchName)")
  if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
    git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
    echo "📌 Created/switched to branch: $BRANCH_NAME"
  fi
fi

# ─── Ensure directories ──────────────────────────────────────────────────────

mkdir -p agent_logs

# ─── Build agent prompt ──────────────────────────────────────────────────────

build_iteration_prompt() {
  local prd_content
  prd_content=$(cat "${PRD_DIR}/prd.json")

  local progress_content=""
  if [[ -f "PROGRESS.md" ]]; then
    progress_content=$(cat PROGRESS.md)
  fi

  local solutions_index=""
  if [[ -d "docs/solutions" ]] && compgen -G "docs/solutions/*.md" > /dev/null 2>&1; then
    solutions_index=$(grep -h "^title:" docs/solutions/*.md 2>/dev/null | sed 's/title: //' | head -20 || true)
  fi

  # Previous iteration context (if any)
  local prev_context=""
  if [[ "$ITERATION" -gt 1 ]] && [[ -n "${PREV_STORY_ID:-}" ]]; then
    prev_context="Previous iteration worked on ${PREV_STORY_ID} (result: ${PREV_RESULT:-unknown}). Check PROGRESS.md for details."
  fi

  cat <<PROMPT
# Ralph Loop — Autonomous Development Session

## Your objective
Implement story **${STORY_ID:-next pending}** from the PRD below.
The story must be fully complete (tests passing, code committed) before you stop.
${prev_context:+
## Previous iteration
${prev_context}}

## Current project state

### PROGRESS.md
${progress_content:-No PROGRESS.md found. Start by creating one.}

### Available learnings (docs/solutions/)
${solutions_index:-No solutions documented yet.}

## PRD
\`\`\`json
${prd_content}
\`\`\`

## Instructions

1. **Read first**: Review PROGRESS.md, docs/CODE-STANDARDS.md, and docs/solutions/ for relevant context
2. **Follow code standards**: docs/CODE-STANDARDS.md contains mandatory patterns — apply them during implementation, not after review
3. **Check failed approaches**: Read docs/failed-approaches.md before attempting solutions
4. **Implement story ${STORY_ID:-"(highest priority with passes: false)"}**: Build the feature following docs/CODE-STANDARDS.md patterns
5. **Test**: Run the quality gate: \`bash scripts/quality-gate.sh\`
   - Fix ALL failures before proceeding
6. **Update PROGRESS.md**: Add what you did, what's next, any discoveries
7. **Commit**: Use conventional commit format: \`feat: [description] (closes ${STORY_ID:-[story-id]})\`
8. **Update PRD**: Mark story \`passes: true\` in prd.json, commit that too
9. **Stop**: Exit after completing ONE story. The loop will restart for the next.

## Context management
- If your context is getting large, update PROGRESS.md with your current findings before continuing
- Keep commits small and frequent — one logical change per commit

## Rules
- NEVER skip the quality gate
- NEVER mark a story as passed without all acceptance criteria met
- If stuck after 3 attempts: document in docs/failed-approaches.md and pick a different story
- Check docs/solutions/ before implementing any non-trivial pattern

PROMPT
}

build_continuation_prompt() {
  # Shorter prompt for retrying the same story — saves tokens on re-attempts
  # Shorter than build_iteration_prompt — omits full PRD and agent prompt file

  # Extract acceptance criteria for this story
  local criteria
  local prd_file="${PRD_DIR}/prd.json"
  criteria=$(node -e "
    const prd = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    const story = prd.userStories.find(s => s.id === process.argv[2]);
    if (story && story.acceptanceCriteria) {
      story.acceptanceCriteria.forEach(c => console.log('- ' + c));
    }
  " "$prd_file" "$STORY_ID" 2>/dev/null || echo "- (could not read criteria)")

  # Get last 50 lines of previous attempt's log
  local prev_log_tail=""
  if [[ -n "${PREV_LOG_FILE:-}" ]] && [[ -f "${PREV_LOG_FILE}" ]]; then
    prev_log_tail=$(tail -50 "${PREV_LOG_FILE}" 2>/dev/null || echo "(previous log not available)")
  else
    prev_log_tail="(no previous log available)"
  fi

  cat <<PROMPT
# Ralph Loop — Continuation (Retry #${CONSECUTIVE_SAME})

You are retrying story **${STORY_ID}**. The previous attempt failed.

## Previous attempt log (last 50 lines)
\`\`\`
${prev_log_tail}
\`\`\`

## Acceptance criteria
${criteria}

## Instructions
Fix the remaining issues and ensure all acceptance criteria pass.

1. Read PROGRESS.md for what was already done
2. Run the quality gate: \`bash scripts/quality-gate.sh\` to see current state
3. Fix all failures
4. Update PROGRESS.md
5. Commit: \`feat: [description] (closes ${STORY_ID})\`
6. Update PRD: Mark story \`passes: true\` in prd.json, commit that too
7. Stop after completing the story

## Rules
- NEVER skip the quality gate
- NEVER mark a story as passed without all acceptance criteria met
- Check docs/failed-approaches.md before retrying the same approach

PROMPT
}

# ─── Main loop ───────────────────────────────────────────────────────────────

TIMEOUT_SECONDS=$((ITER_TIMEOUT * 60))

echo ""
echo "🚀 Starting Ralph loop"
echo "   Max iterations: $MAX_ITERATIONS"
echo "   Iteration timeout: ${ITER_TIMEOUT} minutes"
echo "   Quality gate: $QUALITY_GATE"
echo "   Review: $REVIEW"
echo "   Telemetry: $TELEMETRY (url: $TELEMETRY_URL)"
echo "   Verification: $VERIFY"
echo "   Docker: $USE_DOCKER"
echo "   Auto-PR: $AUTO_PR (threshold: $PR_THRESHOLD)"
echo "   Stall timeout: ${STALL_TIMEOUT} minutes (0=disabled)"
echo "   Hooks dir: $HOOKS_DIR"
echo "   Worktrees: $WORKTREE_DIR"
echo "   PRD: $PRD_DIR"
echo ""

emit_ralph_event "session_start"

ITERATION=0
STORIES_COMPLETED=0
declare -A STORY_FAIL_COUNT 2>/dev/null || true   # track consecutive failures per story
LAST_STORY=""
CONSECUTIVE_SAME=0
MAX_RETRIES_PER_STORY=2   # after this many failures on same story, escalate

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))

  # Dynamic config reload — check ralph-config.json for mid-run setting changes
  load_dynamic_config

  # Clean stale worktrees before each iteration
  clean_stale_worktrees

  # Check if all stories are done
  remaining=$(count_pending "${PRD_DIR}/prd.json")

  if [[ "$remaining" -eq 0 ]]; then
    echo "🎉 All stories complete! PRD finished."
    break
  fi

  # Cost check
  if [[ -n "$MAX_COST" ]] && [[ "$TRACK_COST" == "true" ]]; then
    cost_check=$(node -e "console.log($TOTAL_COST > $MAX_COST ? 'OVER' : 'OK')")
    if [[ "$cost_check" == "OVER" ]]; then
      echo "💰 Cost limit reached: \$$TOTAL_COST / \$$MAX_COST"
      break
    fi
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Iteration $ITERATION / $MAX_ITERATIONS — $remaining stories remaining"
  echo "  $(date '+%Y-%m-%d %H:%M:%S') (timeout: ${ITER_TIMEOUT}min)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Sync with remote
  git pull origin "$(git branch --show-current)" --rebase 2>/dev/null || true

  # Pick next story and create worktree
  STORY_ID=$(pick_next_story "${PRD_DIR}/prd.json")
  if [[ -z "$STORY_ID" ]]; then
    echo "  ℹ️  No pending stories found"
    break
  fi

  # ─── Stuck detection: same story failing repeatedly ───────────────────────
  if [[ "$STORY_ID" == "$LAST_STORY" ]]; then
    CONSECUTIVE_SAME=$((CONSECUTIVE_SAME + 1))
  else
    CONSECUTIVE_SAME=0
    LAST_STORY="$STORY_ID"
  fi

  if [[ "$CONSECUTIVE_SAME" -ge "$MAX_RETRIES_PER_STORY" ]]; then
    echo ""
    echo "  🚨 STUCK DETECTED: $STORY_ID has failed $CONSECUTIVE_SAME consecutive times"
    echo "  🚨 Last failure reason logged below. Stopping to avoid wasting resources."
    echo ""
    emit_ralph_event "stuck_detected" "story_id=$STORY_ID" "consecutive_failures=$CONSECUTIVE_SAME"

    # Write a stuck report for humans
    STUCK_FILE="${PRD_DIR}/STUCK-${STORY_ID}.md"
    {
      echo "# STUCK: $STORY_ID"
      echo ""
      echo "**Detected:** $(date '+%Y-%m-%d %H:%M:%S')"
      echo "**Consecutive failures:** $CONSECUTIVE_SAME"
      echo "**Iteration:** $ITERATION / $MAX_ITERATIONS"
      echo ""
      echo "## Last log tail"
      echo '```'
      tail -40 "$LOG_FILE" 2>/dev/null || echo "(no log available)"
      echo '```'
      echo ""
      echo "## Action needed"
      echo "A human or Opus-level agent needs to investigate and fix the root cause."
      echo "Once fixed, restart Ralph to continue."
    } > "$STUCK_FILE"
    echo "  📝 Wrote stuck report: $STUCK_FILE"

    # Skip this story — mark it stuck and move to next
    node -e "
      const fs = require('fs');
      const prd = JSON.parse(fs.readFileSync('${PRD_DIR}/prd.json', 'utf8'));
      const story = prd.userStories.find(s => s.id === '$STORY_ID');
      if (story) {
        story.stuck = true;
        story.stuckReason = 'Failed $CONSECUTIVE_SAME consecutive attempts';
        fs.writeFileSync('${PRD_DIR}/prd.json', JSON.stringify(prd, null, 2));
      }
    " 2>/dev/null || true

    CONSECUTIVE_SAME=0
    LAST_STORY=""
    echo "  ⏭️  Skipping $STORY_ID — moving to next story"
    continue
  fi
  echo "  📌 Target story: $STORY_ID"

  # ─── Exponential backoff on same-story retries ─────────────────────────────
  if [[ "$BACKOFF_ENABLED" == "true" ]] && [[ "$CONSECUTIVE_SAME" -gt 0 ]]; then
    BACKOFF_DELAY=$(calculate_backoff "$CONSECUTIVE_SAME")
    echo "  ⏳ Backing off ${BACKOFF_DELAY}s before retry #$((CONSECUTIVE_SAME + 1)) of $STORY_ID"
    backoff_sleep "$BACKOFF_DELAY"
    if [[ "$BACKOFF_INTERRUPTED" == "true" ]]; then
      echo "  🛑 Backoff interrupted — shutting down"
      break
    fi
    emit_ralph_event "backoff" \
      "story_id=$STORY_ID" \
      "backoff_seconds=$BACKOFF_DELAY" \
      "retry_number=$((CONSECUTIVE_SAME + 1))"
  fi

  emit_ralph_event "iteration_start"

  COMMIT=$(git rev-parse --short=6 HEAD)
  LOG_FILE="agent_logs/iteration_${ITERATION}_${COMMIT}.log"

  WORKTREE_PATH=""
  if git worktree list > /dev/null 2>&1; then
    WORKTREE_PATH=$(create_worktree "$STORY_ID") || {
      echo "  ⚠️  Worktree creation failed — running in main tree"
      WORKTREE_PATH=""
    }
  fi

  # Build and save the prompt — full for first attempt, continuation for retries
  if [[ "$CONSECUTIVE_SAME" -gt 0 ]] && [[ -n "${PREV_LOG_FILE:-}" ]]; then
    echo "  📝 Using continuation prompt (retry #${CONSECUTIVE_SAME})"
    build_continuation_prompt > /tmp/ralph_continuation_$$.md
    PROMPT_FILE="/tmp/ralph_continuation_$$.md"
  else
    echo "  📝 Using full prompt"
    build_iteration_prompt > /tmp/ralph_prompt_$$.md
    PROMPT_FILE="/tmp/ralph_prompt_$$.md"
  fi

  # Determine model
  if [[ -n "$MODEL_OVERRIDE" ]]; then
    MODEL="$MODEL_OVERRIDE"
  else
    MODEL="claude-sonnet-4-6"
  fi

  # ─── Local model auto-routing ────────────────────────────────────────────────
  # For local-eligible story types, attempt Ollama pre-generation.
  # If it succeeds and writes valid files, we skip the full Claude run.
  # If it fails or is disabled, fall through to Claude as normal.

  LOCAL_PREREQ_DONE=false

  if [[ "$USE_LOCAL" == "true" ]] && [[ -z "$MODEL_OVERRIDE" ]]; then
    # Extract story title and description from PRD
    STORY_META=$(node -e "
      const prd = JSON.parse(require('fs').readFileSync('${PRD_DIR}/prd.json', 'utf8'));
      const s = prd.userStories.find(s => s.id === '$STORY_ID');
      if (s) console.log(JSON.stringify({ title: s.title || '', description: s.description || '' }));
      else console.log(JSON.stringify({ title: '', description: '' }));
    " 2>/dev/null || echo '{"title":"","description":""}')

    STORY_TITLE_LOCAL=$(echo "$STORY_META" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(JSON.parse(d).title||''))" 2>/dev/null || echo "")
    STORY_DESC_LOCAL=$(echo "$STORY_META" | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>process.stdout.write(JSON.parse(d).description||''))" 2>/dev/null || echo "")

    STORY_TYPE=$(classify_story "$STORY_TITLE_LOCAL" "$STORY_DESC_LOCAL")

    if [[ "$STORY_TYPE" != "feature" ]]; then
      echo "  🔀 Story classified as: $STORY_TYPE — attempting local model"
      if run_local_prereq "$STORY_ID" "$STORY_TITLE_LOCAL" "$STORY_TYPE"; then
        LOCAL_PREREQ_DONE=true
        # Route model to haiku for any follow-up (cheaper than sonnet)
        MODEL="claude-haiku-4-5-20251001"
        echo "  💡 Local pre-generation succeeded — Claude ($MODEL) will verify and refine"
      else
        echo "  🔁 Local pre-generation skipped — running full Claude ($MODEL)"
      fi
    fi
  fi

  # Run before_run hook — if it fails, skip this attempt (retry next iteration)
  if ! run_hook "before_run" "${WORKTREE_PATH:-$(pwd)}"; then
    echo "  ⏭️  before_run hook failed — skipping this attempt"
    continue
  fi

  # Run Claude with timeout
  if [[ "$USE_DOCKER" == "true" ]]; then
    echo "  🤖 Running Claude ($MODEL) in Docker..."
  else
    echo "  🤖 Running Claude ($MODEL)..."
  fi

  # Docker/worktree wrapper — runs Claude in the right context
  # Uses --prompt-file to avoid "Argument list too long" on Windows
  run_claude() {
    local work_dir="${WORKTREE_PATH:-$(pwd)}"

    # Prevent "nested session" detection when launched from within Claude Code
    unset CLAUDECODE 2>/dev/null || true

    if [[ "$USE_DOCKER" == "true" ]]; then
      local DOCKER_COMPOSE_FILE=""
      for f in docker/docker-compose.yml .claude-framework/docker/docker-compose.yml; do
        if [[ -f "$f" ]]; then DOCKER_COMPOSE_FILE="$f"; break; fi
      done
      if [[ -z "$DOCKER_COMPOSE_FILE" ]]; then
        echo "  ⚠️  Docker compose file not found — falling back to direct execution"
        (cd "$work_dir" && claude --dangerously-skip-permissions -p --model "$MODEL" < "$PROMPT_FILE")
        return $?
      fi
      WORKSPACE="$work_dir" \
        docker compose -f "$DOCKER_COMPOSE_FILE" run --rm \
        -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
        agent \
        --dangerously-skip-permissions \
        -p --model "$MODEL" < "$PROMPT_FILE"
    else
      (cd "$work_dir" && claude --dangerously-skip-permissions -p --model "$MODEL" < "$PROMPT_FILE")
    fi
  }

  ITER_START=$(date +%s)
  TIMED_OUT=false
  STALL_KILLED=false
  rm -f "/tmp/ralph_stall_$$"

  # Run Claude with background watchdog for timeout
  run_claude 2>&1 | tee "$LOG_FILE" &
  CLAUDE_PID=$!

  # Watchdog: kill if exceeds timeout
  (
    sleep "$TIMEOUT_SECONDS"
    if kill -0 "$CLAUDE_PID" 2>/dev/null; then
      kill "$CLAUDE_PID" 2>/dev/null || true
      echo "  ⏰ Iteration timed out after ${ITER_TIMEOUT} minutes" >> "$LOG_FILE"
    fi
  ) &
  WATCHDOG_PID=$!

  # Stall watchdog: kill if no output for stall-timeout minutes
  STALL_WATCHDOG_PID=""
  if [[ "$STALL_TIMEOUT" -gt 0 ]]; then
    start_stall_watchdog &
    STALL_WATCHDOG_PID=$!
  fi

  wait "$CLAUDE_PID" 2>/dev/null
  CLAUDE_EXIT=$?
  kill "$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true
  if [[ -n "$STALL_WATCHDOG_PID" ]]; then
    kill "$STALL_WATCHDOG_PID" 2>/dev/null || true
    wait "$STALL_WATCHDOG_PID" 2>/dev/null || true
  fi

  # Check if stall watchdog killed the process
  if [[ -f "/tmp/ralph_stall_$$" ]]; then
    STALL_KILLED=true
    CLAUDE_EXIT=1
    rm -f "/tmp/ralph_stall_$$"
    stall_elapsed=$(( $(date +%s) - ITER_START ))
    emit_ralph_event "stall_detected" "story_id=$STORY_ID" "elapsed_seconds=$stall_elapsed"
  fi

  # Run after_run hook — failure is logged but not fatal
  run_hook "after_run" "${WORKTREE_PATH:-$(pwd)}" || true

  ITER_END=$(date +%s)
  ITER_ELAPSED=$(( ITER_END - ITER_START ))

  if [[ "$CLAUDE_EXIT" -ne 0 ]]; then
    if [[ "$STALL_KILLED" == "true" ]]; then
      echo "  ⏸️  Stall detected: no output for ${STALL_TIMEOUT} minutes — killed agent"
    elif [[ "$ITER_ELAPSED" -ge "$((TIMEOUT_SECONDS - 5))" ]]; then
      echo "  ⏰ Iteration timed out after ${ITER_TIMEOUT} minutes"
      TIMED_OUT=true
    else
      echo "  ⚠️  Claude exited with error — check $LOG_FILE"
    fi
    sleep 5
    if [[ "$TIMED_OUT" != "true" ]] && [[ "$STALL_KILLED" != "true" ]]; then
      continue
    fi
  fi

  rm -f /tmp/ralph_prompt_$$.md /tmp/ralph_continuation_$$.md

  # Merge worktree back to main branch
  if [[ -n "$WORKTREE_PATH" ]]; then
    merge_worktree "$STORY_ID" || {
      echo "  ⚠️  Worktree merge failed — manual resolution needed for $STORY_ID"
      emit_ralph_event "worktree_merge_failed" "story_id=$STORY_ID" "iteration=$ITERATION"
    }
  fi

  # Post-merge: ensure prd.json reflects completed work
  # Worktree Claude may commit code without updating prd.json on the main branch
  if git log --oneline -5 | grep -qi "$STORY_ID"; then
    node -e "
      const fs = require('fs');
      const prd = JSON.parse(fs.readFileSync('${PRD_DIR}/prd.json', 'utf8'));
      const story = prd.userStories.find(s => s.id === '$STORY_ID');
      if (story && !story.passes) {
        story.passes = true;
        fs.writeFileSync('${PRD_DIR}/prd.json', JSON.stringify(prd, null, 2));
        console.log('  📝 Marked $STORY_ID as passed in prd.json (post-merge sync)');
      }
    " 2>/dev/null || true
  fi

  # Extract cost if available
  if [[ "$TRACK_COST" == "true" ]] && [[ "$USE_MAX_PLAN" != "true" ]]; then
    ITER_COST=$(grep -oP 'cost: \$\K[0-9.]+' "$LOG_FILE" 2>/dev/null | tail -1 || echo "0")
    TOTAL_COST=$(node -e "console.log(Math.round(($TOTAL_COST + ${ITER_COST:-0}) * 10000) / 10000)")
    echo "  💰 Iteration cost: \$${ITER_COST:-0} | Total: \$$TOTAL_COST"
  fi

  # Compute iteration wall time
  ITER_END_TIME=$(date +%s)
  ITER_WALL_SECS=$(( ITER_END_TIME - ITER_START ))

  # Quality gate
  GATE_RESULT="skipped"
  if [[ "$QUALITY_GATE" == "true" ]]; then
    echo "  🔍 Running quality gate..."
    GATE_ARGS=""
    if [[ "$STRICT" == "true" ]]; then GATE_ARGS="$GATE_ARGS --strict"; fi
    if [[ "$SKIP_TESTS" == "true" ]]; then GATE_ARGS="$GATE_ARGS --skip-tests"; fi

    if ! bash scripts/quality-gate.sh $GATE_ARGS; then
      echo "  ❌ Quality gate failed — Claude should fix this in the next iteration"
      GATE_RESULT="failed"
    else
      echo "  ✅ Quality gate passed"
      STORIES_COMPLETED=$((STORIES_COMPLETED + 1))
      GATE_RESULT="passed"
    fi
  fi

  # ─── Proof packet collection (always, pass or fail) ────────────────────
  PROOF_STATUS="failed"
  if [[ "$CLAUDE_EXIT" -eq 0 ]] && [[ "$GATE_RESULT" != "failed" ]]; then
    PROOF_STATUS="passed"
  elif [[ "$TIMED_OUT" == "true" ]]; then
    PROOF_STATUS="timeout"
  elif [[ "$STALL_KILLED" == "true" ]]; then
    PROOF_STATUS="stall"
  fi

  collect_proof_packet "$STORY_ID" "$ITERATION" "$PROOF_STATUS" "$CLAUDE_EXIT" "$ITER_WALL_SECS" || true

  # Count new stories completed
  new_remaining=$(count_pending "${PRD_DIR}/prd.json")

  STORIES_THIS_ITER=0
  COMPLETED_STORY_ID=""
  if [[ "$new_remaining" -lt "$remaining" ]]; then
    STORIES_THIS_ITER=$((remaining - new_remaining))
    echo "  ✅ $STORIES_THIS_ITER story completed ($new_remaining remaining)"

    # Find which story was just completed (for verification)
    COMPLETED_STORY_ID=$(node -e "
      const prd = JSON.parse(require('fs').readFileSync('${PRD_DIR}/prd.json', 'utf8'));
      const completed = prd.userStories.filter(s => s.passes);
      if (completed.length > 0) console.log(completed[completed.length - 1].id);
    " 2>/dev/null || echo "")
  fi

  # ─── Verification step ─────────────────────────────────────────────────────
  VERIFY_RESULT="skipped"
  VERIFY_CONFIDENCE=0

  if [[ "$VERIFY" == "true" ]] && [[ -n "$COMPLETED_STORY_ID" ]] && [[ -f "scripts/generate-proof.sh" ]]; then
    echo "  🔍 Running verification for $COMPLETED_STORY_ID..."

    VERIFY_ARGS=("$COMPLETED_STORY_ID" "${PRD_DIR}/prd.json")
    if [[ "$VERIFY_RUNTIME" != "true" ]]; then
      VERIFY_ARGS+=("--skip-runtime")
    else
      [[ -n "$DEV_CMD" ]] && VERIFY_ARGS+=("--dev-cmd" "$DEV_CMD")
      VERIFY_ARGS+=("--dev-url" "$DEV_URL")
    fi

    if bash scripts/generate-proof.sh "${VERIFY_ARGS[@]}" 2>&1 | tee -a "$LOG_FILE"; then
      # Read verdict
      if [[ -f "proof/$COMPLETED_STORY_ID/verdict.json" ]]; then
        VERIFY_CONFIDENCE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('proof/$COMPLETED_STORY_ID/verdict.json','utf8')).confidence)" 2>/dev/null || echo "0")
        VERIFY_VERDICT=$(node -e "console.log(JSON.parse(require('fs').readFileSync('proof/$COMPLETED_STORY_ID/verdict.json','utf8')).verdict)" 2>/dev/null || echo "UNKNOWN")

        if [[ "$VERIFY_VERDICT" == "PASS" ]]; then
          VERIFY_RESULT="passed"
          echo "  ✅ Verification passed (confidence: $VERIFY_CONFIDENCE)"
        else
          VERIFY_RESULT="failed"
          echo "  ❌ Verification failed (confidence: $VERIFY_CONFIDENCE)"
        fi
      else
        VERIFY_RESULT="error"
        echo "  ⚠️  Verification ran but no verdict produced"
      fi
    else
      VERIFY_RESULT="error"
      echo "  ⚠️  Verification script failed"
    fi

    emit_ralph_event "verification" \
      "iteration=$ITERATION" \
      "story_id=$COMPLETED_STORY_ID" \
      "result=$VERIFY_RESULT" \
      "confidence=$VERIFY_CONFIDENCE"
  fi

  # ─── Auto-PR step ──────────────────────────────────────────────────────────
  if [[ "$AUTO_PR" == "true" ]] && [[ "$VERIFY_RESULT" == "passed" ]] && [[ -n "$COMPLETED_STORY_ID" ]]; then
    ABOVE_THRESHOLD=$(node -e "console.log($VERIFY_CONFIDENCE >= $PR_THRESHOLD ? 'yes' : 'no')" 2>/dev/null || echo "no")
    if [[ "$ABOVE_THRESHOLD" == "yes" ]]; then
      echo "  📤 Confidence $VERIFY_CONFIDENCE >= $PR_THRESHOLD — creating PR..."
      create_auto_pr "$COMPLETED_STORY_ID" "${PRD_DIR}/prd.json" "$VERIFY_CONFIDENCE" || true
    else
      echo "  ℹ️  Confidence $VERIFY_CONFIDENCE < $PR_THRESHOLD — needs human review"
      emit_ralph_event "auto_pr_skipped" \
        "story_id=$COMPLETED_STORY_ID" \
        "confidence=$VERIFY_CONFIDENCE" \
        "threshold=$PR_THRESHOLD" \
        "reason=below_threshold"
    fi
  fi

  # Count files changed in this iteration
  FILES_CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l || echo "0")

  emit_ralph_event "iteration_end" \
    "exit_code=$CLAUDE_EXIT" \
    "quality_gate=$GATE_RESULT" \
    "stories_completed=$STORIES_THIS_ITER" \
    "stories_remaining=$new_remaining" \
    "total_cost=$TOTAL_COST" \
    "backoff_seconds=${BACKOFF_DELAY:-0}"

  # Track for next iteration's context injection
  PREV_STORY_ID="$STORY_ID"
  PREV_LOG_FILE="$LOG_FILE"
  if [[ "$STORIES_THIS_ITER" -gt 0 ]]; then
    PREV_RESULT="completed"
  elif [[ "$GATE_RESULT" == "failed" ]]; then
    PREV_RESULT="quality-gate-failed"
  elif [[ "$TIMED_OUT" == "true" ]]; then
    PREV_RESULT="timed-out"
  else
    PREV_RESULT="in-progress"
  fi

  echo ""
  sleep 5
done

# ─── Summary ─────────────────────────────────────────────────────────────────

END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

FINAL_REMAINING=$(count_pending "${PRD_DIR}/prd.json")
emit_ralph_event "session_end"

echo ""
echo "═══════════════════════════════════════"
echo "RALPH LOOP COMPLETE"
echo "═══════════════════════════════════════"
echo "Iterations:        $ITERATION"
echo "Time elapsed:      ${ELAPSED} minutes"
if [[ "$TRACK_COST" == "true" ]] && [[ "$USE_MAX_PLAN" != "true" ]]; then
  echo "Total cost:        \$$TOTAL_COST"
fi
echo ""

# Final PRD status
node -e "
  const prd = JSON.parse(require('fs').readFileSync('${PRD_DIR}/prd.json', 'utf8'));
  const total = prd.userStories.length;
  const done = prd.userStories.filter(s => s.passes).length;
  const pending = prd.userStories.filter(s => !s.passes && !s.stuck);
  const stuck = prd.userStories.filter(s => s.stuck);
  console.log('Stories: ' + done + '/' + total + ' complete');
  if (stuck.length > 0) {
    console.log('STUCK (' + stuck.length + '):');
    stuck.forEach(s => console.log('  🚨 ' + s.id + ': ' + s.title + ' — ' + (s.stuckReason || 'unknown')));
  }
  if (pending.length > 0) {
    console.log('Remaining (' + pending.length + '):');
    pending.forEach(s => console.log('  - ' + s.id + ': ' + s.title));
  }
"
echo ""
echo "Next steps:"
echo "  /review          — Run parallel code review"
echo "  /verify          — Independent verification of completed stories"
echo "  /compound        — Capture learnings to docs/solutions/"
echo ""

# Show proof packet summary if verification was enabled
if [[ "$VERIFY" == "true" ]] && [[ -d "proof" ]]; then
  PROOF_COUNT=$(ls proof/*/verdict.json 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [[ "$PROOF_COUNT" -gt 0 ]]; then
    echo "Verification:"
    echo "  Proof packets: $PROOF_COUNT"
    echo "  Review queue:  bash scripts/hartz-land/review-queue.sh"
    echo ""
  fi
fi
