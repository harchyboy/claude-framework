#!/usr/bin/env bash
# claude-modes.sh — Mode-based system prompt injection for Claude Code
#
# Source this in your shell profile (~/.bashrc, ~/.zshrc):
#   source /path/to/scripts/claude-modes.sh
#
# Then use mode aliases:
#   claude-dev          Standard development mode (default rules)
#   claude-review       Code review mode (read-only, review-focused)
#   claude-research     Research mode (exploration, no file writes)
#   claude-debug        Debug mode (systematic investigation)
#   claude-lean         Minimal token usage mode
#
# Custom mode:
#   claude-mode custom  Uses ~/.claude/contexts/custom.md

set -euo pipefail

# ─── Context directory ────────────────────────────────────────────────────────

CLAUDE_CONTEXTS_DIR="${CLAUDE_CONTEXTS_DIR:-$HOME/.claude/contexts}"
mkdir -p "$CLAUDE_CONTEXTS_DIR"

# ─── Create default context files if they don't exist ─────────────────────────

if [[ ! -f "$CLAUDE_CONTEXTS_DIR/review.md" ]]; then
  cat > "$CLAUDE_CONTEXTS_DIR/review.md" <<'CTX'
# Code Review Mode

You are in CODE REVIEW mode. Your primary function is to review code, not write it.

## Constraints
- Do NOT create or modify source files unless explicitly asked
- Focus on finding issues, not fixing them
- Rate findings as P1 (critical), P2 (important), P3 (minor)
- Check: correctness, security, performance, readability, test coverage

## Output Format
For each finding:
- **Location:** file:line
- **Severity:** P1/P2/P3
- **Issue:** What's wrong
- **Suggestion:** How to fix (but don't apply it)
CTX
fi

if [[ ! -f "$CLAUDE_CONTEXTS_DIR/research.md" ]]; then
  cat > "$CLAUDE_CONTEXTS_DIR/research.md" <<'CTX'
# Research Mode

You are in RESEARCH mode. Your primary function is to explore and understand, not modify.

## Constraints
- Do NOT create or modify files unless explicitly asked
- Use Read, Grep, Glob, and web search tools freely
- Summarise findings with source references
- Present multiple perspectives on architectural decisions
- Flag assumptions vs verified facts

## Output Format
- Lead with the answer, then supporting evidence
- Cite file paths and line numbers for code references
- Note confidence level: verified / likely / speculative
CTX
fi

if [[ ! -f "$CLAUDE_CONTEXTS_DIR/debug.md" ]]; then
  cat > "$CLAUDE_CONTEXTS_DIR/debug.md" <<'CTX'
# Debug Mode

You are in DEBUG mode. Follow the systematic 4-phase investigation protocol.

## Phase 1: Reproduce
- Confirm the bug exists with a failing test or reproduction steps
- Do NOT guess at causes yet

## Phase 2: Isolate
- Binary search through the call stack
- Find the exact line where behaviour diverges from expectation

## Phase 3: Root Cause
- Identify WHY the bug exists, not just WHERE
- Check for related instances of the same pattern

## Phase 4: Fix + Verify
- Apply minimal fix
- Run tests to confirm the fix
- Check for regressions
CTX
fi

if [[ ! -f "$CLAUDE_CONTEXTS_DIR/lean.md" ]]; then
  cat > "$CLAUDE_CONTEXTS_DIR/lean.md" <<'CTX'
# Lean Mode — Minimal Token Usage

You are in LEAN mode. Optimise for minimal token consumption.

## Constraints
- Keep all responses under 3 sentences unless code is required
- Use Haiku-routed subagents for exploration
- Prefer Grep/Glob over Agent for searches
- No explanations unless asked — just do the work
- Skip preamble, summaries, and status updates
- One tool call at a time when possible (avoid speculative parallel calls)
CTX
fi

# ─── Mode launcher ────────────────────────────────────────────────────────────

claude_mode() {
  local mode="${1:-dev}"
  local context_file="$CLAUDE_CONTEXTS_DIR/${mode}.md"

  if [[ "$mode" == "dev" ]]; then
    # Default mode — no extra system prompt
    claude "${@:2}"
    return
  fi

  if [[ ! -f "$context_file" ]]; then
    echo "Unknown mode: $mode"
    echo "Available: dev, review, research, debug, lean"
    echo "Or create: $context_file"
    return 1
  fi

  claude --system-prompt "$(cat "$context_file")" "${@:2}"
}

# ─── Aliases ──────────────────────────────────────────────────────────────────

alias claude-dev='claude_mode dev'
alias claude-review='claude_mode review'
alias claude-research='claude_mode research'
alias claude-debug='claude_mode debug'
alias claude-lean='claude_mode lean'
