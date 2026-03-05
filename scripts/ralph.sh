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
#   --telemetry         Write structured JSON logs to agent_logs/ralph-telemetry.jsonl
#   --verify            Run independent verification after each story (generates proof packets)
#   --verify-runtime    Include Playwright runtime verification (requires running dev server)
#   --dev-cmd <cmd>     Dev server start command for runtime verification
#   --dev-url <url>     Dev server URL (default: http://localhost:3000)
#   --docker            Run Claude inside Docker container with network isolation
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
VERIFY=false
VERIFY_RUNTIME=false
DEV_CMD=""
DEV_URL="http://localhost:3000"
USE_DOCKER=false
START_TIME=$(date +%s)
STALE_LOCK_HOURS=2
TELEMETRY_FILE="agent_logs/ralph-telemetry.jsonl"

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
    --verify)        VERIFY=true ;;
    --verify-runtime) VERIFY_RUNTIME=true; VERIFY=true ;;
    --dev-cmd)       DEV_CMD="$2"; shift ;;
    --dev-url)       DEV_URL="$2"; shift ;;
    --docker)        USE_DOCKER=true ;;
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
    const pending = prd.userStories.filter(s => !s.passes);
    console.log(pending.length);
  " 2>/dev/null || echo "0"
}

# ─── Helper: emit telemetry event ────────────────────────────────────────────

