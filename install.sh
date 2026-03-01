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
  if command -v python3 > /dev/null 2>&1; then
    python3 - <<PYEOF
import json

with open('$SETTINGS_DEST') as f:
    existing = json.load(f)

with open('$SETTINGS_SRC') as f:
    framework = json.load(f)

# Merge env vars
if 'env' not in existing:
    existing['env'] = {}
for key, val in framework.get('env', {}).items():
    existing['env'][key] = val

# Merge hooks — APPEND framework hooks to existing arrays (don't skip or overwrite)
if 'hooks' not in existing:
    existing['hooks'] = {}

for hook_name, hook_entries in framework.get('hooks', {}).items():
    if hook_name not in existing['hooks']:
        # Hook type doesn't exist yet — add it
        existing['hooks'][hook_name] = hook_entries
    else:
        # Hook type already exists — append framework entries if not already present
        existing_commands = set()
        for entry in existing['hooks'][hook_name]:
            # Handle both flat and nested hook formats
            if 'command' in entry:
                existing_commands.add(entry['command'])
            elif 'hooks' in entry:
                for h in entry['hooks']:
                    if 'command' in h:
                        existing_commands.add(h['command'])

        for new_entry in hook_entries:
            # Check if this framework hook is already present
            new_commands = set()
            if 'command' in new_entry:
                new_commands.add(new_entry['command'])
            elif 'hooks' in new_entry:
                for h in new_entry['hooks']:
                    if 'command' in h:
                        new_commands.add(h['command'])

            if not new_commands.intersection(existing_commands):
                existing['hooks'][hook_name].append(new_entry)

with open('$SETTINGS_DEST', 'w') as f:
    json.dump(existing, f, indent=2)
PYEOF
    info "Merged settings into existing settings.json"
  else
    warn "python3 not found — manually add framework hooks to .claude/settings.json"
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
