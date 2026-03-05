#!/bin/bash
# monitor.sh — Monitor running Hartz Land agents
#
# Usage:
#   bash scripts/hartz-land/monitor.sh [options]
#
# Options:
#   --watch           Continuous monitoring (refresh every 30s)
#   --interval <sec>  Refresh interval for --watch mode (default: 30)
#   --json            Output in JSON format
#   --help            Show this help

set -euo pipefail

WATCH=false
INTERVAL=30
JSON_OUTPUT=false
TMUX_PREFIX="hartz"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)     WATCH=true ;;
    --interval)  INTERVAL="$2"; shift ;;
    --json)      JSON_OUTPUT=true ;;
    --help)
      sed -n '2,11p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# ─── Colours ──────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Platform detection ──────────────────────────────────────────────────────

USE_TMUX=false
if command -v tmux &>/dev/null; then
  USE_TMUX=true
fi

# ─── Directories ─────────────────────────────────────────────────────────────

HARTZ_DIR="$HOME/.hartz-claude-framework"
LOG_DIR="$HARTZ_DIR/logs"
PID_DIR="$HARTZ_DIR/pids"
REVIEW_DIR="$HARTZ_DIR/review-queue"
REGISTRY="$HARTZ_DIR/projects.txt"

# ─── Helper: check if project is running ─────────────────────────────────────

is_project_running() {
  local project_name="$1"

  # Check tmux
  if [[ "$USE_TMUX" == "true" ]]; then
    local session_name="${TMUX_PREFIX}-${project_name}"
    if tmux has-session -t "$session_name" 2>/dev/null; then
      echo "tmux:$session_name"
      return 0
    fi
  fi

  # Check PID
  local pid_file="$PID_DIR/${project_name}.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "pid:$pid"
      return 0
    else
      rm -f "$pid_file"
    fi
  fi

  return 1
}

