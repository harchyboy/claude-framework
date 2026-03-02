#!/bin/bash
# pre-compact.sh — Save session state before context compaction
# Runs on: PreCompact
#
# Automatically snapshots PROGRESS.md and recent git activity so the
# compacted session can reorient without manual session-catchup.sh.
# Output goes to stdout and is injected into Claude's post-compaction context.

PROJECT_DIR="$(pwd)"

echo "<pre-compact-recovery timestamp=\"$(date '+%Y-%m-%d %H:%M:%S')\">"

# ─── Snapshot PROGRESS.md ─────────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  echo "## PROGRESS.md (snapshot before compaction)"
  head -50 "$PROJECT_DIR/PROGRESS.md"
  echo ""
fi

# ─── Recent git activity ─────────────────────────────────────────────────────

if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "## Recent commits"
  git log --oneline -10 2>/dev/null || true
  echo ""

  echo "## Modified files (uncommitted)"
  git diff --name-only 2>/dev/null || true
  git diff --cached --name-only 2>/dev/null || true
  echo ""
fi

# ─── Active task locks ────────────────────────────────────────────────────────

if [[ -d "$PROJECT_DIR/current_tasks" ]]; then
  TASK_FILES=$(find "$PROJECT_DIR/current_tasks" -name "*.txt" -type f 2>/dev/null)
  if [[ -n "$TASK_FILES" ]]; then
    echo "## Active task locks"
    while IFS= read -r f; do
      echo "  - $(basename "$f" .txt): $(cat "$f")"
    done <<< "$TASK_FILES"
    echo ""
  fi
fi

# ─── Failed approaches (headings only) ───────────────────────────────────────

if [[ -f "$PROJECT_DIR/docs/failed-approaches.md" ]]; then
  HEADINGS=$(grep "^##" "$PROJECT_DIR/docs/failed-approaches.md" 2>/dev/null | tail -5)
  if [[ -n "$HEADINGS" ]]; then
    echo "## Recent failed approaches (do NOT retry)"
    echo "$HEADINGS"
    echo ""
  fi
fi

echo "</pre-compact-recovery>"
echo ""
echo "CONTEXT WAS COMPACTED. The above snapshot contains your pre-compaction state."
echo "Read PROGRESS.md for full context if needed."

exit 0
