#!/bin/bash
# start-all.sh — Launch Ralph loops for all projects
#
# Usage:
#   bash scripts/hartz-land/start-all.sh [options]
#
# Options:
#   --max-iterations <n>   Max iterations per project (default: 20)
#   --model <model-id>     Override Claude model (default: claude-sonnet-4-6)
#   --timeout <min>        Per-iteration timeout (default: 30)
#   --dry-run              Show what would be started without starting
#   --project <name>       Only start a specific project
#   --verify               Enable verification after each story
#   --auto-pr              Enable auto-PR creation (confidence >= 0.9)
#   --max-concurrent <n>   Max concurrent Ralph loops (default: 3)
#   --help                 Show this help
#
# Platform support:
#   Linux/macOS (tmux available):  Each project runs in a tmux session
#     tmux attach -t hartz-<project>    — Watch an agent work
#     Ctrl-b d                          — Detach without stopping
#
#   Windows (no tmux):  Each project runs as a background process with logging
#     tail -f ~/.hartz-claude-framework/logs/<project>_*.log  — Watch output

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

MAX_ITERATIONS=20
MODEL="claude-sonnet-4-6"
TIMEOUT=30
DRY_RUN=false
SPECIFIC_PROJECT=""
VERIFY=false
AUTO_PR=false
MAX_CONCURRENT=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations) MAX_ITERATIONS="$2"; shift ;;
    --model)          MODEL="$2"; shift ;;
    --timeout)        TIMEOUT="$2"; shift ;;
    --dry-run)        DRY_RUN=true ;;
    --project)        SPECIFIC_PROJECT="$2"; shift ;;
    --verify)         VERIFY=true ;;
    --auto-pr)        AUTO_PR=true ;;
    --max-concurrent) MAX_CONCURRENT="$2"; shift ;;
    --help)
      sed -n '2,24p' "$0"
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
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
err()  { echo -e "${RED}  ❌ $1${NC}"; }

# ─── Platform detection ──────────────────────────────────────────────────────

USE_TMUX=false
if command -v tmux &>/dev/null; then
  USE_TMUX=true
fi

TMUX_PREFIX="hartz"

# ─── Directories ─────────────────────────────────────────────────────────────

HARTZ_DIR="$HOME/.hartz-claude-framework"
LOG_DIR="$HARTZ_DIR/logs"
PID_DIR="$HARTZ_DIR/pids"
REGISTRY="$HARTZ_DIR/projects.txt"

mkdir -p "$LOG_DIR" "$PID_DIR"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   HARTZ LAND — Starting All Agents       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

if [[ "$USE_TMUX" == "true" ]]; then
  info "Mode: tmux sessions"
else
  info "Mode: background processes (tmux not found)"
fi

if [[ ! -f "$REGISTRY" ]]; then
  err "No project registry found. Run setup.sh first."
  exit 1
fi

# ─── Find projects with active PRDs ──────────────────────────────────────────

PROJECTS_TO_START=()
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

