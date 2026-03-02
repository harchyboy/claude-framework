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

# ─── Cross-platform helpers ──────────────────────────────────────────────────

# Get file modification time as Unix timestamp (cross-platform)
get_mtime() {
  stat -c %Y "$1" 2>/dev/null \
    || stat -f %m "$1" 2>/dev/null \
    || node -e "console.log(Math.floor(require('fs').statSync(process.argv[1]).mtimeMs/1000))" "$1" 2>/dev/null \
    || echo "0"
}

# Format timestamp to human-readable (cross-platform)
format_timestamp() {
  date -d "@$1" "+%Y-%m-%d %H:%M" 2>/dev/null \
    || date -r "$1" "+%Y-%m-%d %H:%M" 2>/dev/null \
    || node -e "const d=new Date($1*1000);console.log(d.toISOString().slice(0,16).replace('T',' '))" 2>/dev/null \
    || echo "unknown"
}

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
    echo "$(get_mtime "$f") $f"
  done | sort -rn | head -"$SESSIONS_TO_SHOW" | awk '{print $2}')

if [[ -z "$SESSION_FILES" ]]; then
  warn "No session files found in $CLAUDE_SESSIONS_DIR"
  exit 0
fi

# ─── Process each session (using node for reliable JSON parsing) ─────────────

