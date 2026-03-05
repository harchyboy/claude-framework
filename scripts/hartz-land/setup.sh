#!/bin/bash
# setup.sh — First-time setup for a Hartz Land machine
#
# Hartz Land is a dedicated machine (or external drive) where agents live and work
# autonomously. This script sets up the environment for unattended development.
#
# Usage:
#   bash scripts/hartz-land/setup.sh [options]
#
# Options:
#   --projects-dir <dir>   Directory containing project repos (default: ~/Documents/Projects)
#   --memory-path <path>   Shared memory file (default: ~/.hartz-claude-framework/shared-memory.jsonl)
#   --skip-mcps            Skip MCP installation
#   --skip-browsers        Skip Playwright browser installation
#   --help                 Show this help

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

PROJECTS_DIR="${HOME}/Documents/Projects"
MEMORY_PATH="${HOME}/.hartz-claude-framework/shared-memory.jsonl"
SKIP_MCPS=false
SKIP_BROWSERS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects-dir)   PROJECTS_DIR="$2"; shift ;;
    --memory-path)    MEMORY_PATH="$2"; shift ;;
    --skip-mcps)      SKIP_MCPS=true ;;
    --skip-browsers)  SKIP_BROWSERS=true ;;
    --help)
      sed -n '2,15p' "$0"
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
h1()   { echo -e "\n${BOLD}$1${NC}"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   HARTZ LAND — Machine Setup             ║${NC}"
echo -e "${BOLD}║   Where the agents live                  ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ─── Pre-flight checks ──────────────────────────────────────────────────────

h1 "Pre-flight checks..."

CHECKS_PASSED=true

# Node.js
if command -v node > /dev/null 2>&1; then
  ok "Node.js $(node --version)"
else
  err "Node.js not found — install from https://nodejs.org"
  CHECKS_PASSED=false
fi

# npm/npx
if command -v npx > /dev/null 2>&1; then
  ok "npx available"
else
  err "npx not found"
  CHECKS_PASSED=false
fi

# Git
if command -v git > /dev/null 2>&1; then
  ok "Git $(git --version | awk '{print $3}')"
else
  err "Git not found"
  CHECKS_PASSED=false
fi

# Claude CLI
if command -v claude > /dev/null 2>&1; then
  ok "Claude Code CLI available"
else
  err "Claude Code CLI not found — install: npm install -g @anthropic-ai/claude-code"
  CHECKS_PASSED=false
fi

# jq (optional but useful)
if command -v jq > /dev/null 2>&1; then
  ok "jq available"
else
  warn "jq not found — some features will use node instead (optional)"
fi

# Python (optional)
if command -v python > /dev/null 2>&1 || command -v python3 > /dev/null 2>&1; then
  ok "Python available"
else
  warn "Python not found — hartz-command hooks won't work (optional)"
fi

if [[ "$CHECKS_PASSED" != "true" ]]; then
  err "Required tools missing. Install them and re-run."
  exit 1
fi

# ─── Create directories ─────────────────────────────────────────────────────

h1 "Creating Hartz Land directories..."

HARTZ_DIR="$HOME/.hartz-claude-framework"
mkdir -p "$HARTZ_DIR"
mkdir -p "$HARTZ_DIR/review-queue"
mkdir -p "$HARTZ_DIR/logs"
mkdir -p "$(dirname "$MEMORY_PATH")"

ok "Core directories created"

# ─── Discover and sync projects ──────────────────────────────────────────────

h1 "Discovering projects in $PROJECTS_DIR..."

REGISTRY="$HARTZ_DIR/projects.txt"
PROJECT_COUNT=0

if [[ -d "$PROJECTS_DIR" ]]; then
  for dir in "$PROJECTS_DIR"/*/; do
    [[ ! -d "$dir" ]] && continue
    # Check if it's a git repo with the framework installed
    if [[ -d "$dir/.git" ]]; then
      # Normalize path
      PROJECT_PATH="$(cd "$dir" && pwd)"

      # Check if already in registry
      if [[ -f "$REGISTRY" ]] && grep -qF "$PROJECT_PATH" "$REGISTRY" 2>/dev/null; then
        info "Already registered: $(basename "$dir")"
      else
        echo "$PROJECT_PATH" >> "$REGISTRY"
        info "Registered: $(basename "$dir")"
      fi
      PROJECT_COUNT=$((PROJECT_COUNT + 1))

      # Check framework installation
      if [[ -f "$dir/.claude/settings.json" ]]; then
        ok "  Framework installed: $(basename "$dir")"
      else
        warn "  Framework NOT installed: $(basename "$dir") — run install.sh"
      fi

      # Pull latest
      (cd "$dir" && git pull --rebase 2>/dev/null || true) &
    fi
  done
  wait # Wait for all git pulls
fi

ok "Found $PROJECT_COUNT projects"

# ─── Install MCPs ────────────────────────────────────────────────────────────

if [[ "$SKIP_MCPS" != "true" ]]; then
  h1 "Installing MCP servers..."

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -f "$SCRIPT_DIR/setup-mcps.sh" ]]; then
    bash "$SCRIPT_DIR/setup-mcps.sh" \
      --global \
      --memory-path "$MEMORY_PATH" \
      --projects-dir "$PROJECTS_DIR"
  else
    warn "setup-mcps.sh not found — install MCPs manually"
  fi
fi

# ─── Install Playwright browsers ─────────────────────────────────────────────

if [[ "$SKIP_BROWSERS" != "true" ]]; then
  h1 "Installing Playwright browsers..."
  npx playwright install chromium 2>/dev/null && ok "Chromium installed" || warn "Chromium install failed — run manually"
fi

# ─── Create Hartz Land config ────────────────────────────────────────────────

h1 "Writing Hartz Land configuration..."

CONFIG_FILE="$HARTZ_DIR/hartz-land.json"
HOSTNAME=$(hostname)
OS_TYPE=$(uname -s)

node -e "
  const config = {
    machine_name: 'hartz-land',
    hostname: '$HOSTNAME',
    os: '$OS_TYPE',
    projects_dir: '$PROJECTS_DIR',
    memory_path: '$MEMORY_PATH',
    review_queue_dir: '$HARTZ_DIR/review-queue',
    log_dir: '$HARTZ_DIR/logs',
    setup_timestamp: new Date().toISOString(),
    defaults: {
      ralph_model: 'claude-sonnet-4-6',
      ralph_timeout_min: 30,
      ralph_max_iterations: 20,
      quality_gate: true,
      telemetry: true,
      verification: true
    }
  };
  require('fs').writeFileSync('$CONFIG_FILE', JSON.stringify(config, null, 2));
"
ok "Configuration saved to $CONFIG_FILE"

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   HARTZ LAND — Setup Complete            ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Machine:     $HOSTNAME"
echo "  Projects:    $PROJECT_COUNT"
echo "  Memory:      $MEMORY_PATH"
echo "  Review queue: $HARTZ_DIR/review-queue"
echo "  Config:      $CONFIG_FILE"
echo ""
echo "  Next steps:"
echo "    1. Start all Ralph loops:  bash scripts/hartz-land/start-all.sh"
echo "    2. Monitor progress:       bash scripts/hartz-land/monitor.sh"
echo "    3. Generate daily digest:  bash scripts/hartz-land/daily-digest.sh"
echo ""
