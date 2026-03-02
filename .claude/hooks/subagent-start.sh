#!/bin/bash
# subagent-start.sh — Inject project context into every spawned subagent
# Runs on: SubagentStart
#
# Ensures every subagent starts with awareness of project state, code standards,
# and active task locks — without the parent agent needing to manually inject this.

PROJECT_DIR="$(pwd)"

echo "<subagent-context>"

# ─── Project state summary ────────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  echo "## Current project state (PROGRESS.md summary)"
  head -20 "$PROJECT_DIR/PROGRESS.md"
  echo ""
fi

# ─── Code standards reminder ─────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/docs/CODE-STANDARDS.md" ]]; then
  echo "## Code standards"
  echo "Read docs/CODE-STANDARDS.md before writing code. Violations are automatic P1s."
  echo ""
fi

# ─── Active task locks ────────────────────────────────────────────────────────

if [[ -d "$PROJECT_DIR/current_tasks" ]]; then
  TASK_FILES=$(find "$PROJECT_DIR/current_tasks" -name "*.txt" -type f 2>/dev/null)
  if [[ -n "$TASK_FILES" ]]; then
    echo "## Active task locks (do NOT claim)"
    while IFS= read -r f; do
      echo "  - $(basename "$f" .txt): $(cat "$f")"
    done <<< "$TASK_FILES"
    echo ""
  fi
fi

# ─── Recent failed approaches ────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/docs/failed-approaches.md" ]]; then
  HEADINGS=$(grep "^##" "$PROJECT_DIR/docs/failed-approaches.md" 2>/dev/null | tail -3)
  if [[ -n "$HEADINGS" ]]; then
    echo "## Recent failed approaches (do NOT retry)"
    echo "$HEADINGS"
    echo ""
  fi
fi

echo "</subagent-context>"

exit 0