while IFS= read -r session_file; do
  SESSION_NAME=$(basename "$session_file" .jsonl)
  SESSION_DATE=$(get_mtime "$session_file")
  SESSION_DATE_HUMAN=$(format_timestamp "$SESSION_DATE")

  h1 "Session: $SESSION_NAME ($SESSION_DATE_HUMAN)"

  # Use node for reliable JSONL parsing
  if command -v node > /dev/null 2>&1; then
    node -e "
      const fs = require('fs');
      const readline = require('readline');

      const file = process.argv[1];
      const fullMode = process.argv[2] === 'true';

      const lines = fs.readFileSync(file, 'utf8').split('\n').filter(l => l.trim());
      const totalEntries = lines.length;
      console.log('  Total entries: ' + totalEntries);

      // Parse each line as JSON, collect tool calls and user messages
      let lastProgressLine = 0;
      const toolCalls = [];
      const filePaths = new Set();
      const userMessages = [];

      for (let i = 0; i < lines.length; i++) {
        try {
          const entry = JSON.parse(lines[i]);

          // Track PROGRESS.md writes
          const str = JSON.stringify(entry);
          if (str.includes('PROGRESS.md') && (str.includes('Write') || str.includes('Edit'))) {
            lastProgressLine = i + 1;
          }

          // Collect tool uses
          if (entry.type === 'tool_use' || entry.tool_name) {
            const toolName = entry.tool_name || entry.name || '';
            if (['Write', 'Edit', 'Bash'].includes(toolName)) {
              toolCalls.push({ line: i + 1, tool: toolName });
            }
            const fp = entry.file_path || (entry.input && entry.input.file_path) || '';
            if (fp) filePaths.add(fp);
          }

          // Recursively search for tool_use in content arrays
          if (entry.content && Array.isArray(entry.content)) {
            for (const block of entry.content) {
              if (block.type === 'tool_use') {
                const tn = block.name || '';
                if (['Write', 'Edit', 'Bash'].includes(tn)) {
                  toolCalls.push({ line: i + 1, tool: tn });
                }
                if (block.input && block.input.file_path) {
                  filePaths.add(block.input.file_path);
                }
              }
            }
          }

          // Collect user messages
          if (entry.role === 'user' && entry.content) {
            const text = typeof entry.content === 'string'
              ? entry.content
              : Array.isArray(entry.content)
                ? entry.content.filter(b => b.type === 'text').map(b => b.text).join(' ')
                : '';
            if (text.trim()) userMessages.push({ line: i + 1, text: text.slice(0, 200) });
          }
        } catch (e) {
          // Skip unparseable lines
        }
      }

      // Report sync point
      if (lastProgressLine === 0) {
        console.log('  ⚠ No PROGRESS.md write found in this session');
        console.log('  ⚠ All context from this session may be unsynced');
        lastProgressLine = 1;
      } else {
        console.log('  ✓ Last PROGRESS.md update at line ' + lastProgressLine + ' of ' + totalEntries);
      }

      const unsynced = totalEntries - lastProgressLine;
      if (unsynced > 0) {
        console.log('  ⚠ ' + unsynced + ' entries after last PROGRESS.md sync');
      }

      // Tool call summary after sync point
      const afterSync = toolCalls.filter(t => t.line >= lastProgressLine);
      if (afterSync.length > 0) {
        console.log('');
        console.log('  Key actions after last sync:');
        const counts = {};
        afterSync.forEach(t => { counts[t.tool] = (counts[t.tool] || 0) + 1; });
        Object.entries(counts).sort((a, b) => b[1] - a[1]).forEach(([tool, count]) => {
          console.log('    ' + count + ' x ' + tool);
        });
      }

      // Files modified after sync
      const afterSyncPaths = new Set();
      for (let i = lastProgressLine - 1; i < lines.length; i++) {
        try {
          const entry = JSON.parse(lines[i]);
          const str = JSON.stringify(entry);
          const fpMatches = str.match(/\"file_path\"\s*:\s*\"([^\"]*)\"/g);
          if (fpMatches) {
            fpMatches.forEach(m => {
              const fp = m.replace(/.*\"file_path\"\s*:\s*\"/, '').replace(/\"$/, '');
              afterSyncPaths.add(fp);
            });
          }
        } catch (e) {}
      }

      if (afterSyncPaths.size > 0) {
        console.log('');
        console.log('  Files modified after last sync:');
        [...afterSyncPaths].sort().forEach(fp => console.log('    - ' + fp));
      }

      // User messages (full mode)
      if (fullMode && userMessages.length > 0) {
        console.log('');
        console.log('  User messages in session:');
        userMessages.slice(0, 20).forEach(m => {
          console.log('    > ' + m.text.replace(/\\n/g, ' ').slice(0, 200));
        });
      }

      console.log('');
      console.log('  ──────────────────────────────────────');
    " "$session_file" "$FULL_MODE"
  else
    # Fallback: basic grep-based parsing (less reliable but works without node)
    TOTAL_LINES=$(wc -l < "$session_file")
    info "Total entries: $TOTAL_LINES"

    LAST_PROGRESS_LINE=$(grep -n "PROGRESS.md" "$session_file" 2>/dev/null | \
      grep -iE "(Write|Edit)" | tail -1 | cut -d: -f1 || echo "0")

    if [[ "$LAST_PROGRESS_LINE" == "0" ]] || [[ -z "$LAST_PROGRESS_LINE" ]]; then
      warn "No PROGRESS.md write found in this session"
      LAST_PROGRESS_LINE=1
    else
      ok "Last PROGRESS.md update at line $LAST_PROGRESS_LINE of $TOTAL_LINES"
    fi

    UNSYNCED=$(( TOTAL_LINES - LAST_PROGRESS_LINE ))
    if [[ "$UNSYNCED" -gt 0 ]]; then
      warn "$UNSYNCED entries after last PROGRESS.md sync"
    fi

    echo ""
    info "Key actions after last sync:"
    tail -n +"$LAST_PROGRESS_LINE" "$session_file" 2>/dev/null | \
      grep -oE '"tool_name"\s*:\s*"(Write|Edit|Bash)"' 2>/dev/null | \
      sort | uniq -c | sort -rn | while IFS= read -r line; do
        echo "    $line"
      done || true

    info "Files modified after last sync:"
    tail -n +"$LAST_PROGRESS_LINE" "$session_file" 2>/dev/null | \
      grep -oE '"file_path"\s*:\s*"[^"]*"' 2>/dev/null | \
      sed 's/"file_path"\s*:\s*"//;s/"$//' | \
      sort -u | while IFS= read -r fp; do
        echo "    - $fp"
      done || true

    echo ""
    echo "  ──────────────────────────────────────"
  fi

done <<< "$SESSION_FILES"

echo ""
h1 "Recommendations"
echo ""

# Check if PROGRESS.md exists and is stale
if [[ -f "$PROJECT_DIR/PROGRESS.md" ]]; then
  PROGRESS_AGE=$(get_mtime "$PROJECT_DIR/PROGRESS.md")
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
