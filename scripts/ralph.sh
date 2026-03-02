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
START_TIME=$(date +%s)
STALE_LOCK_HOURS=2

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

# ─── Helper: clean stale locks ──────────────────────────────────────────────

clean_stale_locks() {
  if [[ ! -d "current_tasks" ]]; then return; fi

  local now
  now=$(date +%s)
  local threshold=$((STALE_LOCK_HOURS * 3600))
  local cleaned=0

  for lock_file in current_tasks/*.txt; do
    [[ ! -f "$lock_file" ]] && continue

    local file_age
    file_age=$(node -e "
      const fs = require('fs');
      const stat = fs.statSync('$lock_file');
      console.log(Math.floor((Date.now() - stat.mtimeMs) / 1000));
    " 2>/dev/null || echo "0")

    if [[ "$file_age" -gt "$threshold" ]]; then
      local task_name
      task_name=$(basename "$lock_file" .txt)
      echo "  🧹 Removing stale lock: $task_name (${STALE_LOCK_HOURS}h+ old)"
      rm -f "$lock_file"
      cleaned=$((cleaned + 1))
    fi
  done

  if [[ "$cleaned" -gt 0 ]]; then
    git add current_tasks/ 2>/dev/null || true
    git commit -m "chore: remove $cleaned stale task lock(s)" 2>/dev/null || true
    git push 2>/dev/null || true
  fi
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

mkdir -p agent_logs current_tasks

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

  local current_tasks_list=""
  if compgen -G "current_tasks/*.txt" > /dev/null 2>&1; then
    current_tasks_list=$(cat current_tasks/*.txt 2>/dev/null | tr '\n' ', ' || true)
  fi

  cat <<PROMPT
# Ralph Loop — Autonomous Development Session

## Your objective
Work through the PRD below, implementing one user story per session.
Each story must be fully complete (tests passing, code committed) before you stop.

## Current project state

### PROGRESS.md
${progress_content:-No PROGRESS.md found. Start by creating one.}

### Available learnings (docs/solutions/)
${solutions_index:-No solutions documented yet.}

### Currently locked tasks (do NOT claim these)
${current_tasks_list:-None locked.}

## PRD
\`\`\`json
${prd_content}
\`\`\`

## Instructions

1. **Read first**: Review PROGRESS.md, docs/CODE-STANDARDS.md, and docs/solutions/ for relevant context
2. **Follow code standards**: docs/CODE-STANDARDS.md contains mandatory patterns — apply them during implementation, not after review
3. **Check failed approaches**: Read docs/failed-approaches.md before attempting solutions
4. **Pick a story**: Select the highest-priority story where \`passes: false\`
   - Skip any story with a lock file in current_tasks/
5. **Claim it**: Write \`[story-id] [title]\` to \`current_tasks/[story-id].txt\`
   - \`git add current_tasks/ && git commit -m "claim: [story-id]" && git push\`
   - If push fails: another agent claimed it — pick a different story
6. **Implement**: Build the feature following docs/CODE-STANDARDS.md patterns
7. **Test**: Run the quality gate: \`bash scripts/quality-gate.sh\`
   - Fix ALL failures before proceeding
8. **Update PROGRESS.md**: Add what you did, what's next, any discoveries
9. **Commit**: Use conventional commit format: \`feat: [description] (closes [story-id])\`
10. **Update PRD**: Mark story \`passes: true\` in prd.json, commit that too
11. **Release lock**: \`git rm current_tasks/[story-id].txt && git commit -m "release: [story-id]" && git push\`
12. **Stop**: Exit after completing ONE story. The loop will restart for the next.

## Rules
- NEVER skip the quality gate
- NEVER mark a story as passed without all acceptance criteria met
- NEVER work on a locked task
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
echo "   PRD: $PRD_DIR"
echo ""

ITERATION=0
STORIES_COMPLETED=0

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))

  # Clean stale locks before each iteration
  clean_stale_locks

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
  echo "  🤖 Running Claude ($MODEL)..."

  CLAUDE_ARGS=(
    --dangerously-skip-permissions
    -p "$(cat /tmp/ralph_prompt_$$.md)"
    --model "$MODEL"
  )

  ITER_START=$(date +%s)
  TIMED_OUT=false

  if command -v timeout > /dev/null 2>&1; then
    # GNU timeout available (Linux, MSYS)
    if ! timeout "${TIMEOUT_SECONDS}s" claude "${CLAUDE_ARGS[@]}" 2>&1 | tee "$LOG_FILE"; then
      ITER_END=$(date +%s)
      ITER_ELAPSED=$(( ITER_END - ITER_START ))
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
  else
    # No timeout command — run with background watchdog
    claude "${CLAUDE_ARGS[@]}" 2>&1 | tee "$LOG_FILE" &
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

    wait "$CLAUDE_PID" 2>/dev/null || true
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
  fi

  rm -f /tmp/ralph_prompt_$$.md

  # Extract cost if available
  if [[ "$TRACK_COST" == "true" ]] && [[ "$USE_MAX_PLAN" != "true" ]]; then
    ITER_COST=$(grep -oP 'cost: \$\K[0-9.]+' "$LOG_FILE" 2>/dev/null | tail -1 || echo "0")
    TOTAL_COST=$(node -e "console.log(Math.round(($TOTAL_COST + ${ITER_COST:-0}) * 10000) / 10000)")
    echo "  💰 Iteration cost: \$${ITER_COST:-0} | Total: \$$TOTAL_COST"
  fi

  # Quality gate
  if [[ "$QUALITY_GATE" == "true" ]]; then
    echo "  🔍 Running quality gate..."
    GATE_ARGS=""
    if [[ "$STRICT" == "true" ]]; then GATE_ARGS="$GATE_ARGS --strict"; fi
    if [[ "$SKIP_TESTS" == "true" ]]; then GATE_ARGS="$GATE_ARGS --skip-tests"; fi

    if ! bash scripts/quality-gate.sh $GATE_ARGS; then
      echo "  ❌ Quality gate failed — Claude should fix this in the next iteration"
    else
      echo "  ✅ Quality gate passed"
      STORIES_COMPLETED=$((STORIES_COMPLETED + 1))
    fi
  fi

  # Count new stories completed
  new_remaining=$(count_pending "${PRD_DIR}/prd.json")

  if [[ "$new_remaining" -lt "$remaining" ]]; then
    completed=$((remaining - new_remaining))
    echo "  ✅ $completed story completed ($new_remaining remaining)"
  fi

  echo ""
  sleep 5
done

# ─── Summary ─────────────────────────────────────────────────────────────────

END_TIME=$(date +%s)
ELAPSED=$(( (END_TIME - START_TIME) / 60 ))

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
echo "  /compound        — Capture learnings to docs/solutions/"
echo ""
