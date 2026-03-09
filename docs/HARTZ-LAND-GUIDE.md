# Hartz Land — Agent Farm Guide

Hartz Land is a dedicated machine (or external drive) where Claude agents live and work autonomously. While you sleep, agents pick up stories, implement them, verify them, and queue results for your morning review.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   HARTZ COMMAND                      │
│              (Dashboard / Control Tower)              │
│                                                       │
│  React + Express + SQLite + WebSocket                │
│  Your primary machine or web-accessible              │
└──────────────────────┬──────────────────────────────┘
                       │ HTTP + WebSocket
┌──────────────────────┴──────────────────────────────┐
│                    HARTZ LAND                         │
│               (Agent Farm / External Machine)         │
│                                                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ Project A    │  │ Project B    │  │ Project C    │ │
│  │ Ralph Loop   │  │ Ralph Loop   │  │ Ralph Loop   │ │
│  │ + Verify     │  │ + Verify     │  │ + Verify     │ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                       │
│  Shared: Memory MCP, Proof Packets, Review Queue     │
└─────────────────────────────────────────────────────┘
```

## First-Time Setup

```bash
# On the Hartz Land machine
cd ~/Documents/Projects/hartz-claude-framework
bash scripts/hartz-land/setup.sh
```

This will:
1. Check prerequisites (Node, Git, Claude CLI)
2. Discover and register all projects
3. Install MCPs (Playwright, Memory, GitHub, etc.)
4. Install Playwright browsers
5. Create the Hartz Land configuration

## Daily Operations

### Start all agents
```bash
bash scripts/hartz-land/start-all.sh
```

Options:
- `--max-iterations 30` — More iterations per project
- `--model claude-sonnet-4-6` — Override model
- `--verify` — Enable verification after each story
- `--max-concurrent 3` — Limit parallel Ralph loops
- `--dry-run` — Preview what would start

### Monitor progress
```bash
# One-time check
bash scripts/hartz-land/monitor.sh

# Continuous monitoring (updates every 30s)
bash scripts/hartz-land/monitor.sh --watch

# JSON output (for Hartz Command integration)
bash scripts/hartz-land/monitor.sh --json
```

### Monitor from Claude Code (recommended for interactive sessions)
```bash
# Lightweight pulse check every 5 minutes — reports only what changed
/loop 5m /babysit

# Full status briefing every 10 minutes
/loop 10m /status

# Watch a specific PR's CI checks
/loop 5m gh pr checks 42
```

`/babysit` is purpose-built for `/loop` — it uses a compact, exception-based
format that stays quiet when everything is healthy.

### Morning review
```bash
# Daily digest of overnight activity
bash scripts/hartz-land/daily-digest.sh

# Review queue
bash scripts/hartz-land/review-queue.sh list

# Auto-approve high-confidence items
bash scripts/hartz-land/review-queue.sh auto-approve

# Approve specific story
bash scripts/hartz-land/review-queue.sh approve US-001

# Reject (queue for rework)
bash scripts/hartz-land/review-queue.sh reject US-003
```

### Stop all agents
```bash
bash scripts/hartz-land/stop-all.sh

# Force stop
bash scripts/hartz-land/stop-all.sh --force

