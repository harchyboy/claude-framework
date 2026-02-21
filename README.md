# Hartz Claude Framework

> Best-of-breed Claude Code multi-agent workflow system for all Hartz AI projects.

Distilled from 8 community orchestration tools (wshobson/agents, claude-flow, ccswarm, claude-swarm, Compound Engineering, Klaassen's swarm skill, Anthropic's C compiler project, and the 9-agent Kanban system) into a single installable framework.

---

## What this gives you

- **CLAUDE.md** — universal behavioral rules, model routing, and coordination logic Claude reads on every session
- **6 review agents** — parallel specialist reviewers (security, performance, TypeScript, architecture, data integrity, accessibility)
- **4 slash commands** — `/prd`, `/review`, `/compound`, `/ralph` for the full build→review→learn loop
- **Ralph loop script** — autonomous PRD-driven development (git-coordinated, quality-gated)
- **Worker preamble** — self-organizing swarm template for Agent Teams
- **Quality gate script** — TypeScript + lint + test validation with LLM scoring
- **Learnings system** — `docs/solutions/` with YAML-frontmatter searchable knowledge base
- **Hooks** — TaskCompleted quality enforcement, TeammateIdle follow-up assignment

---

## Quick install

### New project
```bash
# From your project root
git clone https://github.com/hartz-ai/claude-framework .claude-framework
cd .claude-framework && bash install.sh ..
```

### Existing project
```bash
git submodule add https://github.com/hartz-ai/claude-framework .claude-framework
cd .claude-framework && bash install.sh ..
```

### What install.sh does
- Copies `.claude/` agents, commands, hooks, skills into your project
- Creates `CLAUDE.md` if none exists (or merges if one does)
- Creates `PROGRESS.md`, `docs/solutions/`, `docs/failed-approaches.md`
- Creates `scripts/ralph.sh` and `scripts/quality-gate.sh`
- Creates `current_tasks/` and `agent_logs/` directories
- Adds `current_tasks/` and `agent_logs/` to `.gitignore`

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

### 2. Agent Teams — parallel review or collaboration
```bash
# Enable agent teams (add to your shell profile)
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Then in Claude Code:
/review                    # Runs 6 specialist reviewers in parallel
/review security           # Single-dimension review
```

### 3. Compound loop — capture learnings
```bash
/compound                  # After any fix, capture learnings to docs/solutions/
```
Builds a searchable knowledge base. Future `/review` sessions consult it automatically.

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
| Data processing / sequential script | Solo Claude Code |
| Capture learnings after a fix | `/compound` |

## Model routing

| Phase | Model |
|-------|-------|
| Orchestrator / lead | Opus |
| Implementation | Sonnet |
| Exploration / grep / read-only | Haiku |

---

## Directory structure
```
your-project/
├── CLAUDE.md                    # ← Claude reads this on every session
├── PROGRESS.md                  # ← Current status, recent changes, next priorities
├── current_tasks/               # ← File-based task locks (git-coordinated)
├── agent_logs/                  # ← Ralph loop iteration logs
├── .claude/
│   ├── agents/                  # ← Specialist agent definitions
│   │   ├── security-sentinel.md
│   │   ├── performance-oracle.md
│   │   ├── typescript-reviewer.md
│   │   ├── architecture-strategist.md
│   │   ├── data-integrity-guardian.md
│   │   └── accessibility-reviewer.md
│   ├── commands/                # ← Slash commands
│   │   ├── prd.md
│   │   ├── bugfix.md
│   │   ├── task.md
│   │   ├── review.md
│   │   └── compound.md
│   ├── hooks/
│   │   ├── task-completed.sh    # ← Quality gate on task completion
│   │   └── teammate-idle.sh     # ← Follow-up task assignment
│   └── skills/                  # ← Reusable skill packs
│       ├── prd/SKILL.md
│       ├── ralph-moss/SKILL.md
│       ├── bugfix/SKILL.md
│       ├── task/SKILL.md
│       └── review/SKILL.md
├── scripts/
│   ├── ralph.sh                 # ← Main autonomous loop
│   ├── quality-gate.sh          # ← Pre-commit validation
│   └── merge-smart.sh           # ← Git conflict resolution
└── docs/
    ├── solutions/               # ← YAML-frontmatter learnings
    ├── failed-approaches.md     # ← What didn't work and why
    └── architecture/            # ← Architecture decision records
```

---

## Updating

```bash
cd .claude-framework
git pull origin main
bash install.sh ..
```

---

## Contributing

This framework is maintained by Hartz AI. To add an agent definition, create a markdown file in `.claude/agents/` following the existing format and submit a PR.

---

## Credits

Synthesised from:
- [wshobson/agents](https://github.com/wshobson/agents) — agent catalog and model-tiering
- [ruvnet/claude-flow](https://github.com/ruvnet/claude-flow) — ONE MESSAGE parallelism rule, behavioural rules
- [nwiizo/ccswarm](https://github.com/nwiizo/ccswarm) — quality scoring dimensions
- [affaan-m/claude-swarm](https://github.com/affaan-m/claude-swarm) — wave execution, file locking
- [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) — review agents, compound loop
- [Kieran Klaassen's swarm skill](https://gist.github.com/kieranklaassen/4f2aba89594a4aea4ad64d753984b2ea) — worker preamble
- [Anthropic C compiler project](https://www.anthropic.com/engineering/building-c-compiler) — RALPH loop, git task locking, external memory
- [harchyboy/ralph-moss](https://github.com/harchyboy/ralph-moss) — PRD format, quality gate integration
