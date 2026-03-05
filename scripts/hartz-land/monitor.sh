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

# ─── Directories ─────────────────────────────────────────────────────────────

HARTZ_DIR="$HOME/.hartz-claude-framework"
LOG_DIR="$HARTZ_DIR/logs"
PID_DIR="$HARTZ_DIR/pids"
REVIEW_DIR="$HARTZ_DIR/review-queue"
REGISTRY="$HARTZ_DIR/projects.txt"

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

  # JSON collector
  JSON_PROJECTS="["

  if [[ -f "$REGISTRY" ]]; then
    while IFS= read -r project_path; do
      [[ -z "$project_path" ]] && continue
      [[ "$project_path" == \#* ]] && continue
      [[ ! -d "$project_path" ]] && continue

      PROJECT_NAME=$(basename "$project_path")
      PID_FILE="$PID_DIR/${PROJECT_NAME}.pid"

      # Status
      STATUS="idle"
      PID=""
      if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
          STATUS="running"
          RUNNING_COUNT=$((RUNNING_COUNT + 1))
        else
          STATUS="completed"
          COMPLETED_COUNT=$((COMPLETED_COUNT + 1))
          rm -f "$PID_FILE"
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

      # Latest log file
      LATEST_LOG=$(ls -t "$LOG_DIR/${PROJECT_NAME}"_*.log 2>/dev/null | head -1 || echo "")
      LAST_ACTIVITY=""
      if [[ -n "$LATEST_LOG" ]]; then
        LAST_ACTIVITY=$(date -r "$LATEST_LOG" '+%H:%M:%S' 2>/dev/null || echo "")
      fi

      # Review queue count
      REVIEW_COUNT=$(ls "$REVIEW_DIR/${PROJECT_NAME}"_*.json 2>/dev/null | wc -l | tr -d ' ' || echo "0")

      if [[ "$JSON_OUTPUT" == "true" ]]; then
        [[ "$JSON_PROJECTS" != "[" ]] && JSON_PROJECTS="$JSON_PROJECTS,"
        JSON_PROJECTS="$JSON_PROJECTS{\"name\":\"$PROJECT_NAME\",\"status\":\"$STATUS\",\"pid\":\"$PID\",\"prd\":\"$PRD_NAME\",\"stories_total\":$STORIES_TOTAL,\"stories_done\":$STORIES_DONE,\"reviews_pending\":$REVIEW_COUNT}"
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
        echo -e "    Status:   $STATUS $([ -n "$PID" ] && echo "(PID $PID)" || echo "")"
        echo -e "    Progress: $PROGRESS"
        [[ -n "$PRD_NAME" ]] && echo -e "    PRD:      $PRD_NAME"
        [[ "$REVIEW_COUNT" -gt 0 ]] && echo -e "    Reviews:  ${YELLOW}$REVIEW_COUNT awaiting review${NC}"
        [[ -n "$LAST_ACTIVITY" ]] && echo -e "    Last log: $LAST_ACTIVITY"
        echo ""
      fi
    done < "$REGISTRY"
  fi

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    JSON_PROJECTS="$JSON_PROJECTS]"
    echo "{\"timestamp\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",\"running\":$RUNNING_COUNT,\"completed\":$COMPLETED_COUNT,\"total_stories\":$TOTAL_STORIES,\"total_done\":$TOTAL_DONE,\"projects\":$JSON_PROJECTS}"
  else
    # Summary bar
    echo -e "  ${BOLD}─────────────────────────────────────────${NC}"
    echo -e "  Running: ${GREEN}$RUNNING_COUNT${NC}  Completed: ${CYAN}$COMPLETED_COUNT${NC}  Stories: $TOTAL_DONE/$TOTAL_STORIES"

    # Review queue summary
    TOTAL_REVIEWS=$(ls "$REVIEW_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [[ "$TOTAL_REVIEWS" -gt 0 ]]; then
      echo -e "  ${YELLOW}Review queue: $TOTAL_REVIEWS items awaiting human review${NC}"
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