while IFS= read -r project_path; do
  [[ -z "$project_path" ]] && continue
  [[ "$project_path" == \#* ]] && continue
  [[ ! -d "$project_path" ]] && continue

  PROJECT_NAME=$(basename "$project_path")

  # Filter to specific project if requested
  if [[ -n "$SPECIFIC_PROJECT" ]] && [[ "$PROJECT_NAME" != "$SPECIFIC_PROJECT" ]]; then
    continue
  fi

  # Check for active PRD
  HAS_PRD=false
  for prd_dir in "$project_path"/scripts/ralph-moss/prds/*/; do
    if [[ -f "$prd_dir/prd.json" ]]; then
      PENDING=$(node -e "
        const prd = JSON.parse(require('fs').readFileSync('$prd_dir/prd.json', 'utf8'));
        console.log(prd.userStories.filter(s => !s.passes).length);
      " 2>/dev/null || echo "0")
      if [[ "$PENDING" -gt 0 ]]; then
        HAS_PRD=true
        info "$PROJECT_NAME: $PENDING stories pending in $(basename "$prd_dir")"
        break
      fi
    fi
  done

  if [[ "$HAS_PRD" != "true" ]]; then
    warn "$PROJECT_NAME: No active PRD — skipping"
    continue
  fi

  # Check for existing session/process
  if [[ "$USE_TMUX" == "true" ]]; then
    SESSION_NAME="${TMUX_PREFIX}-${PROJECT_NAME}"
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
      warn "$PROJECT_NAME: tmux session already running — skipping"
      continue
    fi
  else
    PID_FILE="$PID_DIR/${PROJECT_NAME}.pid"
    if [[ -f "$PID_FILE" ]]; then
      OLD_PID=$(cat "$PID_FILE")
      if kill -0 "$OLD_PID" 2>/dev/null; then
        warn "$PROJECT_NAME: Already running (PID $OLD_PID) — skipping"
        continue
      else
        rm -f "$PID_FILE"
      fi
    fi
  fi

  PROJECTS_TO_START+=("$project_path")
done < "$REGISTRY"

if [[ ${#PROJECTS_TO_START[@]} -eq 0 ]]; then
  warn "No projects to start. Ensure projects have active PRDs."
  exit 0
fi

echo ""
echo "  Projects to start: ${#PROJECTS_TO_START[@]}"
echo "  Max concurrent: $MAX_CONCURRENT"
echo "  Model: $MODEL"
echo "  Max iterations: $MAX_ITERATIONS"
echo "  Timeout: ${TIMEOUT}min"
echo "  Verification: $VERIFY"
echo "  Auto-PR: $AUTO_PR"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}  DRY RUN — nothing started${NC}"
  exit 0
fi

# ─── Count active agents ────────────────────────────────────────────────────

count_active() {
  if [[ "$USE_TMUX" == "true" ]]; then
    tmux list-sessions -F '#{session_name}' 2>/dev/null \
      | grep -c "^${TMUX_PREFIX}-" || echo "0"
  else
    local count=0
    for pid_file in "$PID_DIR"/*.pid; do
      [[ ! -f "$pid_file" ]] && continue
      local pid
      pid=$(cat "$pid_file")
      if kill -0 "$pid" 2>/dev/null; then
        count=$((count + 1))
      else
        rm -f "$pid_file"
      fi
    done
    echo "$count"
  fi
}

# ─── Build ralph command string ──────────────────────────────────────────────

build_ralph_cmd() {
  local project_path="$1"
  local log_file="$2"

  local cmd="cd '$project_path'"
  cmd+=" && git pull --rebase 2>/dev/null || true"
  cmd+=" && bash scripts/ralph.sh $MAX_ITERATIONS"
  cmd+=" --model '$MODEL'"
  cmd+=" --timeout $TIMEOUT"
  cmd+=" --quality-gate"
  cmd+=" --telemetry"

  if [[ "$VERIFY" == "true" ]]; then
    cmd+=" --verify"
  fi

  if [[ "$AUTO_PR" == "true" ]]; then
    cmd+=" --auto-pr"
  fi

  cmd+=" 2>&1 | tee '$log_file'"
  echo "$cmd"
}

# ─── Launch Ralph loops ─────────────────────────────────────────────────────

STARTED=0

for project_path in "${PROJECTS_TO_START[@]}"; do
  PROJECT_NAME=$(basename "$project_path")

  # Wait if at max concurrent
  while true; do
    ACTIVE=$(count_active)
    if [[ "$ACTIVE" -lt "$MAX_CONCURRENT" ]]; then
      break
    fi
    info "At max concurrent ($MAX_CONCURRENT) — waiting for a slot..."
    sleep 15
  done

  LOG_FILE="$LOG_DIR/${PROJECT_NAME}_${TIMESTAMP}.log"
  RALPH_CMD=$(build_ralph_cmd "$project_path" "$LOG_FILE")

  if [[ "$USE_TMUX" == "true" ]]; then
    # ─── tmux mode ──────────────────────────────────────────────────────
    SESSION_NAME="${TMUX_PREFIX}-${PROJECT_NAME}"
    FULL_CMD="$RALPH_CMD; echo ''; echo '━━━ Session complete. Press Enter to close. ━━━'; read"

    info "Starting $PROJECT_NAME → tmux: $SESSION_NAME"
    tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50 "bash -c \"$FULL_CMD\""
    ok "$PROJECT_NAME started (tmux: $SESSION_NAME)"

  else
    # ─── Background process mode (Windows) ──────────────────────────────
    info "Starting $PROJECT_NAME → $LOG_FILE"

    (
      eval "$RALPH_CMD"
      rm -f "$PID_DIR/${PROJECT_NAME}.pid"
    ) &

    RALPH_PID=$!
    echo "$RALPH_PID" > "$PID_DIR/${PROJECT_NAME}.pid"
    ok "$PROJECT_NAME started (PID $RALPH_PID)"
  fi

  STARTED=$((STARTED + 1))
  sleep 3  # Stagger starts
done

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   $STARTED agents deployed to Hartz Land   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

if [[ "$USE_TMUX" == "true" ]]; then
  echo "  Sessions:"
  tmux list-sessions -F '    #{session_name}  (created #{session_created_string})' 2>/dev/null \
    | grep "^    ${TMUX_PREFIX}-" || echo "    (none)"
  echo ""
  echo "  Commands:"
  echo "    tmux ls                               — List all sessions"
  echo "    tmux attach -t ${TMUX_PREFIX}-<project>       — Watch an agent work"
  echo "    Ctrl-b d                              — Detach (agent keeps running)"
else
  echo "  Processes:"
  for pid_file in "$PID_DIR"/*.pid; do
    [[ ! -f "$pid_file" ]] && continue
    pname=$(basename "$pid_file" .pid)
    ppid=$(cat "$pid_file")
    echo "    $pname (PID $ppid)"
  done
  echo ""
  echo "  Commands:"
  echo "    tail -f $LOG_DIR/<project>_${TIMESTAMP}.log  — Watch agent output"
fi

echo "    bash scripts/hartz-land/monitor.sh    — Dashboard view"
echo "    bash scripts/hartz-land/stop-all.sh   — Stop all agents"
echo ""
echo "  Logs:  $LOG_DIR/"
echo ""
