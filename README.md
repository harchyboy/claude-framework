# Hartz Claude Framework

> Production-grade Claude Code orchestration framework. Installs as a git submodule, standardises how Claude Code runs across all your projects.

Synthesised from 8 community orchestration tools and enhanced with context engineering techniques from [superpowers](https://github.com/obra/superpowers), [planning-with-files](https://github.com/OthmanAdi/planning-with-files), and [awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents).

---

## What this gives you

| Category | What you get |
|----------|-------------|
| **CLAUDE.md** | Universal behavioural rules, model routing, anti-rationalization tables, coordination logic — Claude reads this on every session |
| **7 review agents** | Parallel specialist reviewers: spec-compliance, security, TypeScript, architecture, performance, data integrity, accessibility — all read-only |
| **5 slash commands** | `/prd`, `/review`, `/compound`, `/task`, `/bugfix` for the full build → review → learn loop |
| **5 automated hooks** | Session context injection, attention anchoring, completion gating, quality enforcement, idle task assignment |
| **Ralph loop** | Autonomous PRD-driven development — git-coordinated, quality-gated, runs unattended |
| **Bi-directional sync** | One command pushes framework updates to all projects; another pulls improvements back |
| **Session recovery** | Parses Claude Code's internal session files to recover context after `/clear` or compaction |
| **Learnings system** | `docs/solutions/` with YAML-frontmatter searchable knowledge base + `docs/failed-approaches.md` to prevent retrying known failures |

---

## Quick install

```bash
# Add as a submodule
git submodule add https://github.com/harchyboy/claude-framework .claude-framework

# Run the installer
bash .claude-framework/install.sh .

# Edit CLAUDE.md — replace [REPLACE: ...] placeholders with your project details

# Register with the sync system
bash scripts/sync.sh register
```

### What install.sh does

- Copies `.claude/agents/`, `.claude/commands/`, `.claude/hooks/` into your project
- Creates `CLAUDE.md` (or merges with existing)
- Merges framework hooks into `.claude/settings.json` (appends, never overwrites existing hooks)
- Creates `PROGRESS.md`, `docs/solutions/`, `docs/failed-approaches.md`
- Creates `scripts/ralph.sh`, `scripts/quality-gate.sh`, `scripts/session-catchup.sh`
- Creates `current_tasks/` and `agent_logs/` directories
- Updates `.gitignore`

---

## The three workflows

### 1. Ralph loop — autonomous feature development

```bash
# Create a PRD first
/prd Add dark mode toggle to settings

# Then run autonomously
bash scripts/ralph.sh --max-plan --quality-gate --review
```

Claude loops: read PRD → pick task → implement → test → commit → repeat.
Each iteration: fresh context, git-based task locking, quality-gated.

### 2. Code review — two-phase parallel review

```bash
/review                    # Full review (all relevant agents)
/review security           # Single-dimension review
/review src/components/    # Review specific scope
```

**Phase 1:** `spec-compliance-reviewer` verifies the implementation matches the PRD/acceptance criteria.
**Phase 2:** Quality agents run in parallel — security, TypeScript, architecture, performance, data integrity, accessibility.
Findings consolidated into a single P1/P2/P3 report with quality scores.

### 3. Compound loop — capture learnings

```bash
/compound                  # After any fix, capture learnings to docs/solutions/
```

Builds a searchable knowledge base. Future `/review` and session-start hooks consult it automatically.

---

## Automated hooks

The framework installs 5 hooks that run automatically — no user action required.

| Hook | Trigger | What it does |
|------|---------|-------------|
| `session-start.sh` | Session start, resume, clear, compact | Injects PROGRESS.md, failed-approaches headings, and task locks into Claude's context |
| `pre-tool-use.sh` | Before every Write, Edit, or Bash call | Re-reads PROGRESS.md (top 30 lines) to prevent goal drift over long sessions |
| `check-complete.sh` | When Claude tries to stop | Blocks stop if PROGRESS.md hasn't been updated (>2h stale) |
| `task-completed.sh` | Agent Team task marked complete | Runs quality gate; checks PROGRESS.md freshness |
| `teammate-idle.sh` | Agent Team member goes idle | Prompts check for unclaimed tasks before shutdown |

### Context engineering principles

These hooks implement three key techniques:

- **Attention injection** — `pre-tool-use.sh` re-reads the current goal before every file modification, keeping it in Claude's recent attention window. Prevents goal drift after 50+ tool calls.
- **Automatic bootstrapping** — `session-start.sh` ensures every session starts with awareness of project state, past failures, and active locks. No manual "read PROGRESS.md" needed.
- **Completion gating** — `check-complete.sh` ensures Claude updates PROGRESS.md before stopping, so the next session can pick up where this one left off.

---

## Anti-rationalization tables

Every agent and CLAUDE.md contains explicit rationalization-resistance tables that pre-empt the exact excuses Claude uses to skip steps:

```
| Excuse                        | Reality                                                |
|-------------------------------|--------------------------------------------------------|
| "Too simple to test"          | Simple code breaks. The test takes 30 seconds.         |
| "I'll add tests later"        | You won't. Tests written after the fact prove nothing. |
| "I've completed the task"     | Did you run the code? Did you see the output?          |
| "The user didn't ask for it"  | CODE-STANDARDS.md requires it.                         |
```

Each review agent has domain-specific tables (e.g., security-sentinel has "This is internal-only code" → "Internal code gets exposed").

---

## Review agents

All 7 agents are **read-only** (`tools: Read, Glob, Grep`) — they cannot modify code.

| Agent | Specialisation | When spawned |
|-------|---------------|-------------|
| `spec-compliance-reviewer` | Verifies implementation matches requirements | Always (Phase 1, runs first) |
| `security-sentinel` | OWASP Top 10, auth, RLS, injection | Always |
| `typescript-reviewer` | Type safety, strict mode, Supabase types | Always |
| `architecture-strategist` | Boundaries, coupling, dependency direction | Always |
| `performance-oracle` | N+1 queries, re-renders, bundle size | Data-heavy features |
| `data-integrity-guardian` | Migrations, transactions, RLS completeness | Schema changes |
| `accessibility-reviewer` | WCAG 2.1 AA, keyboard nav, ARIA | UI changes |

### Quality scoring

Reviews score 9 dimensions (0.0–1.0). If overall score < 0.85, a remediation task is created before merge.

---

## Bi-directional sync

The framework syncs across all registered projects via `scripts/sync.sh`.

```bash
# Check which projects are current vs behind
bash scripts/sync.sh status

# Push framework updates to ALL registered projects
bash scripts/sync.sh push

# Pull improvements from a project back into the framework
bash scripts/sync.sh pull /path/to/project

# Auto-discover projects in a directory
bash scripts/sync.sh discover ~/Projects

# Register/unregister a project
bash scripts/sync.sh register /path/to/project
bash scripts/sync.sh unregister /path/to/project
```

### How push works

1. Pushes framework to origin
2. Updates each project's `.claude-framework` submodule to latest
3. Copies agents, commands, hooks, scripts to each project
4. Merges framework hooks into each project's `settings.json` (appends, never overwrites)
5. Commits the submodule update in each project

### Project registry

Stored at `~/.hartz-claude-framework/projects.txt`. Projects are registered by absolute path.

---

## Session recovery

After a `/clear` or context compaction, recover what happened in the previous session:

```bash
bash scripts/session-catchup.sh              # Last session's unsynced context
bash scripts/session-catchup.sh --full        # Full session summary with user messages
bash scripts/session-catchup.sh --sessions 3  # Last 3 sessions
```

Parses Claude Code's internal `.jsonl` session files, finds the last PROGRESS.md write, and shows what happened after that point.

---

## Decision guide

| Situation | Command / Approach |
|-----------|-------------------|
| Build a feature with 3+ stories | `/prd` → `ralph.sh` |
| Fix a specific bug | `/bugfix` → `ralph.sh` |
| Quick task routing (auto-classifies) | `/task` |
| Review completed work | `/review` |
| Debug with competing hypotheses | Agent Teams, Debate pattern |
| Architecture decision | Agent Teams (Opus), 3 competing approaches |
| Sequential data processing | Solo Claude Code |
| Capture learnings after a fix | `/compound` |
| Recover after /clear or compaction | `session-catchup.sh` |

## Model routing

| Phase | Model | Rationale |
|-------|-------|-----------|
| Orchestrator / team lead | Opus | Strategic reasoning, synthesis |
| Architecture & security review | Opus | High-stakes decisions |
| Feature implementation | Sonnet | Strong code quality, cost-efficient |
| Code review (all agents) | Sonnet | Complex reasoning without Opus cost |
| Exploration, grep, docs | Haiku | Fast, read-only, minimal cost |

---

## Directory structure

```
your-project/
├── CLAUDE.md                          ← Claude reads this on every session
├── PROGRESS.md                        ← Current status, recent changes, next priorities
├── current_tasks/                     ← File-based task locks (git-coordinated)
├── agent_logs/                        ← Ralph loop iteration logs (gitignored)
├── .claude-framework/                 ← Framework submodule
├── .claude/
│   ├── agents/
│   │   ├── spec-compliance-reviewer.md
│   │   ├── security-sentinel.md
│   │   ├── typescript-reviewer.md
│   │   ├── architecture-strategist.md
│   │   ├── performance-oracle.md
│   │   ├── data-integrity-guardian.md
│   │   └── accessibility-reviewer.md
│   ├── commands/
│   │   ├── prd.md
│   │   ├── bugfix.md
│   │   ├── task.md
│   │   ├── review.md
│   │   └── compound.md
│   ├── hooks/
│   │   ├── session-start.sh           ← Context injection at session start
│   │   ├── pre-tool-use.sh            ← Attention anchoring before file modifications
│   │   ├── check-complete.sh          ← Completion gate before stopping
│   │   ├── task-completed.sh          ← Quality gate on task completion
│   │   └── teammate-idle.sh           ← Follow-up task assignment
│   └── settings.json                  ← Hook configuration (merged, not overwritten)
├── scripts/
│   ├── ralph.sh                       ← Autonomous PRD-driven dev loop
│   ├── quality-gate.sh                ← Pre-commit validation
│   └── session-catchup.sh             ← Context recovery from session files
└── docs/
    ├── solutions/                     ← YAML-frontmatter learnings
    ├── failed-approaches.md           ← What didn't work and why
    ├── CODE-STANDARDS.md              ← Mandatory code patterns
    └── architecture/                  ← Architecture decision records
```

---

## Agent Teams patterns

The framework includes orchestration patterns for multi-agent work:

| Pattern | When to use | How it works |
|---------|------------|-------------|
| **Leader** | Feature development | Opus orchestrator + Sonnet workers with file ownership boundaries |
| **Swarm** | Code review | All review agents spawned in parallel, lead synthesises findings |
| **Debate** | Debugging / architecture | 3 agents with competing hypotheses challenge each other |
| **Watchdog** | Risky refactors | Implementation agent + monitoring agent, plan approval required |
| **Wave** | Large features | Sequential waves of parallel tasks (types → components → integration → tests → review) |

---

## Updating

### Single project

```bash
cd your-project/.claude-framework
git pull origin master
bash install.sh ..
```

### All projects at once

```bash
cd /path/to/hartz-claude-framework
# Make changes, commit, then:
bash scripts/sync.sh push
```

---

## Credits

### Original synthesis

Distilled from 8 community orchestration tools:
- [wshobson/agents](https://github.com/wshobson/agents) — agent catalog and model-tiering
- [ruvnet/claude-flow](https://github.com/ruvnet/claude-flow) — ONE MESSAGE parallelism rule, behavioural rules
- [nwiizo/ccswarm](https://github.com/nwiizo/ccswarm) — quality scoring dimensions
- [affaan-m/claude-swarm](https://github.com/affaan-m/claude-swarm) — wave execution, file locking
- [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) — review agents, compound loop
- [Kieran Klaassen's swarm skill](https://gist.github.com/kieranklaassen/4f2aba89594a4aea4ad64d753984b2ea) — worker preamble
- [Anthropic C compiler project](https://www.anthropic.com/engineering/building-c-compiler) — RALPH loop, git task locking, external memory
- [harchyboy/ralph-moss](https://github.com/harchyboy/ralph-moss) — PRD format, quality gate integration

### Context engineering enhancements

- [obra/superpowers](https://github.com/obra/superpowers) — SessionStart hook injection, anti-rationalization tables, spec-compliance review, verification-before-completion
- [OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files) — PreToolUse attention injection, Stop completion gate, session JSONL recovery
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — tool restrictions per agent role

---

Maintained by [Hartz AI](https://hartz.ai). MIT License.
