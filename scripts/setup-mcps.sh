#!/bin/bash
# setup-mcps.sh — Install and configure MCP servers for Hartz Claude Framework
#
# Usage:
#   bash scripts/setup-mcps.sh [options]
#
# Options:
#   --global          Install MCPs at user scope (~/.claude.json) instead of project scope
#   --github-token    GitHub PAT for the GitHub MCP (or set GITHUB_TOKEN env var)
#   --memory-path     Path for shared memory file (default: ~/.hartz-claude-framework/shared-memory.jsonl)
#   --skip-playwright Skip Playwright MCP
#   --skip-github     Skip GitHub MCP
#   --skip-memory     Skip Memory MCP
#   --skip-thinking   Skip Sequential Thinking MCP
#   --skip-filesystem Skip Filesystem MCP
#   --projects-dir    Directory containing projects for Filesystem MCP (default: ~/Documents/Projects)
#   --headed          Install Playwright in headed mode (visible browser)
#   --help            Show this help

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────

GLOBAL_SCOPE=false
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
MEMORY_PATH=""
SKIP_PLAYWRIGHT=false
SKIP_GITHUB=false
SKIP_MEMORY=false
SKIP_THINKING=false
SKIP_FILESYSTEM=false
PROJECTS_DIR=""
PLAYWRIGHT_HEADED=false

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

# ─── Parse arguments ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)          GLOBAL_SCOPE=true ;;
    --github-token)    GITHUB_TOKEN="$2"; shift ;;
    --memory-path)     MEMORY_PATH="$2"; shift ;;
    --skip-playwright) SKIP_PLAYWRIGHT=true ;;
    --skip-github)     SKIP_GITHUB=true ;;
    --skip-memory)     SKIP_MEMORY=true ;;
    --skip-thinking)   SKIP_THINKING=true ;;
    --skip-filesystem) SKIP_FILESYSTEM=true ;;
    --projects-dir)    PROJECTS_DIR="$2"; shift ;;
    --headed)          PLAYWRIGHT_HEADED=true ;;
    --help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# ─── Defaults ─────────────────────────────────────────────────────────────────

if [[ -z "$MEMORY_PATH" ]]; then
  MEMORY_PATH="$HOME/.hartz-claude-framework/shared-memory.jsonl"
fi

if [[ -z "$PROJECTS_DIR" ]]; then
  PROJECTS_DIR="$HOME/Documents/Projects"
fi

# Ensure shared directory exists
mkdir -p "$(dirname "$MEMORY_PATH")"

# ─── Pre-flight ───────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Hartz Claude Framework — MCP Setup     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# Check for claude CLI
if ! command -v claude > /dev/null 2>&1; then
  err "Claude Code CLI not found. Install it first: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

# Check for npx
if ! command -v npx > /dev/null 2>&1; then
  err "npx not found. Install Node.js first."
  exit 1
fi

SCOPE_FLAG=""
SCOPE_LABEL="project"
if [[ "$GLOBAL_SCOPE" == "true" ]]; then
  SCOPE_FLAG="--scope user"
  SCOPE_LABEL="user (global)"
fi

echo "  Scope: $SCOPE_LABEL"
echo "  Memory path: $MEMORY_PATH"
echo ""

INSTALLED=0
SKIPPED=0
FAILED=0

# ─── Install Playwright MCP ──────────────────────────────────────────────────

if [[ "$SKIP_PLAYWRIGHT" != "true" ]]; then
  h1 "Installing Playwright MCP (Microsoft)..."

  PW_ARGS=("@playwright/mcp@latest")
  if [[ "$PLAYWRIGHT_HEADED" != "true" ]]; then
    PW_ARGS+=("--headless")
  fi

  if claude mcp add $SCOPE_FLAG playwright -- npx -y "${PW_ARGS[@]}" 2>/dev/null; then
    ok "Playwright MCP installed"
    INSTALLED=$((INSTALLED + 1))
  else
    # Fallback: try removing first then re-adding
    claude mcp remove playwright 2>/dev/null || true
    if claude mcp add $SCOPE_FLAG playwright -- npx -y "${PW_ARGS[@]}" 2>/dev/null; then
      ok "Playwright MCP installed (replaced existing)"
      INSTALLED=$((INSTALLED + 1))
    else
      err "Failed to install Playwright MCP"
      FAILED=$((FAILED + 1))
    fi
  fi

  # Install Playwright browsers
  info "Installing Playwright browsers (this may take a minute)..."
  npx playwright install chromium 2>/dev/null || warn "Browser install failed — run 'npx playwright install chromium' manually"
else
  SKIPPED=$((SKIPPED + 1))
fi

# ─── Install GitHub MCP ──────────────────────────────────────────────────────

