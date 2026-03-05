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
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
err()  { echo -e "${RED}  ❌ $1${NC}"; }

PID_DIR="$HOME/.hartz-claude-framework/pids"

echo ""
echo -e "${BOLD}Stopping Hartz Land agents...${NC}"
echo ""

STOPPED=0

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
      # Also kill child processes
      pkill -P "$PID" 2>/dev/null || true
      ok "$PROJECT_NAME force-killed (PID $PID)"
    else
      kill "$PID" 2>/dev/null || true
      # Wait up to 10 seconds for graceful shutdown
      for i in $(seq 1 10); do
        if ! kill -0 "$PID" 2>/dev/null; then
          break
        fi
        sleep 1
      done
      if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID" 2>/dev/null || true
        warn "$PROJECT_NAME: graceful shutdown timed out — force-killed"
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

echo ""
echo "  Stopped: $STOPPED agents"
echo ""
