#!/bin/bash
# install.sh — Install Hartz Claude Framework into a project
#
# Usage:
#   bash install.sh [command] [target-directory] [options]
#
# Commands:
#   init      Fresh install (default if no .framework-version exists)
#   update    Update existing installation (default if .framework-version exists)
#   eject     Copy everything and remove submodule dependency
#   version   Show installed and available framework versions
#
# Options:
#   --no-hooks       Skip hook installation
#   --no-agents      Skip agent installation
#   --no-scripts     Skip script installation
#   --no-ci          Skip GitHub Actions workflow
#   --force          Overwrite existing files (normally skipped)
#   --yes            Skip confirmation prompt
#
# Examples:
#   cd .claude-framework && bash install.sh ..
#   bash .claude-framework/install.sh /path/to/project
#   bash install.sh update .. --force
#   bash install.sh eject /path/to/project

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_VERSION=$(cd "$FRAMEWORK_DIR" && git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
FRAMEWORK_VERSION_FULL=$(cd "$FRAMEWORK_DIR" && git log -1 --format="%h %s" 2>/dev/null || echo "unknown")
VERSION_FILE=".claude/.framework-version"

# ─── Parse command and args ──────────────────────────────────────────────────

COMMAND=""
TARGET_DIR=""
INSTALL_HOOKS=true
INSTALL_AGENTS=true
INSTALL_SCRIPTS=true
INSTALL_CI=true
FORCE=false
AUTO_YES=false

# First pass: extract command and target
for arg in "$@"; do
  case "$arg" in
    init|update|eject|version) COMMAND="$arg" ;;
    --no-hooks)    INSTALL_HOOKS=false ;;
    --no-agents)   INSTALL_AGENTS=false ;;
    --no-scripts)  INSTALL_SCRIPTS=false ;;
    --no-ci)       INSTALL_CI=false ;;
    --force)       FORCE=true ;;
    --yes|-y)      AUTO_YES=true ;;
    --*)           ;; # ignore unknown flags
    *)
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$arg"
      fi
      ;;
  esac
done

# Default target
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$(pwd)"
fi

# If called from within the framework dir, default to parent
if [[ "$TARGET_DIR" == "$FRAMEWORK_DIR" ]]; then
  TARGET_DIR="$(dirname "$FRAMEWORK_DIR")"
fi

# Auto-detect command based on version file
if [[ -z "$COMMAND" ]]; then
  if [[ -f "$TARGET_DIR/$VERSION_FILE" ]]; then
    COMMAND="update"
  else
    COMMAND="init"
  fi
fi

# ─── Colours ─────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
h1()   { echo -e "\n${BOLD}$1${NC}"; }

# ─── Version command ─────────────────────────────────────────────────────────

if [[ "$COMMAND" == "version" ]]; then
  echo "Framework: $FRAMEWORK_VERSION_FULL"
  if [[ -f "$TARGET_DIR/$VERSION_FILE" ]]; then
    echo "Installed: $(cat "$TARGET_DIR/$VERSION_FILE")"
  else
    echo "Installed: not installed"
  fi
  exit 0
fi

# ─── Validate ────────────────────────────────────────────────────────────────

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: Target directory does not exist: $TARGET_DIR"
  exit 1
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Hartz Claude Framework — Installer     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  Command:   $COMMAND"
echo "  Framework: $FRAMEWORK_DIR ($FRAMEWORK_VERSION)"
echo "  Target:    $TARGET_DIR"

if [[ -f "$TARGET_DIR/$VERSION_FILE" ]]; then
  INSTALLED_VERSION=$(cat "$TARGET_DIR/$VERSION_FILE")
  echo "  Installed: $INSTALLED_VERSION"
fi

echo ""

if [[ "$COMMAND" == "update" ]]; then
  echo "  Components to update:"
  [[ "$INSTALL_AGENTS" == "true" ]]  && echo "    ✓ Agents"   || echo "    ✗ Agents (skipped)"
  [[ "$INSTALL_HOOKS" == "true" ]]   && echo "    ✓ Hooks"    || echo "    ✗ Hooks (skipped)"
  [[ "$INSTALL_SCRIPTS" == "true" ]] && echo "    ✓ Scripts"  || echo "    ✗ Scripts (skipped)"
  [[ "$INSTALL_CI" == "true" ]]      && echo "    ✓ CI"       || echo "    ✗ CI (skipped)"
  [[ "$FORCE" == "true" ]]           && echo "    ⚠ Force overwrite: ON"
  echo ""
