#!/bin/bash
# sync.sh — Bi-directional sync for Hartz Claude Framework
#
# Usage:
#   bash scripts/sync.sh push          Push framework updates to all registered projects
#   bash scripts/sync.sh pull           Pull changes from a project back into the framework
#   bash scripts/sync.sh status         Show sync status across all projects
#   bash scripts/sync.sh register       Register the current project directory
#   bash scripts/sync.sh unregister     Remove the current project from the registry
#
# The registry lives at: ~/.hartz-claude-framework/projects.txt

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_DIR="$HOME/.hartz-claude-framework"
REGISTRY_FILE="$REGISTRY_DIR/projects.txt"
FRAMEWORK_REMOTE="https://github.com/Hartz-AI/claude-framework"

# ─── Colours ─────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
err()  { echo -e "${RED}  ✗ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
h1()   { echo -e "\n${BOLD}$1${NC}"; }

# ─── Registry ────────────────────────────────────────────────────────────────

ensure_registry() {
  mkdir -p "$REGISTRY_DIR"
  touch "$REGISTRY_FILE"
}

get_projects() {
  ensure_registry
  # Return non-empty, non-comment lines
  grep -v '^\s*#' "$REGISTRY_FILE" 2>/dev/null | grep -v '^\s*$' || true
}

# ─── Commands ────────────────────────────────────────────────────────────────

cmd_register() {
  ensure_registry
  local project_dir="${1:-$(pwd)}"

  # Resolve to absolute path
  project_dir="$(cd "$project_dir" && pwd)"

  # Verify it has a .claude-framework submodule
  if [[ ! -d "$project_dir/.claude-framework" ]]; then
    err "$project_dir does not have a .claude-framework submodule"
    echo "  Run: cd $project_dir && git submodule add $FRAMEWORK_REMOTE .claude-framework"
    exit 1
  fi

  # Check if already registered
  if grep -qF "$project_dir" "$REGISTRY_FILE" 2>/dev/null; then
    warn "Already registered: $project_dir"
    return 0
  fi

  echo "$project_dir" >> "$REGISTRY_FILE"
  ok "Registered: $project_dir"
}

cmd_unregister() {
  ensure_registry
  local project_dir="${1:-$(pwd)}"
  project_dir="$(cd "$project_dir" && pwd)"

  if grep -qF "$project_dir" "$REGISTRY_FILE" 2>/dev/null; then
    grep -vF "$project_dir" "$REGISTRY_FILE" > "$REGISTRY_FILE.tmp" || true
    mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
    ok "Unregistered: $project_dir"
  else
    warn "Not registered: $project_dir"
  fi
}

cmd_status() {
  ensure_registry

  local framework_commit
  framework_commit=$(cd "$FRAMEWORK_DIR" && git rev-parse --short HEAD 2>/dev/null)
  local framework_msg
  framework_msg=$(cd "$FRAMEWORK_DIR" && git log --oneline -1 2>/dev/null)

  h1 "Hartz Claude Framework — Sync Status"
  echo ""
  echo -e "  Framework: ${BOLD}$framework_msg${NC}"
  echo ""

  local projects
  projects=$(get_projects)

  if [[ -z "$projects" ]]; then
    warn "No projects registered. Run: bash scripts/sync.sh register /path/to/project"
    echo ""
    echo "  Or auto-discover projects:"
    echo "    bash scripts/sync.sh discover /path/to/projects/dir"
    return 0
  fi

  printf "  ${BOLD}%-30s %-10s %s${NC}\n" "PROJECT" "STATUS" "PINNED TO"
  printf "  %-30s %-10s %s\n" "───────────────────────────" "────────" "─────────────────────────────────"

  while IFS= read -r project_dir; do
    local name
    name=$(basename "$project_dir")
    local submod="$project_dir/.claude-framework"

    if [[ ! -d "$submod" ]]; then
      printf "  %-30s ${RED}%-10s${NC} %s\n" "$name" "MISSING" "submodule not found"
      continue
    fi

    local pinned_commit
    pinned_commit=$(cd "$submod" && git rev-parse --short HEAD 2>/dev/null || echo "???")
    local pinned_msg
    pinned_msg=$(cd "$submod" && git log --oneline -1 2>/dev/null || echo "unknown")

    if [[ "$pinned_commit" == "$framework_commit" ]]; then
      printf "  %-30s ${GREEN}%-10s${NC} %s\n" "$name" "UP TO DATE" "$pinned_msg"
    else
      # Count how many commits behind
      local behind
      behind=$(cd "$submod" && git fetch origin 2>/dev/null && git rev-list --count HEAD..origin/master 2>/dev/null || echo "?")
      printf "  %-30s ${YELLOW}%-10s${NC} %s\n" "$name" "${behind} BEHIND" "$pinned_msg"
    fi
  done <<< "$projects"

  echo ""
}

cmd_push() {
  ensure_registry

  local framework_commit
  framework_commit=$(cd "$FRAMEWORK_DIR" && git rev-parse --short HEAD)
  local framework_msg
  framework_msg=$(cd "$FRAMEWORK_DIR" && git log --oneline -1)

  h1 "Pushing framework updates to all projects"
  echo ""
  info "Framework at: $framework_msg"
  echo ""

  # First, ensure the framework is pushed to remote
  info "Ensuring framework is pushed to Hartz-AI remote..."
  cd "$FRAMEWORK_DIR"
  git push origin master 2>/dev/null && ok "Framework pushed to origin" || warn "Already up to date (or push failed)"
  echo ""

  local projects
  projects=$(get_projects)

  if [[ -z "$projects" ]]; then
    err "No projects registered. Run: bash scripts/sync.sh register /path/to/project"
    exit 1
  fi

  local updated=0
  local skipped=0
  local failed=0
  local total=0

  while IFS= read -r project_dir; do
    local name
    name=$(basename "$project_dir")
    local submod="$project_dir/.claude-framework"

    if [[ ! -d "$submod" ]]; then
      err "$name — submodule not found"
      ((failed++)) || true
      continue
    fi

    # Update submodule
    cd "$submod"
    git fetch origin 2>/dev/null

    local current
    current=$(git rev-parse --short HEAD 2>/dev/null)

    if [[ "$current" == "$framework_commit" ]]; then
      ok "$name — already up to date"
      ((skipped++)) || true
      continue
    fi

    git checkout origin/master 2>/dev/null
    local new_commit
    new_commit=$(git rev-parse --short HEAD 2>/dev/null)

    if [[ "$new_commit" == "$framework_commit" ]]; then
      ok "$name — updated to $framework_commit"

      # Re-run install to sync agents, commands, hooks, scripts
      info "$name — re-installing framework files..."
      cd "$FRAMEWORK_DIR"
      # Force-copy framework files (skip CLAUDE.md, PROGRESS.md, settings.json to preserve customisations)
      for agent in "$FRAMEWORK_DIR/.claude/agents/"*.md; do
        cp "$agent" "$project_dir/.claude/agents/$(basename "$agent")"
      done
      for cmd in "$FRAMEWORK_DIR/.claude/commands/"*.md; do
        cp "$cmd" "$project_dir/.claude/commands/$(basename "$cmd")"
      done
      for hook in "$FRAMEWORK_DIR/.claude/hooks/"*.sh; do
        cp "$hook" "$project_dir/.claude/hooks/$(basename "$hook")"
        chmod +x "$project_dir/.claude/hooks/$(basename "$hook")"
      done
      for script in "$FRAMEWORK_DIR/scripts/"*.sh; do
        local sname
        sname=$(basename "$script")
        # Don't overwrite sync.sh in projects — it lives in the framework only
        if [[ "$sname" != "sync.sh" ]]; then
          cp "$script" "$project_dir/scripts/$sname"
          chmod +x "$project_dir/scripts/$sname"
        fi
      done
      # Copy CODE-STANDARDS.md if it exists
      if [[ -f "$FRAMEWORK_DIR/docs/CODE-STANDARDS.md" ]]; then
        cp "$FRAMEWORK_DIR/docs/CODE-STANDARDS.md" "$project_dir/docs/CODE-STANDARDS.md"
      fi

      # Stage and commit the submodule pointer + updated files
      cd "$project_dir"
      git add .claude-framework .claude/ scripts/ docs/CODE-STANDARDS.md 2>/dev/null || true
      if ! git diff --cached --quiet 2>/dev/null; then
        git commit -m "chore: update claude framework to $framework_commit" 2>/dev/null
        ok "$name — committed submodule update"
      fi

      ((updated++)) || true
    else
      err "$name — update failed (at $new_commit, expected $framework_commit)"
      ((failed++)) || true
    fi
  done <<< "$projects"

  echo ""
  h1 "Summary"
  echo "  Updated: $updated | Already current: $skipped | Failed: $failed"
  echo ""

  if [[ $updated -gt 0 ]]; then
    warn "Submodule updates are committed locally. Push each project when ready:"
    echo "  for each project: cd <project> && git push"
  fi
}

cmd_pull() {
  # Pull changes FROM a project back into the framework
  # This handles the case where someone edits an agent/command/hook directly in a project
  # and wants to upstream those changes to the framework

  local source_dir="${1:-$(pwd)}"
  source_dir="$(cd "$source_dir" && pwd)"

  if [[ ! -d "$source_dir/.claude" ]]; then
    err "No .claude directory found in $source_dir"
    exit 1
  fi

  h1 "Pulling changes from $(basename "$source_dir") into framework"
  echo ""

  local changes=0

  # Compare agents
  for agent in "$source_dir/.claude/agents/"*.md; do
    [[ ! -f "$agent" ]] && continue
    local name
    name=$(basename "$agent")
    local framework_file="$FRAMEWORK_DIR/.claude/agents/$name"

    if [[ ! -f "$framework_file" ]]; then
      info "NEW agent: $name"
      cp "$agent" "$framework_file"
      ((changes++)) || true
    elif ! diff -q "$agent" "$framework_file" > /dev/null 2>&1; then
      warn "MODIFIED agent: $name"
      echo "    Project version differs from framework."
      # Show a brief diff summary
      diff --brief "$framework_file" "$agent" 2>/dev/null || true
      cp "$agent" "$framework_file"
      ok "  Updated framework agent: $name"
      ((changes++)) || true
    fi
  done

  # Compare commands
  for cmd in "$source_dir/.claude/commands/"*.md; do
    [[ ! -f "$cmd" ]] && continue
    local name
    name=$(basename "$cmd")
    local framework_file="$FRAMEWORK_DIR/.claude/commands/$name"

    if [[ ! -f "$framework_file" ]]; then
      info "NEW command: $name"
      cp "$cmd" "$framework_file"
      ((changes++)) || true
    elif ! diff -q "$cmd" "$framework_file" > /dev/null 2>&1; then
      warn "MODIFIED command: $name"
      cp "$cmd" "$framework_file"
      ok "  Updated framework command: $name"
      ((changes++)) || true
    fi
  done

  # Compare hooks
  for hook in "$source_dir/.claude/hooks/"*.sh; do
    [[ ! -f "$hook" ]] && continue
    local name
    name=$(basename "$hook")
    local framework_file="$FRAMEWORK_DIR/.claude/hooks/$name"

    if [[ ! -f "$framework_file" ]]; then
      info "NEW hook: $name"
      cp "$hook" "$framework_file"
      chmod +x "$framework_file"
      ((changes++)) || true
    elif ! diff -q "$hook" "$framework_file" > /dev/null 2>&1; then
      warn "MODIFIED hook: $name"
      cp "$hook" "$framework_file"
      chmod +x "$framework_file"
      ok "  Updated framework hook: $name"
      ((changes++)) || true
    fi
  done

  # Compare scripts (ralph.sh, quality-gate.sh)
  for script in "$source_dir/scripts/"*.sh; do
    [[ ! -f "$script" ]] && continue
    local name
    name=$(basename "$script")
    # Only pull back scripts that exist in the framework
    local framework_file="$FRAMEWORK_DIR/scripts/$name"
    [[ ! -f "$framework_file" ]] && continue

    if ! diff -q "$script" "$framework_file" > /dev/null 2>&1; then
      warn "MODIFIED script: $name"
      cp "$script" "$framework_file"
      chmod +x "$framework_file"
      ok "  Updated framework script: $name"
      ((changes++)) || true
    fi
  done

  echo ""
  if [[ $changes -eq 0 ]]; then
    ok "No changes to pull — framework and project are in sync"
  else
    ok "Pulled $changes change(s) into framework"
    echo ""
    info "Next steps:"
    echo "    cd $FRAMEWORK_DIR"
    echo "    git add -A && git commit -m 'feat: pull changes from $(basename "$source_dir")'"
    echo "    git push origin master"
    echo "    bash scripts/sync.sh push   # propagate to all other projects"
  fi
}

cmd_discover() {
  # Auto-discover projects with .claude-framework submodule in a directory
  local search_dir="${1:-$(dirname "$FRAMEWORK_DIR")}"

  h1 "Discovering projects in $search_dir"
  echo ""

  local found=0
  # Use find with -maxdepth 2 to handle directory names with spaces
  while IFS= read -r -d '' submod_dir; do
    local dir
    dir="$(dirname "$submod_dir")"
    # Don't register the framework itself
    local abs_dir
    abs_dir="$(cd "$dir" && pwd)"
    if [[ "$abs_dir" == "$FRAMEWORK_DIR" ]]; then
      continue
    fi
    cmd_register "$abs_dir"
    ((found++)) || true
  done < <(find "$search_dir" -maxdepth 2 -type d -name ".claude-framework" -print0 2>/dev/null)

  echo ""
  if [[ $found -eq 0 ]]; then
    warn "No projects with .claude-framework found in $search_dir"
  else
    ok "Discovered and registered $found project(s)"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

cmd="${1:-help}"
shift || true

case "$cmd" in
  push)       cmd_push "$@" ;;
  pull)       cmd_pull "$@" ;;
  status)     cmd_status "$@" ;;
  register)   cmd_register "$@" ;;
  unregister) cmd_unregister "$@" ;;
  discover)   cmd_discover "$@" ;;
  help|*)
    echo ""
    echo -e "${BOLD}Hartz Claude Framework — Sync Tool${NC}"
    echo ""
    echo "  Usage: bash scripts/sync.sh <command> [args]"
    echo ""
    echo "  Commands:"
    echo "    status              Show sync status across all registered projects"
    echo "    push                Push framework updates to all projects"
    echo "    pull [project_dir]  Pull changes from a project back into the framework"
    echo "    register [dir]      Register a project (default: current directory)"
    echo "    unregister [dir]    Unregister a project"
    echo "    discover [dir]      Auto-discover and register all projects in a directory"
    echo ""
    echo "  Workflow:"
    echo "    1. Discover projects:   bash scripts/sync.sh discover ~/Projects"
    echo "    2. Check status:        bash scripts/sync.sh status"
    echo "    3. After framework change:"
    echo "       Push to all:         bash scripts/sync.sh push"
    echo "    4. After project-level improvement:"
    echo "       Pull to framework:   bash scripts/sync.sh pull /path/to/project"
    echo "       Then push to all:    bash scripts/sync.sh push"
    echo ""
    ;;
esac