display_status() {
  if [[ "$JSON_OUTPUT" != "true" ]]; then
    clear 2>/dev/null || true
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   HARTZ LAND — Agent Monitor                               ║${NC}"
    echo -e "${BOLD}║   $(date '+%Y-%m-%d %H:%M:%S')                                         ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
  fi

  RUNNING_COUNT=0
  COMPLETED_COUNT=0
  TOTAL_STORIES=0
  TOTAL_DONE=0

  JSON_PROJECTS="["

  if [[ -f "$REGISTRY" ]]; then
    while IFS= read -r project_path; do
      [[ -z "$project_path" ]] && continue
      [[ "$project_path" == \#* ]] && continue
      [[ ! -d "$project_path" ]] && continue

      PROJECT_NAME=$(basename "$project_path")

      # Status
      STATUS="idle"
      RUN_INFO=""
      if RUN_INFO=$(is_project_running "$PROJECT_NAME"); then
        STATUS="running"
        RUNNING_COUNT=$((RUNNING_COUNT + 1))
      else
        # Check if there's a recent log (completed within last hour)
        LATEST_LOG=$(ls -t "$LOG_DIR/${PROJECT_NAME}"_*.log 2>/dev/null | head -1 || echo "")
        if [[ -n "$LATEST_LOG" ]]; then
          LOG_AGE=$(node -e "
            const fs = require('fs');
            const stat = fs.statSync('$LATEST_LOG');
            console.log(Math.floor((Date.now() - stat.mtimeMs) / 1000));
          " 2>/dev/null || echo "999999")
          if [[ "$LOG_AGE" -lt 3600 ]]; then
            STATUS="completed"
            COMPLETED_COUNT=$((COMPLETED_COUNT + 1))
          fi
        fi
      fi

      # PRD progress
      STORIES_TOTAL=0
      STORIES_DONE=0
      PRD_NAME=""
      for prd_dir in "$project_path"/scripts/ralph-moss/prds/*/; do
        if [[ -f "$prd_dir/prd.json" ]]; then
          PRD_NAME=$(basename "$prd_dir")
          COUNTS=$(node -e "
            const prd = JSON.parse(require('fs').readFileSync('$prd_dir/prd.json', 'utf8'));
            console.log(prd.userStories.length + ':' + prd.userStories.filter(s => s.passes).length);
          " 2>/dev/null || echo "0:0")
          STORIES_TOTAL=$(echo "$COUNTS" | cut -d: -f1)
          STORIES_DONE=$(echo "$COUNTS" | cut -d: -f2)
          TOTAL_STORIES=$((TOTAL_STORIES + STORIES_TOTAL))
          TOTAL_DONE=$((TOTAL_DONE + STORIES_DONE))
          break
        fi
      done

      # Latest log
      LATEST_LOG=$(ls -t "$LOG_DIR/${PROJECT_NAME}"_*.log 2>/dev/null | head -1 || echo "")
      LAST_ACTIVITY=""
      LAST_LOG_LINE=""
      if [[ -n "$LATEST_LOG" ]]; then
        LAST_ACTIVITY=$(date -r "$LATEST_LOG" '+%H:%M:%S' 2>/dev/null || echo "")
        LAST_LOG_LINE=$(grep -v '^$' "$LATEST_LOG" 2>/dev/null | tail -1 | head -c 80 || echo "")
      fi

      # Review queue
      REVIEW_COUNT=$(ls "$REVIEW_DIR/${PROJECT_NAME}"_*.json 2>/dev/null | wc -l | tr -d ' ' || echo "0")

      if [[ "$JSON_OUTPUT" == "true" ]]; then
        [[ "$JSON_PROJECTS" != "[" ]] && JSON_PROJECTS="$JSON_PROJECTS,"
        JSON_PROJECTS="$JSON_PROJECTS{\"name\":\"$PROJECT_NAME\",\"status\":\"$STATUS\",\"run_info\":\"$RUN_INFO\",\"prd\":\"$PRD_NAME\",\"stories_total\":$STORIES_TOTAL,\"stories_done\":$STORIES_DONE,\"reviews_pending\":$REVIEW_COUNT}"
      else
        # Status icon
        case "$STATUS" in
          running)   STATUS_ICON="${GREEN}●${NC}" ;;
          completed) STATUS_ICON="${CYAN}◉${NC}" ;;
          idle)      STATUS_ICON="${DIM}○${NC}" ;;
        esac

        # Progress bar
        if [[ "$STORIES_TOTAL" -gt 0 ]]; then
          PCT=$((STORIES_DONE * 100 / STORIES_TOTAL))
          BAR_LEN=20
          FILLED=$((PCT * BAR_LEN / 100))
          EMPTY=$((BAR_LEN - FILLED))
          BAR="${GREEN}"
          for ((i=0; i<FILLED; i++)); do BAR+="█"; done
          BAR+="${DIM}"
          for ((i=0; i<EMPTY; i++)); do BAR+="░"; done
          BAR+="${NC}"
          PROGRESS="$BAR ${STORIES_DONE}/${STORIES_TOTAL}"
        else
          PROGRESS="${DIM}no PRD${NC}"
        fi

        echo -e "  $STATUS_ICON ${BOLD}$PROJECT_NAME${NC}"
        if [[ "$STATUS" == "running" ]]; then
          if [[ "$RUN_INFO" == tmux:* ]]; then
            local session="${RUN_INFO#tmux:}"
            echo -e "    Session:  $session  ${DIM}(tmux attach -t $session)${NC}"
          else
            local pid="${RUN_INFO#pid:}"
            echo -e "    Process:  PID $pid  ${DIM}(tail -f $LATEST_LOG)${NC}"
          fi
        else
          echo -e "    Status:   $STATUS"
        fi
        echo -e "    Progress: $PROGRESS"
        [[ -n "$PRD_NAME" ]] && echo -e "    PRD:      $PRD_NAME"
        [[ "$REVIEW_COUNT" -gt 0 ]] && echo -e "    Reviews:  ${YELLOW}$REVIEW_COUNT awaiting review${NC}"
        [[ -n "$LAST_ACTIVITY" ]] && echo -e "    Last log: $LAST_ACTIVITY"
        [[ -n "$LAST_LOG_LINE" ]] && echo -e "    ${DIM}> $LAST_LOG_LINE${NC}"
        echo ""
      fi
    done < "$REGISTRY"
  fi

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    JSON_PROJECTS="$JSON_PROJECTS]"
    echo "{\"timestamp\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",\"running\":$RUNNING_COUNT,\"completed\":$COMPLETED_COUNT,\"total_stories\":$TOTAL_STORIES,\"total_done\":$TOTAL_DONE,\"projects\":$JSON_PROJECTS}"
  else
    echo -e "  ${BOLD}─────────────────────────────────────────${NC}"
    echo -e "  Running: ${GREEN}$RUNNING_COUNT${NC}  Completed: ${CYAN}$COMPLETED_COUNT${NC}  Stories: $TOTAL_DONE/$TOTAL_STORIES"

    TOTAL_REVIEWS=$(ls "$REVIEW_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [[ "$TOTAL_REVIEWS" -gt 0 ]]; then
      echo -e "  ${YELLOW}Review queue: $TOTAL_REVIEWS items awaiting human review${NC}"
    fi
    echo ""

    echo -e "  ${DIM}Commands:${NC}"
    echo -e "  ${DIM}  bash scripts/hartz-land/stop-all.sh     — Stop all agents${NC}"
    if [[ "$USE_TMUX" == "true" ]]; then
      echo -e "  ${DIM}  tmux attach -t ${TMUX_PREFIX}-<project>  — Watch agent work${NC}"
    else
      echo -e "  ${DIM}  tail -f $LOG_DIR/<project>_*.log        — Watch agent output${NC}"
    fi
    echo ""
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if [[ "$WATCH" == "true" ]]; then
  while true; do
    display_status
    sleep "$INTERVAL"
  done
else
  display_status
fi