fi

if [[ "$AUTO_YES" != "true" ]]; then
  read -p "  Proceed with $COMMAND? (Y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

# ─── Helper: copy file (respects --force) ────────────────────────────────────

copy_file() {
  local src="$1"
  local dest="$2"
  local label="${3:-$(basename "$src")}"

  if [[ -f "$dest" ]] && [[ "$FORCE" != "true" ]]; then
    warn "Skipping $label (already exists — use --force to overwrite)"
    return 1
  fi

  cp "$src" "$dest"
  info "Installed: $label"
  return 0
}

# ─── Create directories ──────────────────────────────────────────────────────

h1 "Creating directories..."

dirs=(
  "$TARGET_DIR/.claude/agents"
  "$TARGET_DIR/.claude/commands"
  "$TARGET_DIR/.claude/hooks"
  "$TARGET_DIR/.claude/skills"
  "$TARGET_DIR/.claude/docs"
  "$TARGET_DIR/scripts/ralph-moss/prds"
  "$TARGET_DIR/docs/solutions"
  "$TARGET_DIR/docs/architecture"
  "$TARGET_DIR/current_tasks"
  "$TARGET_DIR/agent_logs"
)

for dir in "${dirs[@]}"; do
  mkdir -p "$dir"
done
ok "Directories created"

# ─── Copy agent definitions ──────────────────────────────────────────────────

if [[ "$INSTALL_AGENTS" == "true" ]]; then
  h1 "Installing agent definitions..."

  for agent in "$FRAMEWORK_DIR/.claude/agents/"*.md; do
    name=$(basename "$agent")
    copy_file "$agent" "$TARGET_DIR/.claude/agents/$name" "agent: $name" || true
  done
  ok "Agent definitions installed"
fi

# ─── Copy commands ───────────────────────────────────────────────────────────

h1 "Installing slash commands..."

for cmd in "$FRAMEWORK_DIR/.claude/commands/"*.md; do
  name=$(basename "$cmd")
  copy_file "$cmd" "$TARGET_DIR/.claude/commands/$name" "command: /$(basename "$name" .md)" || true
done
ok "Slash commands installed"

# ─── Copy hooks ──────────────────────────────────────────────────────────────

if [[ "$INSTALL_HOOKS" == "true" ]]; then
  h1 "Installing hooks..."

  for hook in "$FRAMEWORK_DIR/.claude/hooks/"*.sh; do
    name=$(basename "$hook")
    dest="$TARGET_DIR/.claude/hooks/$name"
    cp "$hook" "$dest"
    chmod +x "$dest"
    info "Installed hook: $name"
  done
  ok "Hooks installed"
fi

# ─── Copy CLAUDE.md imported modules ────────────────────────────────────────

h1 "Installing CLAUDE.md modules..."

if [[ -d "$FRAMEWORK_DIR/.claude/docs" ]]; then
  for doc in "$FRAMEWORK_DIR/.claude/docs/"*.md; do
    [[ ! -f "$doc" ]] && continue
    name=$(basename "$doc")
    cp "$doc" "$TARGET_DIR/.claude/docs/$name"
    info "Installed module: $name"
  done
fi
ok "CLAUDE.md modules installed"

# ─── Copy/merge settings.json ────────────────────────────────────────────────

h1 "Configuring Claude Code settings..."

SETTINGS_DEST="$TARGET_DIR/.claude/settings.json"
SETTINGS_SRC="$FRAMEWORK_DIR/.claude/settings.json"

if [[ -f "$SETTINGS_DEST" ]]; then
  # Merge framework hooks into existing settings (appends, doesn't overwrite)
  if command -v node > /dev/null 2>&1; then
    # Convert MSYS paths to Windows paths for node
    sd_path="$SETTINGS_DEST"
    ss_path="$SETTINGS_SRC"
    if command -v cygpath > /dev/null 2>&1; then
      sd_path="$(cygpath -w "$SETTINGS_DEST")"
      ss_path="$(cygpath -w "$SETTINGS_SRC")"
    fi
    node -e "
const fs = require('fs');
const existing = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const framework = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

// Normalize old-format object matchers to strings
function normalizeMatcher(entry) {
  if (entry.matcher && typeof entry.matcher === 'object') {
    entry.matcher = entry.matcher.tool_name || '';
  }
}

