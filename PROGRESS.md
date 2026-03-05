# Project Progress

> Updated by Claude after each development session. Human-readable project state.

---

## Current status

**As of:** 2026-03-05
**Active branch:** master
**Open PRDs:** None

---

## What was last worked on

P2+P3 improvements: git worktrees, context management, local model routing.

**P2 — Git worktrees**: Replaced file-based task locks (`current_tasks/`) with git worktrees (`.worktrees/<story-id>`). Each Ralph iteration creates an isolated worktree, runs Claude inside it, merges back on completion. No more stale lock files or file conflicts between agents.

**P2 — Context management**: Added previous-iteration context injection to agent prompts. Agents now receive info about what the last iteration did. Added context management instructions to the prompt ("update PROGRESS.md if context is getting large").

**P3 — Local model routing**: Created `scripts/local-model.sh` — routes prompts to Ollama (default: qwen2.5-coder:7b) with automatic Claude fallback. For test generation, docs, lint fixes. Updated model routing table in CLAUDE.md.

---

## What's next

1. **Connect to Hartz Land** — Set up the remote machine, run `setup.sh`
2. **Add GitHub PAT** — Configure GitHub MCP with personal access token
3. **Install Ollama** — Set up local model for cost-optimized subtasks
4. **Runtime verification** — Test Playwright MCP with a real project's dev server
5. **Hartz Command integration** — Review queue UI, daily digest endpoint, confidence dashboard
6. **Test worktree workflow** — Run Ralph loop end-to-end with worktree isolation

---

## Known issues / blockers

- GitHub MCP needs a Personal Access Token (placeholder installed)
- Static verification caps confidence at 0.85 — runtime verification needed for higher scores
- Hartz Land machine not yet connected
- Claude Squad cannot automate session creation — tmux is the automation layer
- Ollama not yet installed — local-model.sh falls back to Claude gracefully

---

## Recent decisions

- **CLAUDE.md size**: Zero `@` imports; docs referenced on-demand, not loaded every turn
- **Docker isolation**: Squid proxy restricts autonomous agents to approved domains only
- **Session management**: tmux + worktrees for automation; Claude Squad as optional TUI monitor only
- **Verification architecture**: Separate agent verifies work against acceptance criteria with proof packets
- **Confidence thresholds**: 0.9+ = auto-merge, 0.7-0.89 = human review, <0.7 = blocked
- **Git worktrees**: Replace file locks with worktree-per-story isolation in Ralph loop
- **Local models**: Ollama + qwen2.5-coder:7b for routine subtasks, auto-fallback to Claude
- **MCP stack**: Playwright, Memory, Sequential Thinking, GitHub, Filesystem

---

## Session history

| Date | What was done | Stories completed |
|------|---------------|------------------|
| — | Initial setup | — |
| 2026-03-04 | Verification system, Hartz Land scripts, MCP setup, proof packets, review queue | N/A (framework enhancement) |
| 2026-03-05 | P0: CLAUDE.md trim, P1: Docker isolation, P1: Session mgmt, P2: Worktrees, P2: Context mgmt, P3: Local models | N/A (framework enhancement) |
