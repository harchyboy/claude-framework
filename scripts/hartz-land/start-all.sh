#!/bin/bash
# start-all.sh — Launch Ralph loops for all projects with active PRDs
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
#   --max-concurrent <n>   Max concurrent Ralph loops (default: 3)
#   --help                 Show this help
#
# Each project runs in its own background process with output logged to
# ~/.hartz-claude-framework/logs/<project>-<timestamp>.log

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

MAX_ITERATIONS=20
MODEL="claude-sonnet-4-6"
TIMEOUT=30
DRY_RUN=false
SPECIFIC_PROJECT=""
VERIFY=false
MAX_CONCURRENT=3

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations) MAX_ITERATIONS="$2"; shift ;;
    --model)          MODEL="$2"; shift ;;
    --timeout)        TIMEOUT="$2"; shift ;;
    --dry-run)        DRY_RUN=true ;;
    --project)        SPECIFIC_PROJECT="$2"; shift ;;
    --verify)         VERIFY=true ;;
    --max-concurrent) MAX_CONCURRENT="$2"; shift ;;
    --help)
      sed -n '2,16p' "$0"
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

  # Check for existing running process
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
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${YELLOW}  DRY RUN — nothing started${NC}"
  exit 0
fi

# ─── Launch Ralph loops ──────────────────────────────────────────────────────

RUNNING=0
STARTED=0

for project_path in "${PROJECTS_TO_START[@]}"; do
  PROJECT_NAME=$(basename "$project_path")

  # Wait if at max concurrent
  while [[ "$RUNNING" -ge "$MAX_CONCURRENT" ]]; do
    # Check which processes have finished
    for pid_file in "$PID_DIR"/*.pid; do
      [[ ! -f "$pid_file" ]] && continue
      PID=$(cat "$pid_file")
      if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$pid_file"
        RUNNING=$((RUNNING - 1))
      fi
    done
    if [[ "$RUNNING" -ge "$MAX_CONCURRENT" ]]; then
      sleep 10
    fi
  done

  LOG_FILE="$LOG_DIR/${PROJECT_NAME}_${TIMESTAMP}.log"

  RALPH_ARGS=(
    "$MAX_ITERATIONS"
    --model "$MODEL"
    --timeout "$TIMEOUT"
    --quality-gate
    --telemetry
  )

  if [[ "$VERIFY" == "true" ]]; then
    RALPH_ARGS+=(--verify)
  fi

  info "Starting $PROJECT_NAME → $LOG_FILE"

  (
    cd "$project_path"
    git pull --rebase 2>/dev/null || true
    bash scripts/ralph.sh "${RALPH_ARGS[@]}" 2>&1 | tee "$LOG_FILE"

    # Run verification if enabled and ralph.sh doesn't have --verify yet
    if [[ "$VERIFY" == "true" ]] && [[ -f "scripts/generate-proof.sh" ]]; then
      # Verify all completed stories without proof packets
      for prd_dir in scripts/ralph-moss/prds/*/; do
        [[ ! -f "$prd_dir/prd.json" ]] && continue
        node -e "
          const prd = JSON.parse(require('fs').readFileSync('$prd_dir/prd.json', 'utf8'));
          const completed = prd.userStories.filter(s => s.passes);
          completed.forEach(s => {
            const fs = require('fs');
            if (!fs.existsSync('proof/' + s.id + '/verdict.json')) {
              console.log(s.id);
            }
          });
        " 2>/dev/null | while read -r story_id; do
          info "Verifying $story_id..."
          bash scripts/generate-proof.sh "$story_id" "$prd_dir/prd.json" --skip-runtime 2>&1 | tee -a "$LOG_FILE" || true
        done
      done
    fi

    rm -f "$PID_DIR/${PROJECT_NAME}.pid"
  ) &

  RALPH_PID=$!
  echo "$RALPH_PID" > "$PID_DIR/${PROJECT_NAME}.pid"
  RUNNING=$((RUNNING + 1))
  STARTED=$((STARTED + 1))
  ok "$PROJECT_NAME started (PID $RALPH_PID)"

  sleep 2  # Stagger starts slightly
done

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   $STARTED agents deployed to Hartz Land   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Monitor:  bash scripts/hartz-land/monitor.sh"
echo "  Logs:     $LOG_DIR/"
echo "  PIDs:     $PID_DIR/"
echo ""
echo "  To stop all: bash scripts/hartz-land/stop-all.sh"
echo ""