if (!existing.env) existing.env = {};
for (const [key, val] of Object.entries(framework.env || {})) {
  existing.env[key] = val;
}

if (!existing.hooks) existing.hooks = {};

// Remove Stop hooks — they cause infinite loops (Stop fires after every turn,
// hook output becomes a message, Claude responds, turn ends, Stop fires again)
delete existing.hooks.Stop;

for (const [hookName, hookEntries] of Object.entries(framework.hooks || {})) {
  if (!existing.hooks[hookName]) {
    existing.hooks[hookName] = hookEntries;
  } else {
    // Fix old-format matchers on existing entries
    existing.hooks[hookName].forEach(normalizeMatcher);
    const existingCmds = new Set();
    for (const entry of existing.hooks[hookName]) {
      if (entry.command) existingCmds.add(entry.command);
      if (entry.hooks) entry.hooks.forEach(h => { if (h.command) existingCmds.add(h.command); });
    }
    for (const newEntry of hookEntries) {
      const newCmds = new Set();
      if (newEntry.command) newCmds.add(newEntry.command);
      if (newEntry.hooks) newEntry.hooks.forEach(h => { if (h.command) newCmds.add(h.command); });
      const overlap = [...newCmds].some(c => existingCmds.has(c));
      if (!overlap) existing.hooks[hookName].push(newEntry);
    }
  }
}

fs.writeFileSync(process.argv[1], JSON.stringify(existing, null, 2) + '\\n');
" "$sd_path" "$ss_path"
    info "Merged settings into existing settings.json"
  else
    warn "node not found — manually add framework hooks to .claude/settings.json"
  fi
else
  cp "$SETTINGS_SRC" "$SETTINGS_DEST"
  info "Created .claude/settings.json"
fi
ok "Settings configured"

# ─── Copy scripts ────────────────────────────────────────────────────────────

if [[ "$INSTALL_SCRIPTS" == "true" ]]; then
  h1 "Installing scripts..."

  for script in "$FRAMEWORK_DIR/scripts/"*.sh; do
    name=$(basename "$script")
    dest="$TARGET_DIR/scripts/$name"
    if copy_file "$script" "$dest" "scripts/$name"; then
      chmod +x "$dest"
    fi
  done
  ok "Scripts installed"
fi

# ─── CLAUDE.md ───────────────────────────────────────────────────────────────

h1 "Setting up CLAUDE.md..."

CLAUDE_MD="$TARGET_DIR/CLAUDE.md"

if [[ -f "$CLAUDE_MD" ]]; then
  if grep -q "Hartz Claude Framework" "$CLAUDE_MD" 2>/dev/null; then
    if [[ "$FORCE" == "true" ]]; then
      cp "$FRAMEWORK_DIR/CLAUDE.md" "$CLAUDE_MD"
      info "Force-updated CLAUDE.md"
    else
      warn "CLAUDE.md already contains framework content — skipping (use --force to overwrite)"
    fi
  else
    warn "CLAUDE.md already exists — creating CLAUDE.md.framework-template"
    cp "$FRAMEWORK_DIR/CLAUDE.md" "$TARGET_DIR/CLAUDE.md.framework-template"
    info "Review CLAUDE.md.framework-template and merge manually"
  fi
else
  cp "$FRAMEWORK_DIR/CLAUDE.md" "$CLAUDE_MD"
  info "Created CLAUDE.md"
  warn "Edit CLAUDE.md — replace [REPLACE: ...] placeholders with your project details"
fi
ok "CLAUDE.md ready"

# ─── PROGRESS.md ─────────────────────────────────────────────────────────────

h1 "Setting up PROGRESS.md..."

PROGRESS_MD="$TARGET_DIR/PROGRESS.md"
if [[ ! -f "$PROGRESS_MD" ]]; then
  cp "$FRAMEWORK_DIR/PROGRESS.md" "$PROGRESS_MD"
  sed -i "s/\[DATE\]/$(date '+%Y-%m-%d')/" "$PROGRESS_MD" 2>/dev/null || true
  info "Created PROGRESS.md"
else
  warn "PROGRESS.md already exists — skipping"
fi
ok "PROGRESS.md ready"

# ─── docs/failed-approaches.md ───────────────────────────────────────────────

FAILED_APPROACHES="$TARGET_DIR/docs/failed-approaches.md"
if [[ ! -f "$FAILED_APPROACHES" ]]; then
  cp "$FRAMEWORK_DIR/docs/failed-approaches.md" "$FAILED_APPROACHES"
  info "Created docs/failed-approaches.md"
