#!/usr/bin/env bash
set -euo pipefail

# Pre-commit validation hook — PreToolUse (Bash matching git commit)
# Validates commit messages follow conventional commit format with ticket ID.
# Exit 2 = block, Exit 0 = allow.

# Extract commit message from the command arguments
# The hook receives the full bash command; we extract the -m argument
COMMIT_MSG="${CLAUDE_BASH_COMMAND:-}"

# Try to extract the message from -m "..." or -m '...'
if [[ -z "$COMMIT_MSG" ]]; then
  exit 0  # No command to validate
fi

# Extract message content after -m flag
MSG=$(echo "$COMMIT_MSG" | grep -oP '(?<=-m\s["\x27])[^"\x27]+' | head -1 || true)

# Also try heredoc format (cat <<'EOF' ... EOF)
if [[ -z "$MSG" ]]; then
  MSG=$(echo "$COMMIT_MSG" | grep -oP '(?<=EOF\n).*(?=\n.*EOF)' | head -1 || true)
fi

if [[ -z "$MSG" ]]; then
  # Cannot parse — allow through (avoid false blocks)
  exit 0
fi

# First line of the message
FIRST_LINE=$(echo "$MSG" | head -1)

# Pattern: type(optional-scope): description [TICKET-ID]
# Types: feat, fix, test, refactor, docs, chore, style, perf, ci, build
PATTERN='^(feat|fix|test|refactor|docs|chore|style|perf|ci|build)(\([a-zA-Z0-9_-]+\))?: .+ \[[A-Z]+-[0-9]+\]$'

if [[ "$FIRST_LINE" =~ $PATTERN ]]; then
  exit 0
else
  echo "COMMIT BLOCKED: Invalid commit message format."
  echo ""
  echo "Expected: type(scope): description [TICKET-ID]"
  echo "  Types: feat, fix, test, refactor, docs, chore, style, perf, ci, build"
  echo "  Scope: optional, e.g., (auth), (api)"
  echo "  Ticket: required, e.g., [KPF-042], [UNION-108]"
  echo ""
  echo "Examples:"
  echo "  feat(auth): add OAuth2 login flow [KPF-042]"
  echo "  fix: resolve null pointer in user lookup [UNION-108]"
  echo ""
  echo "Got: $FIRST_LINE"
  exit 2
fi
