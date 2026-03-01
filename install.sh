#!/bin/bash
# install.sh — Install Hartz Claude Framework into a project
# Usage: bash install.sh [target-project-directory]
#
# Run from inside the .claude-framework directory:
#   cd .claude-framework && bash install.sh ..
#
# Or with explicit target:
#   bash .claude-framework/install.sh /path/to/project

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────

FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$(pwd)}"

# If called from within the framework dir, default to parent
if [[ "$TARGET_DIR" == "$FRAMEWORK_DIR" ]]; then
  TARGET_DIR="$(dirname "$FRAMEWORK_DIR")"
fi

# ─── Colours ─────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $1${NC}"; }
h1()   { echo -e "\n${BOLD}$1${NC}"; }

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
echo "  Framework: $FRAMEWORK_DIR"
echo "  Target:    $TARGET_DIR"
echo ""
read -p "  Install to $TARGET_DIR? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
  echo "Cancelled."
  exit 0
fi

# ─── Create directories ──────────────────────────────────────────────────────

h1 "Creating directories..."

dirs=(
  "$TARGET_DIR/.claude/agents"
  "$TARGET_DIR/.claude/commands"
  "$TARGET_DIR/.claude/hooks"
  "$TARGET_DIR/.claude/skills"
  "$TARGET_DIR/scripts/ralph-moss/prds"
  "$TARGET_DIR/docs/solutions"
  "$TARGET_DIR/docs/architecture"
  "$TARGET_DIR/current_tasks"
  "$TARGET_DIR/agent_logs"
)

for dir in "${dirs[@]}"; do
  mkdir -p "$dir"
  info "Created $dir"
done
ok "Directories created"

# ─── Copy agent definitions ──────────────────────────────────────────────────

h1 "Installing agent definitions..."

for agent in "$FRAMEWORK_DIR/.claude/agents/"*.md; do
  name=$(basename "$agent")
  dest="$TARGET_DIR/.claude/agents/$name"
  if [[ -f "$dest" ]]; then
    warn "Skipping $name (already exists — delete to reinstall)"
  else
    cp "$agent" "$dest"
    info "Installed agent: $name"
  fi
done
ok "Agent definitions installed"

# ─── Copy commands ───────────────────────────────────────────────────────────

h1 "Installing slash commands..."

for cmd in "$FRAMEWORK_DIR/.claude/commands/"*.md; do
  name=$(basename "$cmd")
  dest="$TARGET_DIR/.claude/commands/$name"
  if [[ -f "$dest" ]]; then
    warn "Skipping $name (already exists)"
  else
    cp "$cmd" "$dest"
    info "Installed command: /$( basename "$name" .md)"
  fi
done
ok "Slash commands installed"

# ─── Copy hooks ──────────────────────────────────────────────────────────────

h1 "Installing hooks..."

for hook in "$FRAMEWORK_DIR/.claude/hooks/"*.sh; do
  name=$(basename "$hook")
  dest="$TARGET_DIR/.claude/hooks/$name"
  cp "$hook" "$dest"
  chmod +x "$dest"
  info "Installed hook: $name"
done
ok "Hooks installed"

# ─── Copy/merge settings.json ────────────────────────────────────────────────

h1 "Configuring Claude Code settings..."

SETTINGS_DEST="$TARGET_DIR/.claude/settings.json"
SETTINGS_SRC="$FRAMEWORK_DIR/.claude/settings.json"

if [[ -f "$SETTINGS_DEST" ]]; then
  # Merge framework hooks into existing settings (appends, doesn't overwrite)
  if command -v node > /dev/null 2>&1; then
    # Convert MSYS paths to Windows paths for node
    local sd_path="$SETTINGS_DEST"
    local ss_path="$SETTINGS_SRC"
    if command -v cygpath > /dev/null 2>&1; then
      sd_path="$(cygpath -w "$SETTINGS_DEST")"
      ss_path="$(cygpath -w "$SETTINGS_SRC")"
    fi
    node -e "
const fs = require('fs');
const existing = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
const framework = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

if (!existing.env) existing.env = {};
for (const [key, val] of Object.entries(framework.env || {})) {
  existing.env[key] = val;
}

if (!existing.hooks) existing.hooks = {};
for (const [hookName, hookEntries] of Object.entries(framework.hooks || {})) {
  if (!existing.hooks[hookName]) {
    existing.hooks[hookName] = hookEntries;
  } else {
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

fs.writeFileSync(process.argv[1], JSON.stringify(existing, null, 2));
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

h1 "Installing scripts..."

for script in "$FRAMEWORK_DIR/scripts/"*.sh; do
  name=$(basename "$script")
  dest="$TARGET_DIR/scripts/$name"
  if [[ -f "$dest" ]]; then
    warn "Skipping $name (already exists)"
  else
    cp "$script" "$dest"
    chmod +x "$dest"
    info "Installed: scripts/$name"
  fi
done
ok "Scripts installed"

# ─── CLAUDE.md ───────────────────────────────────────────────────────────────

h1 "Setting up CLAUDE.md..."

CLAUDE_MD="$TARGET_DIR/CLAUDE.md"

if [[ -f "$CLAUDE_MD" ]]; then
  # Check if it already has the framework header
  if grep -q "Hartz Claude Framework" "$CLAUDE_MD" 2>/dev/null; then
    warn "CLAUDE.md already contains framework content — skipping"
  else
    # Prepend framework content, keep existing content at the bottom
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
  # Update date
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

# Note: current_tasks/ should be tracked by git (it's the coordination mechanism)
ok ".gitignore updated"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   Installation complete ✅                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
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
echo ""
echo "  Docs: https://github.com/hartz-ai/claude-framework"
echo ""