fi

# ─── GitHub Actions workflow ─────────────────────────────────────────────────

if [[ "$INSTALL_CI" == "true" ]]; then
  h1 "Installing CI template..."

  if [[ -d "$FRAMEWORK_DIR/.github/workflows" ]]; then
    mkdir -p "$TARGET_DIR/.github/workflows"
    for wf in "$FRAMEWORK_DIR/.github/workflows/"*.yml; do
      [[ ! -f "$wf" ]] && continue
      name=$(basename "$wf")
      copy_file "$wf" "$TARGET_DIR/.github/workflows/$name" "workflow: $name" || true
    done
  fi
  ok "CI template installed"
fi

# ─── .gitignore ──────────────────────────────────────────────────────────────

h1 "Updating .gitignore..."

GITIGNORE="$TARGET_DIR/.gitignore"
ENTRIES=(
  "# Hartz Claude Framework"
  "agent_logs/"
  ".ralph_prompt_*"
)

for entry in "${ENTRIES[@]}"; do
  if [[ -f "$GITIGNORE" ]]; then
    if ! grep -qF "$entry" "$GITIGNORE" 2>/dev/null; then
      echo "$entry" >> "$GITIGNORE"
      info "Added to .gitignore: $entry"
    fi
  else
    echo "$entry" >> "$GITIGNORE"
    info "Created .gitignore with: $entry"
  fi
done
ok ".gitignore updated"

# ─── Write version file ─────────────────────────────────────────────────────

echo "$FRAMEWORK_VERSION_FULL" > "$TARGET_DIR/$VERSION_FILE"
ok "Version tracked: $FRAMEWORK_VERSION"

# ─── Eject (remove submodule dependency) ─────────────────────────────────────

if [[ "$COMMAND" == "eject" ]]; then
  h1 "Ejecting from framework submodule..."

  SUBMODULE_PATH=""
  if [[ -f "$TARGET_DIR/.gitmodules" ]]; then
    SUBMODULE_PATH=$(grep -A2 "claude-framework\|claude_framework" "$TARGET_DIR/.gitmodules" 2>/dev/null | grep "path" | head -1 | sed 's/.*path = //' || true)
  fi

  if [[ -n "$SUBMODULE_PATH" ]] && [[ -d "$TARGET_DIR/$SUBMODULE_PATH" ]]; then
    cd "$TARGET_DIR"
    git submodule deinit -f "$SUBMODULE_PATH" 2>/dev/null || true
    git rm -f "$SUBMODULE_PATH" 2>/dev/null || true
    rm -rf ".git/modules/$SUBMODULE_PATH" 2>/dev/null || true
    ok "Submodule removed: $SUBMODULE_PATH"
    warn "All framework files are now standalone — updates must be applied manually"
  else
    warn "No framework submodule found — already standalone"
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
if [[ "$COMMAND" == "eject" ]]; then
  echo -e "${BOLD}║   Eject complete ✅                       ║${NC}"
elif [[ "$COMMAND" == "update" ]]; then
  echo -e "${BOLD}║   Update complete ✅                      ║${NC}"
else
  echo -e "${BOLD}║   Installation complete ✅                ║${NC}"
fi
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

if [[ "$COMMAND" == "init" ]]; then
  echo "  Next steps:"
  echo ""
  echo "  1. Edit CLAUDE.md — replace [REPLACE: ...] with your project details"
  echo "     $CLAUDE_MD"
  echo ""
  echo "  2. Create your first PRD:"
  echo "     Open Claude Code and run: /prd [describe your feature]"
  echo ""
  echo "  3. Run autonomously:"
  echo "     bash scripts/ralph.sh --max-plan --quality-gate"
  echo ""
  echo "  4. Review your work:"
  echo "     Open Claude Code and run: /review"
elif [[ "$COMMAND" == "update" ]]; then
  echo "  Updated to: $FRAMEWORK_VERSION_FULL"
  echo ""
  echo "  Check for breaking changes: https://github.com/harchyboy/claude-framework/releases"
elif [[ "$COMMAND" == "eject" ]]; then
  echo "  Framework files are now standalone in your project."
  echo "  You can safely delete the .claude-framework directory."
  echo "  To get future updates, re-add the submodule: git submodule add <url>"
fi
echo ""
echo "  Docs: https://github.com/harchyboy/claude-framework"
echo ""
