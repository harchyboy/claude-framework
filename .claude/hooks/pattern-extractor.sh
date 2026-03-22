#!/usr/bin/env bash
# pattern-extractor.sh — Continuous learning system
# Runs on: SessionEnd
# Extracts reusable patterns from the session into docs/lessons-learned.md
#
# Scans recent git commits and modified files for patterns that indicate
# discoveries worth remembering: workarounds, configuration fixes,
# non-obvious solutions, and debugging techniques.
#
# Enable: Set HCF_PATTERN_EXTRACTION=1 (off by default to avoid noise)

set -euo pipefail

[[ "${HCF_PATTERN_EXTRACTION:-0}" != "1" ]] && exit 0

PROJECT_DIR="$(pwd)"
LESSONS_FILE="$PROJECT_DIR/docs/lessons-learned.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# Only run in git repos
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# ─── Gather session signals ──────────────────────────────────────────────────

# Recent commits from this session (last 2 hours)
RECENT_COMMITS=$(git log --since="2 hours ago" --oneline --no-merges 2>/dev/null || echo "")

# Skip if no commits were made
[[ -z "$RECENT_COMMITS" ]] && exit 0

# Look for fix commits (these often contain learnings)
FIX_COMMITS=$(echo "$RECENT_COMMITS" | grep -iE "^[a-f0-9]+ (fix|hotfix|workaround|revert)" || true)

# Look for commits that mention specific technologies or patterns
PATTERN_COMMITS=$(echo "$RECENT_COMMITS" | grep -iE "(config|migration|deploy|auth|cache|timeout|retry|fallback)" || true)

# Count commits and files changed
COMMIT_COUNT=$(echo "$RECENT_COMMITS" | wc -l | tr -d ' ')
FILES_CHANGED=$(git diff --name-only HEAD~${COMMIT_COUNT}..HEAD 2>/dev/null | sort -u || echo "")

# ─── Extract patterns ────────────────────────────────────────────────────────

PATTERNS=""

# Pattern: Multiple fix commits in same area = non-obvious problem
if [[ -n "$FIX_COMMITS" ]]; then
  FIX_COUNT=$(echo "$FIX_COMMITS" | wc -l | tr -d ' ')
  if [[ "$FIX_COUNT" -ge 2 ]]; then
    PATTERNS="${PATTERNS}\n### Multi-fix pattern detected ($TIMESTAMP)\n"
    PATTERNS="${PATTERNS}Branch: $BRANCH\n"
    PATTERNS="${PATTERNS}$FIX_COUNT fix commits suggest a non-obvious problem area:\n"
    PATTERNS="${PATTERNS}\`\`\`\n${FIX_COMMITS}\n\`\`\`\n"
    PATTERNS="${PATTERNS}Files involved:\n"
    while IFS= read -r f; do
      PATTERNS="${PATTERNS}- $f\n"
    done <<< "$(echo "$FILES_CHANGED" | head -10)"
    PATTERNS="${PATTERNS}\n"
  fi
fi

# Pattern: Config file changes (often contain environment-specific learnings)
CONFIG_CHANGES=$(echo "$FILES_CHANGED" | grep -iE '\.(env|config|toml|yaml|yml|ini)' || true)
if [[ -n "$CONFIG_CHANGES" ]]; then
  PATTERNS="${PATTERNS}\n### Configuration changes ($TIMESTAMP)\n"
  PATTERNS="${PATTERNS}Branch: $BRANCH\n"
  PATTERNS="${PATTERNS}Config files modified (review for environment-specific learnings):\n"
  while IFS= read -r f; do
    PATTERNS="${PATTERNS}- $f\n"
  done <<< "$CONFIG_CHANGES"
  PATTERNS="${PATTERNS}\n"
fi

# ─── Append to lessons file ──────────────────────────────────────────────────

if [[ -n "$PATTERNS" ]]; then
  mkdir -p "$(dirname "$LESSONS_FILE")"

  # Create file with header if it doesn't exist
  if [[ ! -f "$LESSONS_FILE" ]]; then
    cat > "$LESSONS_FILE" <<'HEADER'
# Lessons Learned

Auto-extracted patterns and manually recorded learnings.
Review periodically and promote important entries to proper documentation.

---

HEADER
  fi

  echo -e "$PATTERNS" >> "$LESSONS_FILE"
fi

exit 0