# Stop specific project
bash scripts/hartz-land/stop-all.sh --project my-project
```

## Verification Flow

When `--verify` is enabled, each completed story goes through:

1. **Static verification** — Tests pass? TypeScript compiles? Acceptance criteria addressed?
2. **Proof packet generation** — Evidence collected in `proof/<story-id>/`
3. **Confidence scoring** — 0.0 to 1.0 based on evidence strength
4. **Review queue** — Added to `~/.hartz-claude-framework/review-queue/`

### Confidence thresholds
| Score | Meaning | Action |
|-------|---------|--------|
| 0.9+  | High — all criteria verified with evidence | Auto-merge candidate |
| 0.7–0.89 | Medium — mostly verified, minor gaps | Queue for human review |
| < 0.7 | Low — failures or insufficient evidence | Block until reviewed |

### Proof packet contents
```
proof/US-001/
├── criteria.md        # Original acceptance criteria from PRD
├── diff.patch         # Code changes for this story
├── test-results.txt   # Test suite output
├── verification.md    # Detailed verification report
├── verdict.json       # Machine-readable pass/fail + confidence
└── screenshots/       # Evidence screenshots (runtime verification)
```

## File Locations

| Path | Purpose |
|------|---------|
| `~/.hartz-claude-framework/hartz-land.json` | Machine configuration |
| `~/.hartz-claude-framework/projects.txt` | Project registry |
| `~/.hartz-claude-framework/review-queue/` | Pending review items |
| `~/.hartz-claude-framework/logs/` | Agent output logs |
| `~/.hartz-claude-framework/pids/` | Running process IDs |
| `~/.hartz-claude-framework/shared-memory.jsonl` | Shared knowledge graph |

## MCP Servers

Hartz Land uses these MCPs (installed via `setup-mcps.sh`):

| MCP | Purpose |
|-----|---------|
| **Playwright** | Runtime verification — browser automation |
| **Memory** | Cross-session knowledge graph |
| **GitHub** | PR creation, CI monitoring |
| **Filesystem** | Cross-project file access |
| **Sequential Thinking** | Structured reasoning for complex tasks |

## Keeping Machines in Sync

Projects sync via Git. The framework syncs via `sync.sh`:

```bash
# On primary machine: push framework updates
bash scripts/sync.sh push

# On Hartz Land: pull updates
git pull
bash scripts/sync.sh pull

# Or let start-all.sh handle it (it runs git pull on each project)
```

## Docker Isolation

For autonomous agents running with `--dangerously-skip-permissions`, Docker provides network isolation via a Squid proxy that restricts traffic to approved domains only.

```bash
# Run Ralph loop in Docker
bash scripts/ralph.sh --docker --quality-gate --verify

# Or via docker-compose directly
WORKSPACE=./my-project PROMPT="Implement US-001" \
  docker compose -f docker/docker-compose.yml run --rm agent
```

Docker isolation includes:
- **Network proxy** — agents can only reach GitHub, npm, Anthropic, PyPI, Supabase, Vercel, Netlify
- **Resource limits** — 2 CPUs, 4GB RAM per container
- **Non-root user** — agents run as `agent` user inside the container

Build the image first: `docker compose -f docker/docker-compose.yml build`

## Session Management

We use **tmux + git worktrees** for running multiple agents in parallel. Each agent gets its own tmux session and worktree, preventing file conflicts.

Claude Squad (`cs`) can optionally be used as a monitoring TUI on top of tmux sessions, but is not required for automation. It cannot create sessions programmatically — tmux handles that directly.

```bash
# Manual multi-agent setup with tmux
tmux new-session -d -s project-a "cd /path/to/project-a && bash scripts/ralph.sh --verify"
tmux new-session -d -s project-b "cd /path/to/project-b && bash scripts/ralph.sh --verify"

# Monitor with Claude Squad (optional)
cs  # TUI shows existing tmux sessions
```

## Troubleshooting

**Agent stuck / not progressing**
```bash
# Check logs
tail -f ~/.hartz-claude-framework/logs/<project>_*.log

# Check for stale locks
ls -la <project>/current_tasks/

# Force stop and restart
bash scripts/hartz-land/stop-all.sh --project <name>
bash scripts/hartz-land/start-all.sh --project <name>
```

**No active PRDs**
Ralph requires a PRD with pending stories. Create one:
```bash
cd <project>
# Open Claude Code and run /prd to generate a PRD
```

**Verification always returns low confidence**
Static verification caps confidence at 0.85. For higher confidence, enable runtime verification:
```bash
bash scripts/hartz-land/start-all.sh --verify-runtime --dev-cmd "npm run dev"
```
