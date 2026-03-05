#!/bin/bash
# stop-all.sh — Gracefully stop all running Hartz Land agents
#
# Usage:
#   bash scripts/hartz-land/stop-all.sh [options]
#
# Options:
#   --force    Kill immediately instead of graceful shutdown
#   --project  Only stop a specific project
#   --help     Show this help

set -euo pipefail

FORCE=false
SPECIFIC_PROJECT=""
TMUX_PREFIX="hartz"
PID_DIR="$HOME/.hartz-claude-framework/pids"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)    FORCE=true ;;
    --project)  SPECIFIC_PROJECT="$2"; shift ;;
    --help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }

echo ""
echo -e "${BOLD}Stopping Hartz Land agents...${NC}"
echo ""

STOPPED=0

# ─── Stop tmux sessions (if tmux available) ──────────────────────────────────

if command -v tmux &>/dev/null; then
  SESSIONS=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${TMUX_PREFIX}-" || true)

  for session in $SESSIONS; do
    PROJECT_NAME="${session#${TMUX_PREFIX}-}"

    if [[ -n "$SPECIFIC_PROJECT" ]] && [[ "$PROJECT_NAME" != "$SPECIFIC_PROJECT" ]]; then
      continue
    fi

    if [[ "$FORCE" == "true" ]]; then
      tmux kill-session -t "$session" 2>/dev/null || true
      ok "$PROJECT_NAME force-killed (tmux: $session)"
    else
      tmux send-keys -t "$session" C-c 2>/dev/null || true

      GRACEFUL=false
      for i in $(seq 1 15); do
        if ! tmux has-session -t "$session" 2>/dev/null; then
          GRACEFUL=true
          break
        fi
        sleep 1
      done

      if [[ "$GRACEFUL" == "true" ]]; then
        ok "$PROJECT_NAME stopped gracefully (tmux: $session)"
      else
        tmux kill-session -t "$session" 2>/dev/null || true
        warn "$PROJECT_NAME: graceful shutdown timed out — force-killed"
      fi
    fi

    STOPPED=$((STOPPED + 1))
  done
fi

# ─── Stop PID-tracked processes ──────────────────────────────────────────────

if [[ -d "$PID_DIR" ]]; then
  for pid_file in "$PID_DIR"/*.pid; do
    [[ ! -f "$pid_file" ]] && continue

    PROJECT_NAME=$(basename "$pid_file" .pid)

    if [[ -n "$SPECIFIC_PROJECT" ]] && [[ "$PROJECT_NAME" != "$SPECIFIC_PROJECT" ]]; then
      continue
    fi

    PID=$(cat "$pid_file")

    if kill -0 "$PID" 2>/dev/null; then
      if [[ "$FORCE" == "true" ]]; then
        kill -9 "$PID" 2>/dev/null || true
        pkill -P "$PID" 2>/dev/null || true
        ok "$PROJECT_NAME force-killed (PID $PID)"
      else
        kill "$PID" 2>/dev/null || true
        for i in $(seq 1 10); do
          if ! kill -0 "$PID" 2>/dev/null; then break; fi
          sleep 1
        done
        if kill -0 "$PID" 2>/dev/null; then
          kill -9 "$PID" 2>/dev/null || true
          pkill -P "$PID" 2>/dev/null || true
          warn "$PROJECT_NAME: graceful shutdown timed out — force-killed (PID $PID)"
        else
          ok "$PROJECT_NAME stopped gracefully (PID $PID)"
        fi
      fi
      STOPPED=$((STOPPED + 1))
    else
      warn "$PROJECT_NAME: process $PID already exited"
    fi

    rm -f "$pid_file"
  done
fi

if [[ "$STOPPED" -eq 0 ]]; then
  warn "No running agents found."
fi

echo ""
echo "  Stopped: $STOPPED agents"
echo ""
