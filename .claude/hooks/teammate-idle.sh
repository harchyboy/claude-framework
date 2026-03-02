#!/bin/bash
# teammate-idle.sh — Runs when an Agent Team teammate goes idle
# Exit with code 2 to give the agent a new task (keeps them working)
# Exit with code 0 to allow shutdown
#
# Environment variables:
#   AGENT_NAME    — which agent is idle
#   TEAM_NAME     — current team name

PROJECT_DIR="$(pwd)"

# ─── Check for unclaimed task lock files ──────────────────────────────────────

UNCLAIMED_TASKS=0
if [[ -d "$PROJECT_DIR/current_tasks" ]]; then
  # Task files with content "UNCLAIMED" or empty are available
  for f in "$PROJECT_DIR/current_tasks/"*.txt; do
    [[ ! -f "$f" ]] && continue
    content=$(cat "$f" 2>/dev/null || true)
    if [[ -z "$content" ]] || [[ "$content" == *"UNCLAIMED"* ]]; then
      UNCLAIMED_TASKS=$((UNCLAIMED_TASKS + 1))
    fi
  done
fi

# ─── Check for incomplete PRD stories ─────────────────────────────────────────

PENDING_STORIES=0
for prd_file in "$PROJECT_DIR"/scripts/ralph-moss/prds/*/prd.json; do
  [[ ! -f "$prd_file" ]] && continue
  # Count stories where passes is false or missing
  count=$(node -e "
    const prd = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'));
    const pending = (prd.userStories || []).filter(s => !s.passes);
    process.stdout.write(String(pending.length));
  " "$prd_file" 2>/dev/null || echo "0")
  PENDING_STORIES=$((PENDING_STORIES + count))
done

# ─── Check PROGRESS.md for in-progress items ─────────────────────────────────

OPEN_ITEMS=0
if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  OPEN_ITEMS=$(grep -ciE "(in.?progress|pending|blocked|not started)" "$PROJECT_DIR/PROGRESS.md" 2>/dev/null || echo "0")
fi

# ─── Decision: keep working or allow shutdown ─────────────────────────────────

TOTAL_WORK=$((UNCLAIMED_TASKS + PENDING_STORIES + OPEN_ITEMS))

if [[ "$TOTAL_WORK" -gt 0 ]]; then
  echo "There is still work available before shutting down:"
  echo ""
  if [[ "$UNCLAIMED_TASKS" -gt 0 ]]; then
    echo "  - $UNCLAIMED_TASKS unclaimed task(s) in current_tasks/"
  fi
  if [[ "$PENDING_STORIES" -gt 0 ]]; then
    echo "  - $PENDING_STORIES pending PRD story/stories"
  fi
  if [[ "$OPEN_ITEMS" -gt 0 ]]; then
    echo "  - $OPEN_ITEMS open item(s) in PROGRESS.md"
  fi
  echo ""
  echo "Check the task list for any tasks matching your role before shutting down."
  echo "If nothing matches your specialisation, you may shut down."

  # Exit 2 keeps the agent alive to check the task list
  exit 2
fi

# No work found — allow graceful shutdown
echo "No unclaimed tasks or pending work found. Shutdown approved."
exit 0
