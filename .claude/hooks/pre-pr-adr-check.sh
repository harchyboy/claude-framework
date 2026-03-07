#!/usr/bin/env bash
set -euo pipefail

# Pre-PR ADR check — blocks multi-module PRs that lack an ADR reference.
# A PR touching files across 3+ top-level directories requires an ADR.
# Exit 2 = block, Exit 0 = allow.

ADR_DIR="docs/adr"
DIR_THRESHOLD=3

# Get changed files compared to main/master
BASE_BRANCH="main"
if ! git rev-parse --verify "$BASE_BRANCH" &>/dev/null; then
  BASE_BRANCH="master"
fi

if ! git rev-parse --verify "$BASE_BRANCH" &>/dev/null; then
  # Cannot determine base branch — allow through
  exit 0
fi

CHANGED_FILES=$(git diff --name-only "$BASE_BRANCH"...HEAD 2>/dev/null || true)

if [[ -z "$CHANGED_FILES" ]]; then
  exit 0
fi

# Count distinct top-level directories touched
DIR_COUNT=$(echo "$CHANGED_FILES" | cut -d'/' -f1 | sort -u | wc -l | tr -d ' ')

if (( DIR_COUNT < DIR_THRESHOLD )); then
  exit 0
fi

# Multi-module change detected — check for ADR reference
# Look for ADR in: PR branch name, recent commit messages, or new ADR files
HAS_ADR=false

# Check if any ADR files were added/modified in this branch
ADR_FILES=$(echo "$CHANGED_FILES" | grep -i "^docs/adr/" || true)
if [[ -n "$ADR_FILES" ]]; then
  HAS_ADR=true
fi

# Check recent commit messages for ADR references
ADR_IN_COMMITS=$(git log "$BASE_BRANCH"..HEAD --oneline 2>/dev/null | grep -iE "ADR-[0-9]+" || true)
if [[ -n "$ADR_IN_COMMITS" ]]; then
  HAS_ADR=true
fi

if [[ "$HAS_ADR" == "true" ]]; then
  exit 0
else
  echo "PR BLOCKED: Multi-module change requires an Architecture Decision Record."
  echo ""
  echo "This PR touches $DIR_COUNT top-level directories (threshold: $DIR_THRESHOLD)."
  echo "Directories affected:"
  echo "$CHANGED_FILES" | cut -d'/' -f1 | sort -u | sed 's/^/  - /'
  echo ""
  echo "To unblock:"
  echo "  1. Create an ADR in $ADR_DIR/ using docs/templates/adr-template.md"
  echo "  2. Or reference an existing ADR in a commit message (e.g., 'ref ADR-001')"
  echo ""
  echo "Use the architect agent: claude --agent architect"
  exit 2
fi
