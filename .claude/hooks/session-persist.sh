#!/usr/bin/env bash
# session-persist.sh — Auto-persist session state for seamless continuity
# Runs on: SessionEnd
# Creates/updates .claude/handoff/session-summary.md with structured state
# so the next session can pick up where this one left off.
#
# This enhances the existing session-end.sh by also capturing:
# - Task list state
# - Tool call count estimate (from git activity)
# - Suggested next actions based on branch state

set -euo pipefail

PROJECT_DIR="$(pwd)"
HANDOFF_DIR="$PROJECT_DIR/.claude/handoff"
PERSIST_FILE="$HANDOFF_DIR/session-state.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$HANDOFF_DIR"

# Only run in git repos
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# ─── Gather session metrics ──────────────────────────────────────────────────

# Commits made this session (last 4 hours as a rough session window)
SESSION_COMMITS=$(git log --since="4 hours ago" --oneline --no-merges 2>/dev/null | wc -l | tr -d ' ')

# Uncommitted changes
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
UNSTAGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

# Files modified in session
SESSION_FILES=$(git log --since="4 hours ago" --name-only --pretty=format: --no-merges 2>/dev/null | sort -u | grep -v '^$' | head -30 || echo "")
SESSION_FILE_COUNT=$(echo "$SESSION_FILES" | grep -c . 2>/dev/null || echo "0")

# Branch state relative to remote
AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "0")
BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo "0")

# ─── Determine suggested next action ─────────────────────────────────────────

NEXT_ACTION="continue working"
if [[ "$STAGED" -gt 0 ]] || [[ "$UNSTAGED" -gt 0 ]]; then
  NEXT_ACTION="commit pending changes ($STAGED staged, $UNSTAGED unstaged)"
elif [[ "$AHEAD" -gt 0 ]]; then
  NEXT_ACTION="push $AHEAD commit(s) to origin/$BRANCH"
elif [[ "$BEHIND" -gt 0 ]]; then
  NEXT_ACTION="pull $BEHIND commit(s) from origin/$BRANCH"
fi

# ─── Write structured session state ──────────────────────────────────────────

cat > "$PERSIST_FILE" <<STATE
{
  "timestamp": "$TIMESTAMP",
  "branch": "$BRANCH",
  "session_commits": $SESSION_COMMITS,
  "files_modified": $SESSION_FILE_COUNT,
  "uncommitted": {
    "staged": $STAGED,
    "unstaged": $UNSTAGED,
    "untracked": $UNTRACKED
  },
  "remote": {
    "ahead": $AHEAD,
    "behind": $BEHIND
  },
  "suggested_next_action": "$NEXT_ACTION"
}
STATE

# ─── Update session-start.sh context ─────────────────────────────────────────
# Write a human-readable summary that session-start.sh can inject

READABLE_FILE="$HANDOFF_DIR/last-session.md"
cat > "$READABLE_FILE" <<READABLE
## Last Session Summary ($TIMESTAMP)

- **Branch:** $BRANCH
- **Commits made:** $SESSION_COMMITS
- **Files modified:** $SESSION_FILE_COUNT
- **Uncommitted work:** $STAGED staged, $UNSTAGED unstaged, $UNTRACKED untracked
- **Remote:** $AHEAD ahead, $BEHIND behind origin/$BRANCH
- **Suggested next:** $NEXT_ACTION

### Recent commits
$(git log --since="4 hours ago" --oneline --no-merges 2>/dev/null | head -10 || echo "  (none)")

### Modified files
$(echo "$SESSION_FILES" | head -15 || echo "  (none)")
READABLE

exit 0
