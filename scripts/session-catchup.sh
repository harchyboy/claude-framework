#!/bin/bash
# session-catchup.sh — Recover context from previous Claude Code sessions
#
# Parses Claude Code's internal .jsonl session files to find what happened
# after the last PROGRESS.md write. Useful after /clear or context compaction.
#
# Usage:
#   bash scripts/session-catchup.sh              Show last session's unsynced context
#   bash scripts/session-catchup.sh --full        Show full last session summary
#   bash scripts/session-catchup.sh --sessions N  Show last N sessions
#
# Based on the session recovery pattern from planning-with-files.

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────

PROJECT_DIR="$(pwd)"
SESSIONS_TO_SHOW="${SESSIONS_TO_SHOW:-1}"
FULL_MODE=false

# ─── Colours ─────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  $1${NC}"; }
info() { echo -e "${CYAN}  $1${NC}"; }
warn() { echo -e "${YELLOW}  $1${NC}"; }
h1()   { echo -e "\n${BOLD}$1${NC}"; }

# ─── Parse args ──────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL_MODE=true; shift ;;
    --sessions) SESSIONS_TO_SHOW="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ─── Find Claude Code sessions directory ─────────────────────────────────────

# Claude Code stores sessions at ~/.claude/projects/<sanitized-path>/
# The path is sanitized: / becomes - on Unix, \ becomes - on Windows
SANITIZED_PATH=""

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "${WINDIR:-}" ]]; then
  # Windows: convert C:\Users\craig\project to C--Users-craig-project
  SANITIZED_PATH=$(echo "$PROJECT_DIR" | sed 's|\\|-|g' | sed 's|/|-|g' | sed 's|:||g')
else
  # Unix: convert /home/craig/project to -home-craig-project
  SANITIZED_PATH=$(echo "$PROJECT_DIR" | sed 's|/|-|g')
fi

# Remove leading dash
SANITIZED_PATH="${SANITIZED_PATH#-}"

CLAUDE_SESSIONS_DIR="$HOME/.claude/projects/$SANITIZED_PATH"

if [[ ! -d "$CLAUDE_SESSIONS_DIR" ]]; then
  warn "No Claude Code session directory found at: $CLAUDE_SESSIONS_DIR"
  warn "This script reads Claude Code's internal session files."
  exit 0
fi

# ─── Find most recent session files ──────────────────────────────────────────

h1 "Session Catchup — Recovering context from previous sessions"
echo ""

# Find .jsonl files, sorted by modification time (newest first)
SESSION_FILES=$(find "$CLAUDE_SESSIONS_DIR" -name "*.jsonl" -type f 2>/dev/null | \
  while IFS= read -r f; do
    echo "$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0) $f"
  done | sort -rn | head -"$SESSIONS_TO_SHOW" | awk '{print $2}')

if [[ -z "$SESSION_FILES" ]]; then
  warn "No session files found in $CLAUDE_SESSIONS_DIR"
  exit 0
fi

# ─── Process each session ────────────────────────────────────────────────────

while IFS= read -r session_file; do
  SESSION_NAME=$(basename "$session_file" .jsonl)
  SESSION_DATE=$(stat -c %Y "$session_file" 2>/dev/null || stat -f %m "$session_file" 2>/dev/null || echo 0)
  SESSION_DATE_HUMAN=$(date -d "@$SESSION_DATE" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$SESSION_DATE" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")

  h1 "Session: $SESSION_NAME ($SESSION_DATE_HUMAN)"

  # Count total messages
  TOTAL_LINES=$(wc -l < "$session_file")
  info "Total entries: $TOTAL_LINES"

  # Find the last PROGRESS.md write (the sync point)
  LAST_PROGRESS_LINE=$(grep -n "PROGRESS.md" "$session_file" 2>/dev/null | \
    grep -iE "(Write|Edit)" | tail -1 | cut -d: -f1 || echo "0")

  if [[ "$LAST_PROGRESS_LINE" == "0" ]] || [[ -z "$LAST_PROGRESS_LINE" ]]; then
    warn "No PROGRESS.md write found in this session"
    warn "All context from this session may be unsynced"
    LAST_PROGRESS_LINE=1
  else
    ok "Last PROGRESS.md update at line $LAST_PROGRESS_LINE of $TOTAL_LINES"
  fi

  # Count unsynced entries
  UNSYNCED=$(( TOTAL_LINES - LAST_PROGRESS_LINE ))
  if [[ "$UNSYNCED" -gt 0 ]]; then
    warn "$UNSYNCED entries after last PROGRESS.md sync"
  fi

  echo ""

  # Extract key actions after the sync point
  info "Key actions after last sync:"
  echo ""

  # Look for tool calls (file writes, edits, bash commands)
  tail -n +"$LAST_PROGRESS_LINE" "$session_file" 2>/dev/null | \
    grep -oE '"tool_name"\s*:\s*"(Write|Edit|Bash)"' 2>/dev/null | \
    sort | uniq -c | sort -rn | while IFS= read -r line; do
      echo "    $line"
    done || true

  # Look for file paths that were modified
  info "Files modified after last sync:"
  tail -n +"$LAST_PROGRESS_LINE" "$session_file" 2>/dev/null | \
    grep -oE '"file_path"\s*:\s*"[^"]*"' 2>/dev/null | \
    sed 's/"file_path"\s*:\s*"//;s/"$//' | \
    sort -u | while IFS= read -r fp; do
      echo "    - $fp"
    done || true

  # Look for user messages (the actual requests)
  if [[ "$FULL_MODE" == "true" ]]; then
    echo ""
    info "User messages in session:"
    grep -o '"role"\s*:\s*"user"[^}]*"content"\s*:\s*"[^"]*"' "$session_file" 2>/dev/null | \
      sed 's/.*"content"\s*:\s*"//;s/"$//' | \
      head -20 | while IFS= read -r msg; do
        echo "    > $(echo "$msg" | head -c 200)"
      done || true
  fi

  echo ""
  echo "  ──────────────────────────────────────"

done <<< "$SESSION_FILES"

echo ""
h1 "Recommendations"
echo ""

# Check if PROGRESS.md exists and is stale
if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  PROGRESS_AGE=$(stat -c %Y "$PROJECT_DIR/PROGRESS.md" 2>/dev/null || stat -f %m "$PROJECT_DIR/PROGRESS.md" 2>/dev/null || echo 0)
  PROGRESS_AGE_HOURS=$(( ($(date +%s) - PROGRESS_AGE) / 3600 ))
  if [[ "$PROGRESS_AGE_HOURS" -gt 24 ]]; then
    warn "PROGRESS.md last updated $PROGRESS_AGE_HOURS hours ago — may be stale"
    echo "  Run: Read PROGRESS.md and update it with current state"
  else
    ok "PROGRESS.md is recent ($PROGRESS_AGE_HOURS hours old)"
  fi
else
  warn "No PROGRESS.md found — create one to enable session recovery"
fi

echo ""
