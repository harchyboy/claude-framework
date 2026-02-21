#!/bin/bash
# task-completed.sh — Runs when an Agent Team task is marked complete
# Exit with code 2 to reject completion and send feedback to the agent
# Exit with code 0 to allow completion
#
# Environment variables available:
#   TASK_ID       — the task being completed
#   TASK_SUBJECT  — task title
#   AGENT_NAME    — which agent is completing it

set -euo pipefail

# Run quality gate as a lightweight check
# Only run if we're in a project directory with a quality gate
if [[ -f "scripts/quality-gate.sh" ]]; then
  if ! bash scripts/quality-gate.sh --skip-tests 2>&1; then
    # Send feedback — exit 2 means "reject this completion and tell the agent"
    echo "Quality gate failed. TypeScript errors or lint issues found."
    echo "Fix all type errors and lint issues before marking this task complete."
    echo "Run: bash scripts/quality-gate.sh"
    exit 2
  fi
fi

# Check that PROGRESS.md was updated (has today's date or recent changes)
if [[ -f "PROGRESS.md" ]]; then
  LAST_MODIFIED=$(stat -c %Y PROGRESS.md 2>/dev/null || stat -f %m PROGRESS.md 2>/dev/null || echo "0")
  NOW=$(date +%s)
  AGE=$(( NOW - LAST_MODIFIED ))

  if [[ "$AGE" -gt 3600 ]]; then
    echo "PROGRESS.md hasn't been updated in over an hour."
    echo "Please update PROGRESS.md with what you changed and what's next."
    exit 2
  fi
fi

# All checks passed
exit 0
