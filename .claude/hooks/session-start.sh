#!/bin/bash
# session-start.sh — Inject project context at session start
# Runs on: SessionStart (startup, resume, clear, compact)
# Outputs project state into Claude's attention window so every session
# starts with awareness of current progress, failed approaches, and active locks.

PROJECT_DIR="$(pwd)"

# ─── Sync check (warn if behind remote) ──────────────────────────────────────

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Quick fetch (timeout after 5 seconds to not block startup)
  timeout 5 git fetch origin 2>/dev/null || true

  LOCAL=$(git rev-parse HEAD 2>/dev/null)
  BRANCH=$(git branch --show-current 2>/dev/null)
  REMOTE=$(git rev-parse "origin/$BRANCH" 2>/dev/null || echo "")

  if [[ -n "$REMOTE" ]] && [[ "$LOCAL" != "$REMOTE" ]]; then
    BEHIND=$(git rev-list --count HEAD..origin/$BRANCH 2>/dev/null || echo "0")
    AHEAD=$(git rev-list --count origin/$BRANCH..HEAD 2>/dev/null || echo "0")

    if [[ "$BEHIND" -gt 0 ]]; then
      echo "<framework-context source=\"sync-warning\">"
      echo "## SYNC WARNING: This repo is $BEHIND commit(s) behind origin/$BRANCH"
      echo "Run \`git pull\` before starting work to avoid conflicts."
      if [[ "$AHEAD" -gt 0 ]]; then
        echo "Also $AHEAD commit(s) ahead — pull with rebase: \`git pull --rebase\`"
      fi
      echo "</framework-context>"
      echo ""
    fi
  fi

  # Check framework submodule freshness
  if [[ -d "$PROJECT_DIR/.claude-framework" ]]; then
    SUBMOD_COMMIT=$(cd "$PROJECT_DIR/.claude-framework" && git rev-parse --short HEAD 2>/dev/null || echo "")
    SUBMOD_REMOTE=$(cd "$PROJECT_DIR/.claude-framework" && git fetch origin 2>/dev/null && git rev-parse --short origin/master 2>/dev/null || echo "")
    if [[ -n "$SUBMOD_COMMIT" ]] && [[ -n "$SUBMOD_REMOTE" ]] && [[ "$SUBMOD_COMMIT" != "$SUBMOD_REMOTE" ]]; then
      echo "<framework-context source=\"framework-update\">"
      echo "## FRAMEWORK UPDATE AVAILABLE"
      echo "Framework submodule is at $SUBMOD_COMMIT, latest is $SUBMOD_REMOTE."
      echo "Update with: \`git submodule update --remote .claude-framework && bash install.sh\`"
      echo "</framework-context>"
      echo ""
    fi
  fi
fi

# ─── Last session continuity ──────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/.claude/handoff/last-session.md" ]]; then
  echo "<framework-context source=\"last-session\">"
  cat "$PROJECT_DIR/.claude/handoff/last-session.md"
  echo "</framework-context>"
  echo ""
fi

# ─── Current project state ────────────────────────────────────────────────────

if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  echo "<framework-context source=\"PROGRESS.md\">"
  echo "## Current Project State"
  head -50 "$PROJECT_DIR/PROGRESS.md"
  echo "</framework-context>"
  echo ""
fi

# ─── Failed approaches (prevent retrying known failures) ──────────────────────

if [[ -f "$PROJECT_DIR/docs/failed-approaches.md" ]]; then
  FAILED_COUNT=$(grep -c "^## " "$PROJECT_DIR/docs/failed-approaches.md" 2>/dev/null || echo "0")
  if [[ "$FAILED_COUNT" -gt 0 ]]; then
    echo "<framework-context source=\"failed-approaches\">"
    echo "## Known Failed Approaches ($FAILED_COUNT entries)"
    echo "DO NOT retry these approaches. Check docs/failed-approaches.md for details."
    # Show just the headings so the agent knows what to avoid
    grep "^## " "$PROJECT_DIR/docs/failed-approaches.md" 2>/dev/null | head -20
    echo "</framework-context>"
    echo ""
  fi
fi

# ─── Active task locks (prevent conflicts) ────────────────────────────────────

if [[ -d "$PROJECT_DIR/current_tasks" ]]; then
  LOCK_FILES=$(find "$PROJECT_DIR/current_tasks" -name "*.txt" -type f 2>/dev/null)
  if [[ -n "$LOCK_FILES" ]]; then
    echo "<framework-context source=\"task-locks\">"
    echo "## Active Task Locks (DO NOT claim these)"
    while IFS= read -r lock; do
      echo "- $(basename "$lock" .txt): $(cat "$lock")"
    done <<< "$LOCK_FILES"
    echo "</framework-context>"
    echo ""
  fi
fi

# ─── Recent solutions (leverage past learnings) ──────────────────────────────

if [[ -d "$PROJECT_DIR/docs/solutions" ]]; then
  RECENT=$(find "$PROJECT_DIR/docs/solutions" -name "*.md" -type f -newer "$PROJECT_DIR/PROGRESS.md" 2>/dev/null | head -5)
  if [[ -n "$RECENT" ]]; then
    echo "<framework-context source=\"recent-solutions\">"
    echo "## Recent Solutions (since last PROGRESS.md update)"
    while IFS= read -r sol; do
      echo "- $(basename "$sol")"
    done <<< "$RECENT"
    echo "Read these before starting work on related areas."
    echo "</framework-context>"
  fi
fi
