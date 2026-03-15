# Project Progress

> Updated by Claude after each development session. Human-readable project state.

---

## Current status

**As of:** 2026-03-15
**Active branch:** ralph/US-006
**Open PRDs:** ralph-symphony-upgrades (6 stories, 6 complete)

---

## What was last worked on

**US-006: Dynamic config reload — change settings mid-run** — Added `load_dynamic_config()` function to ralph.sh. At each iteration start, checks `$PRD_DIR/ralph-config.json` for setting changes. Uses file mtime for efficient change detection (skips re-parse if unchanged). Reloadable settings: model, timeout, quality_gate, strict, skip_tests, review, max_cost, stall_timeout. Non-reloadable (launch only): telemetry, telemetry_url, docker, hooks_dir. Malformed JSON keeps previous config with warning. Missing config file is a silent no-op. Logs each changed setting with old/new values. Uses node for JSON parsing, grep for value extraction. 31 tests added.

Previous: US-005 — Proof packets (collect_proof_packet, always-on evidence, 43 tests).

Previous: US-004 — Exponential backoff (calculate_backoff, backoff_sleep, --no-backoff, 22 tests).

Previous: US-003 — Stall detection (start_stall_watchdog, --stall-timeout, 18 tests).

Previous: US-002 — Continuation prompts (build_continuation_prompt, retry detection, 17 tests).

Previous: US-001 — Workspace lifecycle hooks (run_hook, --hooks-dir, 4 hook points, 21 tests).

Previous: Track 3 — automation pipeline, tmux orchestration, shared memory.

**Auto-PR pipeline**: Added `--auto-pr` and `--pr-threshold` flags to ralph.sh. After verification passes with confidence >= threshold (default 0.9), automatically creates a GitHub PR via `gh pr create` with story info, acceptance criteria, and proof packet summary. Includes branch push, duplicate PR detection, and telemetry.

**tmux orchestration**: Rewrote start-all.sh to use tmux sessions instead of background processes. Each project gets `hartz-<name>` session. `tmux attach` to watch agents work in real-time. Updated stop-all.sh (sends Ctrl-C for graceful shutdown, falls back to kill-session) and monitor.sh (detects tmux sessions, shows last log line, displays attach commands).

**Shared Memory MCP**: Reconfigured Memory MCP to persist to `~/.hartz-claude-framework/shared-memory.json`. Knowledge graph now shared across all projects and sessions.

---

## What's next

1. **Install Docker Desktop + Ollama** — User is installing; verify once done
2. **Runtime verification** — Test Playwright MCP with a real project's dev server
3. **E2E test with auto-PR** — Run Ralph loop with `--verify --auto-pr` on a real project
4. **Hartz Command integration** — Review queue UI, daily digest endpoint, confidence dashboard
5. **Multi-machine sync** — Test Hartz Land setup on external drive / remote machine

---

## Known issues / blockers

- Static verification caps confidence at 0.85 — runtime verification needed for higher scores
- Hartz Land machine not yet connected
- Docker Desktop + Ollama pending user installation
- tmux required on Hartz Land machine (start-all.sh dependency)

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
| 2026-03-05 | MCPs installed (Playwright, Memory, Filesystem, GitHub w/ PAT), E2E test on hartzai-website (3 bugs fixed), Track 3: auto-PR, tmux orchestration, shared memory | N/A (framework enhancement) |
| 2026-03-15 | US-001: Workspace lifecycle hooks — run_hook(), --hooks-dir, 4 hook points, 21 tests | US-001 |
| 2026-03-15 | US-002: Continuation prompts — build_continuation_prompt(), retry detection, token savings, 17 tests | US-002 |
| 2026-03-15 | US-003: Stall detection — start_stall_watchdog(), --stall-timeout, log mtime monitoring, grace period, 18 tests | US-003 |
| 2026-03-15 | US-004: Exponential backoff — calculate_backoff(), backoff_sleep(), --no-backoff, interruptible sleep, 22 tests | US-004 |
| 2026-03-15 | US-005: Proof packets — collect_proof_packet(), always-on evidence collection, git stats, quality gate fields, telemetry POST, 43 tests | US-005 |
| 2026-03-15 | US-006: Dynamic config reload — load_dynamic_config(), mtime-based change detection, 8 reloadable settings, malformed JSON handling, 31 tests | US-006 |