emit_telemetry() {
  if [[ "$TELEMETRY" != "true" ]]; then return; fi

  local event_type="$1"
  shift

  # Remaining args are key=value pairs
  local fields=""
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    # Escape quotes in values
    val="${val//\"/\\\"}"
    if [[ -n "$fields" ]]; then fields="$fields, "; fi
    # Auto-detect numbers vs strings
    if [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      fields="$fields\"$key\": $val"
    elif [[ "$val" == "true" || "$val" == "false" ]]; then
      fields="$fields\"$key\": $val"
    else
      fields="$fields\"$key\": \"$val\""
    fi
  done

  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  echo "{\"timestamp\": \"$timestamp\", \"event\": \"$event_type\", $fields}" >> "$TELEMETRY_FILE"
}

# ─── Helper: pick next story ID from PRD ────────────────────────────────────

pick_next_story() {
  local prd_file="$1"
  node -e "
    const prd = JSON.parse(require('fs').readFileSync('$prd_file', 'utf8'));
    const pending = prd.userStories
      .filter(s => !s.passes)
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

  # Clean up if stale worktree exists
  if [[ -d "$worktree_path" ]]; then
    echo "  🧹 Cleaning stale worktree: $story_id" >&2
    git worktree remove "$worktree_path" --force >/dev/null 2>&1 || rm -rf "$worktree_path"
    git branch -D "$branch_name" >/dev/null 2>&1 || true
  fi

  mkdir -p "$WORKTREE_DIR"
  git worktree add "$worktree_path" -b "$branch_name" HEAD >/dev/null 2>&1
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
    if git merge "$branch_name" --no-edit 2>/dev/null; then
      echo "  ✅ Merge successful"
    else
      echo "  ⚠️  Merge conflict — keeping worktree branch for manual resolution"
      git merge --abort 2>/dev/null || true
      return 1
    fi
  else
    echo "  ℹ️  No new commits in worktree"
  fi

  # Clean up
  git worktree remove "$worktree_path" --force 2>/dev/null || rm -rf "$worktree_path"
  git branch -D "$branch_name" 2>/dev/null || true
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

# ─── Main loop ───────────────────────────────────────────────────────────────

TIMEOUT_SECONDS=$((ITER_TIMEOUT * 60))

echo ""
echo "🚀 Starting Ralph loop"
echo "   Max iterations: $MAX_ITERATIONS"
echo "   Iteration timeout: ${ITER_TIMEOUT} minutes"
echo "   Quality gate: $QUALITY_GATE"
echo "   Review: $REVIEW"
echo "   Telemetry: $TELEMETRY"
echo "   Verification: $VERIFY"
echo "   Docker: $USE_DOCKER"
echo "   Worktrees: $WORKTREE_DIR"
echo "   PRD: $PRD_DIR"
echo ""

emit_telemetry "session_start" \
  "prd=$PRD_DIR" \
  "max_iterations=$MAX_ITERATIONS" \
  "timeout_min=$ITER_TIMEOUT" \
  "quality_gate=$QUALITY_GATE" \
  "model=${MODEL_OVERRIDE:-claude-sonnet-4-6}"

ITERATION=0
STORIES_COMPLETED=0

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))

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

  emit_telemetry "iteration_start" \
    "iteration=$ITERATION" \
    "stories_remaining=$remaining" \
    "total_cost=$TOTAL_COST"

  # Sync with remote
  git pull origin "$(git branch --show-current)" --rebase 2>/dev/null || true

  # Pick next story and create worktree
  STORY_ID=$(pick_next_story "${PRD_DIR}/prd.json")
  if [[ -z "$STORY_ID" ]]; then
    echo "  ℹ️  No pending stories found"
    break
  fi
  echo "  📌 Target story: $STORY_ID"

  WORKTREE_PATH=""
  if git worktree list > /dev/null 2>&1; then
    WORKTREE_PATH=$(create_worktree "$STORY_ID") || {
      echo "  ⚠️  Worktree creation failed — running in main tree"
      WORKTREE_PATH=""
    }
  fi

  COMMIT=$(git rev-parse --short=6 HEAD)
  LOG_FILE="agent_logs/iteration_${ITERATION}_${COMMIT}.log"

  # Build and save the prompt
  build_iteration_prompt > /tmp/ralph_prompt_$$.md

  # Determine model
  if [[ -n "$MODEL_OVERRIDE" ]]; then
    MODEL="$MODEL_OVERRIDE"
  else
    MODEL="claude-sonnet-4-6"
  fi

  # Run Claude with timeout
  if [[ "$USE_DOCKER" == "true" ]]; then
    echo "  🤖 Running Claude ($MODEL) in Docker..."
  else
    echo "  🤖 Running Claude ($MODEL)..."
  fi

  CLAUDE_ARGS=(
    --dangerously-skip-permissions
    -p "$(cat /tmp/ralph_prompt_$$.md)"
    --model "$MODEL"
  )

  # Docker/worktree wrapper — runs Claude in the right context
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
        (cd "$work_dir" && claude "${CLAUDE_ARGS[@]}")
        return $?
      fi
      WORKSPACE="$work_dir" PROMPT="$(cat /tmp/ralph_prompt_$$.md)" \
        docker compose -f "$DOCKER_COMPOSE_FILE" run --rm \
        -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
        agent \
        --dangerously-skip-permissions \
        -p "$(cat /tmp/ralph_prompt_$$.md)" \
        --model "$MODEL"
    else
      (cd "$work_dir" && claude "${CLAUDE_ARGS[@]}")
    fi
  }

  ITER_START=$(date +%s)
  TIMED_OUT=false

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

  wait "$CLAUDE_PID" 2>/dev/null
  CLAUDE_EXIT=$?
  kill "$WATCHDOG_PID" 2>/dev/null || true
  wait "$WATCHDOG_PID" 2>/dev/null || true

  ITER_END=$(date +%s)
  ITER_ELAPSED=$(( ITER_END - ITER_START ))

  if [[ "$CLAUDE_EXIT" -ne 0 ]]; then
    if [[ "$ITER_ELAPSED" -ge "$((TIMEOUT_SECONDS - 5))" ]]; then
      echo "  ⏰ Iteration timed out after ${ITER_TIMEOUT} minutes"
      TIMED_OUT=true
    else
      echo "  ⚠️  Claude exited with error — check $LOG_FILE"
    fi
    sleep 5
    if [[ "$TIMED_OUT" != "true" ]]; then
      continue
    fi
  fi

  rm -f /tmp/ralph_prompt_$$.md

  # Merge worktree back to main branch
  if [[ -n "$WORKTREE_PATH" ]]; then
    merge_worktree "$STORY_ID" || {
      echo "  ⚠️  Worktree merge failed — manual resolution needed for $STORY_ID"
      emit_telemetry "worktree_merge_failed" "story_id=$STORY_ID" "iteration=$ITERATION"
    }
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

  emit_telemetry "claude_completed" \
    "iteration=$ITERATION" \
    "wall_time_secs=$ITER_WALL_SECS" \
    "timed_out=$TIMED_OUT" \
    "model=$MODEL" \
    "cost=${ITER_COST:-0}"

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

    emit_telemetry "verification" \
      "iteration=$ITERATION" \
      "story_id=$COMPLETED_STORY_ID" \
      "result=$VERIFY_RESULT" \
      "confidence=$VERIFY_CONFIDENCE"
  fi

  # Count files changed in this iteration
  FILES_CHANGED=$(git diff --name-only HEAD~1 HEAD 2>/dev/null | wc -l || echo "0")

  emit_telemetry "iteration_end" \
    "iteration=$ITERATION" \
    "wall_time_secs=$ITER_WALL_SECS" \
    "quality_gate=$GATE_RESULT" \
    "verification=$VERIFY_RESULT" \
    "verify_confidence=$VERIFY_CONFIDENCE" \
    "stories_completed=$STORIES_THIS_ITER" \
    "stories_remaining=$new_remaining" \
    "files_changed=$FILES_CHANGED" \
    "total_cost=$TOTAL_COST"

  # Track for next iteration's context injection
  PREV_STORY_ID="$STORY_ID"
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
emit_telemetry "session_end" \
  "iterations=$ITERATION" \
  "elapsed_min=$ELAPSED" \
  "total_cost=$TOTAL_COST" \
  "stories_remaining=$FINAL_REMAINING" \
  "prd=$PRD_DIR"

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
  const pending = prd.userStories.filter(s => !s.passes);
  console.log('Stories: ' + done + '/' + total + ' complete');
  if (pending.length > 0) {
    console.log('Remaining:');
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
