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
#   --skip-tests        Skip tests in quality gate
#   --skip-preflight    Skip PRD validation
#   --no-cost           Disable cost tracking
#   --help              Show this help

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

MAX_ITERATIONS=20
USE_MAX_PLAN=false
MAX_COST=""
QUALITY_GATE=false
REVIEW=false
STRICT=false
SKIP_TESTS=false
SKIP_PREFLIGHT=false
TRACK_COST=true
TOTAL_COST=0
START_TIME=$(date +%s)

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
    --quality-gate)  QUALITY_GATE=true ;;
    --review)        REVIEW=true ;;
    --strict)        STRICT=true ;;
    --skip-tests)    SKIP_TESTS=true ;;
    --skip-preflight) SKIP_PREFLIGHT=true ;;
    --no-cost)       TRACK_COST=false ;;
    --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# ─── Find PRD ────────────────────────────────────────────────────────────────

PRD_DIR=""
AGENT_PROMPT=""

# Look for PRDs with incomplete stories
for dir in scripts/ralph-moss/prds/*/; do
  if [[ -f "$dir/prd.json" ]]; then
    incomplete=$(python3 -c "
import json, sys
with open('$dir/prd.json') as f:
    prd = json.load(f)
pending = [s for s in prd['userStories'] if not s.get('passes', False)]
print(len(pending))
" 2>/dev/null || echo "0")
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
  python3 -c "
import json, sys
with open('${PRD_DIR}/prd.json') as f:
    prd = json.load(f)

required = ['project', 'branchName', 'description', 'userStories']
for field in required:
    if field not in prd:
        print(f'ERROR: Missing required field: {field}')
        sys.exit(1)

for story in prd['userStories']:
    if len(story.get('acceptanceCriteria', [])) < 2:
        print(f'WARNING: Story {story[\"id\"]} has fewer than 2 acceptance criteria')

pending = [s for s in prd['userStories'] if not s.get('passes', False)]
print(f'✅ PRD valid: {len(pending)} stories pending')
" || exit 1

  # Check git is clean (warn only, never block)
  if ! git diff --quiet 2>/dev/null; then
    echo "⚠️ Working directory has uncommitted changes — continuing anyway"
  fi

  # Ensure branch exists
  BRANCH_NAME=$(python3 -c "import json; print(json.load(open('${PRD_DIR}/prd.json'))['branchName'])")
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

1. **Read first**: Review PROGRESS.md and docs/solutions/ for relevant context
2. **Check failed approaches**: Read docs/failed-approaches.md before attempting solutions
3. **Pick a story**: Select the highest-priority story where \`passes: false\`
   - Skip any story with a lock file in current_tasks/
4. **Claim it**: Write \`[story-id] [title]\` to \`current_tasks/[story-id].txt\`
   - \`git add current_tasks/ && git commit -m "claim: [story-id]" && git push\`
   - If push fails: another agent claimed it — pick a different story
5. **Implement**: Build the feature with proper TypeScript types and tests
6. **Test**: Run the quality gate: \`bash scripts/quality-gate.sh\`
   - Fix ALL failures before proceeding
7. **Update PROGRESS.md**: Add what you did, what's next, any discoveries
8. **Commit**: Use conventional commit format: \`feat: [description] (closes [story-id])\`
9. **Update PRD**: Mark story \`passes: true\` in prd.json, commit that too
10. **Release lock**: \`git rm current_tasks/[story-id].txt && git commit -m "release: [story-id]" && git push\`
11. **Stop**: Exit after completing ONE story. The loop will restart for the next.

## Rules
- NEVER skip the quality gate
- NEVER mark a story as passed without all acceptance criteria met
- NEVER work on a locked task
- If stuck after 3 attempts: document in docs/failed-approaches.md and pick a different story
- Check docs/solutions/ before implementing any non-trivial pattern

PROMPT
}

# ─── Main loop ───────────────────────────────────────────────────────────────

echo ""
echo "🚀 Starting Ralph loop"
echo "   Max iterations: $MAX_ITERATIONS"
echo "   Quality gate: $QUALITY_GATE"
echo "   Review: $REVIEW"
echo "   PRD: $PRD_DIR"
echo ""

ITERATION=0
STORIES_COMPLETED=0

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  ITERATION=$((ITERATION + 1))

  # Check if all stories are done
  remaining=$(python3 -c "
import json
with open('${PRD_DIR}/prd.json') as f:
    prd = json.load(f)
pending = [s for s in prd['userStories'] if not s.get('passes', False)]
print(len(pending))
" 2>/dev/null || echo "0")

  if [[ "$remaining" -eq 0 ]]; then
    echo "🎉 All stories complete! PRD finished."
    break
  fi

  # Cost check
  if [[ -n "$MAX_COST" ]] && [[ "$TRACK_COST" == "true" ]]; then
    cost_check=$(python3 -c "print('OVER' if $TOTAL_COST > $MAX_COST else 'OK')")
    if [[ "$cost_check" == "OVER" ]]; then
      echo "💰 Cost limit reached: \$$TOTAL_COST / \$$MAX_COST"
      break
    fi
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "▶ Iteration $ITERATION / $MAX_ITERATIONS — $remaining stories remaining"
  echo "  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Sync with remote
  git pull origin "$(git branch --show-current)" --rebase 2>/dev/null || true

  COMMIT=$(git rev-parse --short=6 HEAD)
  LOG_FILE="agent_logs/iteration_${ITERATION}_${COMMIT}.log"

  # Build and save the prompt
  build_iteration_prompt > /tmp/ralph_prompt_$$.md

  # Determine model
  MODEL="claude-sonnet-4-5"
  if [[ "$USE_MAX_PLAN" == "true" ]]; then
    MODEL="claude-sonnet-4-5"
  fi

  # Run Claude
  echo "  🤖 Running Claude ($MODEL)..."

  CLAUDE_ARGS=(
    --dangerously-skip-permissions
    -p "$(cat /tmp/ralph_prompt_$$.md)"
    --model "$MODEL"
  )

  if ! claude "${CLAUDE_ARGS[@]}" 2>&1 | tee "$LOG_FILE"; then
    echo "  ⚠️  Claude exited with error — check $LOG_FILE"
    sleep 10
    continue
  fi

  rm -f /tmp/ralph_prompt_$$.md

  # Extract cost if available
  if [[ "$TRACK_COST" == "true" ]] && [[ "$USE_MAX_PLAN" != "true" ]]; then
    ITER_COST=$(grep -oP 'cost: \$\K[0-9.]+' "$LOG_FILE" 2>/dev/null | tail -1 || echo "0")
    TOTAL_COST=$(python3 -c "print(round($TOTAL_COST + ${ITER_COST:-0}, 4))")
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
  new_remaining=$(python3 -c "
import json
with open('${PRD_DIR}/prd.json') as f:
    prd = json.load(f)
pending = [s for s in prd['userStories'] if not s.get('passes', False)]
print(len(pending))
" 2>/dev/null || echo "$remaining")

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
python3 -c "
import json
with open('${PRD_DIR}/prd.json') as f:
    prd = json.load(f)
total = len(prd['userStories'])
done = sum(1 for s in prd['userStories'] if s.get('passes', False))
pending = [s for s in prd['userStories'] if not s.get('passes', False)]
print(f'Stories: {done}/{total} complete')
if pending:
    print('Remaining:')
    for s in pending:
        print(f'  - {s[\"id\"]}: {s[\"title\"]}')
"
echo ""
echo "Next steps:"
echo "  /review          — Run parallel code review"
echo "  /compound        — Capture learnings to docs/solutions/"
echo ""
