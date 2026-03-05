# Project Progress

> Updated by Claude after each development session. Human-readable project state.

---

## Current status

**As of:** 2026-03-05
**Active branch:** master
**Open PRDs:** None

---

## What was last worked on

P0+P1 improvements based on autonomous engineering research analysis.

**P0 — CLAUDE.md trim**: Reduced from 470 lines (with @imports) to 82 lines with zero `@` imports. References docs on-demand instead of embedding every turn.

**P1 — Docker isolation**: Added `docker/Dockerfile`, `docker/squid.conf`, `docker/docker-compose.yml`. Ralph loop supports `--docker` flag for running Claude inside network-restricted containers. Squid proxy limits traffic to approved domains only.

**P1 — Session management decision**: Evaluated Claude Squad — it cannot create sessions programmatically (TUI-only). Decision: use tmux + git worktrees directly, Claude Squad as optional monitoring TUI only. Documented in Hartz Land guide.

---

## What's next

1. **Commit all changes** — Large batch from overnight build + P0 + P1
2. **Connect to Hartz Land** — Set up the remote machine, run `setup.sh`
3. **Add GitHub PAT** — Configure GitHub MCP with personal access token
4. **Git worktrees per task** — Replace file-based locks with worktree isolation
5. **Runtime verification** — Test Playwright MCP with a real project's dev server
6. **Hartz Command integration** — Review queue UI, daily digest endpoint, confidence dashboard

---

## Known issues / blockers

- GitHub MCP needs a Personal Access Token (placeholder installed)
- Static verification caps confidence at 0.85 — runtime verification needed for higher scores
- Hartz Land machine not yet connected
- Claude Squad cannot automate session creation — tmux is the automation layer

---

## Recent decisions

- **CLAUDE.md size**: Zero `@` imports; docs referenced on-demand, not loaded every turn
- **Docker isolation**: Squid proxy restricts autonomous agents to approved domains only
- **Session management**: tmux + worktrees for automation; Claude Squad as optional TUI monitor only
- **Verification architecture**: Separate agent verifies work against acceptance criteria with proof packets
- **Confidence thresholds**: 0.9+ = auto-merge, 0.7-0.89 = human review, <0.7 = blocked
- **MCP stack**: Playwright, Memory, Sequential Thinking, GitHub, Filesystem

---

## Session history

| Date | What was done | Stories completed |
|------|---------------|------------------|
| — | Initial setup | — |
| 2026-03-04 | Verification system, Hartz Land scripts, MCP setup, proof packets, review queue | N/A (framework enhancement) |
| 2026-03-05 | P0: CLAUDE.md trim (470→82 lines), P1: Docker isolation, P1: Session mgmt decision | N/A (framework enhancement) |
