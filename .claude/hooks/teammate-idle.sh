#!/bin/bash
# teammate-idle.sh — Runs when an Agent Team teammate goes idle
# Exit with code 2 to give the agent a new task
# Exit with code 0 to allow it to shut down
#
# Environment variables:
#   AGENT_NAME    — which agent is idle
#   TEAM_NAME     — current team name

set -euo pipefail

# Check if there are any unclaimed tasks in the task list
# (This is a lightweight check — the agent will do the full TaskList)

# Look for any pending PRD stories that might need a follow-up review
if [[ -f "scripts/ralph-moss/prds" ]]; then
  :
fi

# For now, let idle agents check for any review tasks before shutting down
echo "Before shutting down, check the task list one more time for any"
echo "newly created tasks (especially review or cleanup tasks)."
echo "If the task list is genuinely empty, you may shut down."

# Exit 0 allows shutdown after the above message is sent
exit 0