if [[ "$SKIP_GITHUB" != "true" ]]; then
  h1 "Installing GitHub MCP..."

  if [[ -z "$GITHUB_TOKEN" ]]; then
    warn "No GitHub token provided"
    warn "Set GITHUB_TOKEN env var or pass --github-token <token>"
    warn "To create a token: https://github.com/settings/tokens"
    warn "Required scopes: repo, read:org, read:project"
    echo ""

    # Install anyway with placeholder
    if claude mcp add $SCOPE_FLAG github -- npx -y @modelcontextprotocol/server-github 2>/dev/null; then
      ok "GitHub MCP installed (token not configured — set GITHUB_TOKEN env var)"
      INSTALLED=$((INSTALLED + 1))
    else
      claude mcp remove github 2>/dev/null || true
      claude mcp add $SCOPE_FLAG github -- npx -y @modelcontextprotocol/server-github 2>/dev/null || true
      INSTALLED=$((INSTALLED + 1))
    fi
  else
    # Install with token
    export GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN"
    if claude mcp add $SCOPE_FLAG github -e GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN" -- npx -y @modelcontextprotocol/server-github 2>/dev/null; then
      ok "GitHub MCP installed with token"
      INSTALLED=$((INSTALLED + 1))
    else
      claude mcp remove github 2>/dev/null || true
      claude mcp add $SCOPE_FLAG github -e GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_TOKEN" -- npx -y @modelcontextprotocol/server-github 2>/dev/null || true
      INSTALLED=$((INSTALLED + 1))
    fi
  fi
else
  SKIPPED=$((SKIPPED + 1))
fi

# ─── Install Memory MCP ──────────────────────────────────────────────────────

if [[ "$SKIP_MEMORY" != "true" ]]; then
  h1 "Installing Memory MCP (Knowledge Graph)..."

  if claude mcp add $SCOPE_FLAG memory -e MEMORY_FILE_PATH="$MEMORY_PATH" -- npx -y @modelcontextprotocol/server-memory 2>/dev/null; then
    ok "Memory MCP installed (file: $MEMORY_PATH)"
    INSTALLED=$((INSTALLED + 1))
  else
    claude mcp remove memory 2>/dev/null || true
    if claude mcp add $SCOPE_FLAG memory -e MEMORY_FILE_PATH="$MEMORY_PATH" -- npx -y @modelcontextprotocol/server-memory 2>/dev/null; then
      ok "Memory MCP installed (replaced existing)"
      INSTALLED=$((INSTALLED + 1))
    else
      err "Failed to install Memory MCP"
      FAILED=$((FAILED + 1))
    fi
  fi
else
  SKIPPED=$((SKIPPED + 1))
fi

# ─── Install Sequential Thinking MCP ─────────────────────────────────────────

if [[ "$SKIP_THINKING" != "true" ]]; then
  h1 "Installing Sequential Thinking MCP..."

  if claude mcp add $SCOPE_FLAG sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking 2>/dev/null; then
    ok "Sequential Thinking MCP installed"
    INSTALLED=$((INSTALLED + 1))
  else
    claude mcp remove sequential-thinking 2>/dev/null || true
    if claude mcp add $SCOPE_FLAG sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking 2>/dev/null; then
      ok "Sequential Thinking MCP installed (replaced existing)"
      INSTALLED=$((INSTALLED + 1))
    else
      err "Failed to install Sequential Thinking MCP"
      FAILED=$((FAILED + 1))
    fi
  fi
else
  SKIPPED=$((SKIPPED + 1))
fi

# ─── Install Filesystem MCP ──────────────────────────────────────────────────

if [[ "$SKIP_FILESYSTEM" != "true" ]]; then
  h1 "Installing Filesystem MCP..."

  # Build list of project directories from registry
  PROJECT_PATHS=()
  REGISTRY="$HOME/.hartz-claude-framework/projects.txt"

  if [[ -f "$REGISTRY" ]]; then
    while IFS= read -r project_path; do
      [[ -z "$project_path" ]] && continue
      [[ "$project_path" == \#* ]] && continue
      if [[ -d "$project_path" ]]; then
        PROJECT_PATHS+=("$project_path")
      fi
    done < "$REGISTRY"
    info "Found ${#PROJECT_PATHS[@]} projects in registry"
  else
    # Fallback to projects directory
    if [[ -d "$PROJECTS_DIR" ]]; then
      PROJECT_PATHS+=("$PROJECTS_DIR")
      info "Using projects directory: $PROJECTS_DIR"
    fi
  fi

  if [[ ${#PROJECT_PATHS[@]} -gt 0 ]]; then
    if claude mcp add $SCOPE_FLAG filesystem -- npx -y @modelcontextprotocol/server-filesystem "${PROJECT_PATHS[@]}" 2>/dev/null; then
      ok "Filesystem MCP installed (${#PROJECT_PATHS[@]} paths)"
      INSTALLED=$((INSTALLED + 1))
    else
      claude mcp remove filesystem 2>/dev/null || true
      claude mcp add $SCOPE_FLAG filesystem -- npx -y @modelcontextprotocol/server-filesystem "${PROJECT_PATHS[@]}" 2>/dev/null || true
      INSTALLED=$((INSTALLED + 1))
    fi
  else
    warn "No project paths found — skipping Filesystem MCP"
    warn "Add projects to $REGISTRY or pass --projects-dir"
    SKIPPED=$((SKIPPED + 1))
  fi
else
  SKIPPED=$((SKIPPED + 1))
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   MCP Setup Complete                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Installed: $INSTALLED"
echo "  Skipped:   $SKIPPED"
echo "  Failed:    $FAILED"
echo ""

if [[ "$FAILED" -gt 0 ]]; then
  warn "Some MCPs failed to install. Check errors above."
fi

echo "  Verify with: claude mcp list"
echo ""
echo "  To add more MCPs later:"
echo "    Sentry:    claude mcp add --transport http sentry https://mcp.sentry.dev/mcp"
echo "    Slack:     See https://docs.slack.dev/ai/slack-mcp-server/"
echo "    Docker:    claude mcp add docker -- npx -y @quantgeekdev/docker-mcp"
echo ""
