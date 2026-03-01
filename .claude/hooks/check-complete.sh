#!/bin/bash
# check-complete.sh — Completion gate: verify work is done before stopping
# Runs on: Stop
#
# Checks PROGRESS.md for incomplete items and whether it was updated recently.
# Exit 0 = allow stop (with informational output)
# Exit 2 = block stop (force agent to update PROGRESS.md first)

PROJECT_DIR="$(pwd)"

# If no PROGRESS.md, allow stop
if [[ ! -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  exit 0
fi

# ─── Check if PROGRESS.md was updated this session ───────────────────────────

LAST_MODIFIED=$(stat -c %Y "$PROJECT_DIR/PROGRESS.md" 2>/dev/null || stat -f %m "$PROJECT_DIR/PROGRESS.md" 2>/dev/null || echo "0")
NOW=$(date +%s)
AGE=$(( NOW - LAST_MODIFIED ))

# If PROGRESS.md hasn't been updated in over 2 hours, block stop
if [[ "$AGE" -gt 7200 ]]; then
  echo "STOP BLOCKED — PROGRESS.md not updated this session"
  echo ""
  echo "Before stopping, you MUST update PROGRESS.md with:"
  echo "  1. What you worked on this session"
  echo "  2. What's next"
  echo "  3. Any new blockers or decisions"
  echo ""
  echo "This ensures the next session can pick up where you left off."
  exit 2
fi

# ─── Check for incomplete work (informational, doesn't block) ────────────────

INCOMPLETE_ITEMS=""

# Check for in-progress markers
if grep -qiE "(in.?progress|pending|blocked|not started)" "$PROJECT_DIR/PROGRESS.md" 2>/dev/null; then
  INCOMPLETE_ITEMS=$(grep -iE "(in.?progress|pending|blocked|not started)" "$PROJECT_DIR/PROGRESS.md" 2>/dev/null | head -5)
fi

# Check for active task locks
ACTIVE_TASKS=0
if [[ -d "$PROJECT_DIR/current_tasks" ]]; then
  ACTIVE_TASKS=$(find "$PROJECT_DIR/current_tasks" -name "*.txt" -type f 2>/dev/null | wc -l)
fi

# If there's incomplete work, inform but don't block
if [[ -n "$INCOMPLETE_ITEMS" ]] || [[ "$ACTIVE_TASKS" -gt 0 ]]; then
  echo "COMPLETION CHECK — Items still open"
  echo ""

  if [[ -n "$INCOMPLETE_ITEMS" ]]; then
    echo "Open items in PROGRESS.md:"
    echo "$INCOMPLETE_ITEMS" | while IFS= read -r line; do
      echo "  $line"
    done
    echo ""
  fi

  if [[ "$ACTIVE_TASKS" -gt 0 ]]; then
    echo "Active task locks: $ACTIVE_TASKS"
    find "$PROJECT_DIR/current_tasks" -name "*.txt" -type f 2>/dev/null | while IFS= read -r f; do
      echo "  - $(basename "$f" .txt): $(cat "$f")"
    done
    echo ""
  fi

  echo "If you're done for now, this is fine — PROGRESS.md has been updated."
  echo "The next session will pick up from where you left off."
fi

exit 0
