#!/bin/bash
# session-end.sh — Cleanup and summary when a session ends
# Runs on: Stop (alongside check-complete.sh)
#
# This hook performs end-of-session cleanup:
# - Warns about uncommitted PROGRESS.md changes
# - Warns about stale task locks
# - Outputs a session summary (files changed, duration estimate)
#
# Non-blocking: always exits 0 (informational only)

PROJECT_DIR="$(pwd)"

# ─── Cross-platform file age helper ──────────────────────────────────────────

get_mtime() {
  stat -c %Y "$1" 2>/dev/null \
    || stat -f %m "$1" 2>/dev/null \
    || node -e "console.log(Math.floor(require('fs').statSync(process.argv[1]).mtimeMs/1000))" "$1" 2>/dev/null \
    || echo "0"
}

# ─── Check for uncommitted PROGRESS.md changes ──────────────────────────────

if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  if git diff --name-only 2>/dev/null | grep -q "PROGRESS.md"; then
    echo "SESSION END: PROGRESS.md has uncommitted changes"
    echo "  Consider committing before leaving: git add PROGRESS.md && git commit -m 'docs: update progress'"
    echo ""
  fi
fi

# ─── Warn about stale task locks ─────────────────────────────────────────────

if [[ -d "$PROJECT_DIR/current_tasks" ]]; then
  STALE_LOCKS=0
  NOW=$(date +%s)
  THRESHOLD=$((2 * 3600))  # 2 hours

  for lock in "$PROJECT_DIR/current_tasks/"*.txt; do
    [[ ! -f "$lock" ]] && continue
    LOCK_MTIME=$(get_mtime "$lock")
    AGE=$(( NOW - LOCK_MTIME ))
    if [[ "$AGE" -gt "$THRESHOLD" ]]; then
      STALE_LOCKS=$((STALE_LOCKS + 1))
      LOCK_NAME=$(basename "$lock" .txt)
      LOCK_HOURS=$(( AGE / 3600 ))
      echo "SESSION END: Stale task lock detected — $LOCK_NAME (${LOCK_HOURS}h old)"
    fi
  done

  if [[ "$STALE_LOCKS" -gt 0 ]]; then
    echo "  Remove stale locks: rm current_tasks/<task>.txt && git add -A && git commit -m 'chore: remove stale locks'"
    echo ""
  fi
fi

# ─── Session summary ─────────────────────────────────────────────────────────

# Count files changed since last commit
UNCOMMITTED=$(git diff --name-only 2>/dev/null | wc -l || echo "0")
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l || echo "0")

# Recent commits this session (last 2 hours)
RECENT_COMMITS=$(git log --oneline --since="2 hours ago" 2>/dev/null | wc -l || echo "0")

if [[ "$UNCOMMITTED" -gt 0 ]] || [[ "$STAGED" -gt 0 ]] || [[ "$RECENT_COMMITS" -gt 0 ]]; then
  echo "SESSION SUMMARY:"
  if [[ "$RECENT_COMMITS" -gt 0 ]]; then
    echo "  Commits this session: $RECENT_COMMITS"
  fi
  if [[ "$STAGED" -gt 0 ]]; then
    echo "  Staged files: $STAGED"
  fi
  if [[ "$UNCOMMITTED" -gt 0 ]]; then
    echo "  Uncommitted changes: $UNCOMMITTED files"
  fi
  echo ""
fi

exit 0
