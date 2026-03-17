#!/usr/bin/env bash
set -euo pipefail

# Pre-commit blast-radius warning hook — PreToolUse (Bash matching git commit)
# Runs blast-radius.sh on staged changes and warns if the blast radius is high.
# Does NOT block commits — only prints a warning to stderr.
# Exit 0 = allow (always), output goes to stderr as advisory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BR_SCRIPT="$SCRIPT_DIR/scripts/blast-radius.sh"

# Only run if blast-radius.sh exists
if [[ ! -f "$BR_SCRIPT" ]]; then
  exit 0
fi

# Only trigger on git commit commands
COMMAND="${CLAUDE_BASH_COMMAND:-}"
if [[ -z "$COMMAND" ]] || ! echo "$COMMAND" | grep -q "git commit"; then
  exit 0
fi

# Run blast-radius in quiet JSON mode against staged changes
# Use HEAD~1 as base since we're about to commit
BR_OUTPUT=$(bash "$BR_SCRIPT" --base HEAD --json 2>/dev/null || true)

if [[ -z "$BR_OUTPUT" ]]; then
  exit 0
fi

# Extract affected file count from JSON
AFFECTED=$(echo "$BR_OUTPUT" | grep -o '"affected_file_count": [0-9]*' | grep -o '[0-9]*' || echo "0")

if [[ "$AFFECTED" -gt 20 ]]; then
  echo "" >&2
  echo "⚠️  HIGH BLAST RADIUS: $AFFECTED files transitively affected by this commit" >&2
  echo "   Consider splitting into smaller commits or running /review first" >&2
  echo "   Run: bash scripts/blast-radius.sh  for details" >&2
  echo "" >&2
elif [[ "$AFFECTED" -gt 10 ]]; then
  echo "" >&2
  echo "📊 MODERATE BLAST RADIUS: $AFFECTED files transitively affected" >&2
  echo "   Run: bash scripts/blast-radius.sh  for details" >&2
  echo "" >&2
fi

# Never block — advisory only
exit 0
