# Claude Code — Project Instructions

> Hartz Claude Framework. Edit PROJECT CONTEXT for your project.

## PROJECT CONTEXT

```
Project name:    [REPLACE]
Description:     [REPLACE]
Tech stack:      [REPLACE]
Primary domain:  [REPLACE]
Repo:            [REPLACE]
```

## RULES

### File discipline
- Read files before editing — never assume contents
- Prefer editing existing files over creating new ones
- Never commit secrets, API keys, or `.env` files
- Verify imports resolve before committing TypeScript

### Quality discipline
- Read `docs/CODE-STANDARDS.md` before writing code
- Run tests before AND after changes
- No `TODO` comments without a linked task
- Update `PROGRESS.md` after completing any task
- If stuck after 3 attempts: add to `docs/failed-approaches.md`, try different approach
- Check `docs/solutions/` before implementing novel solutions
- Never retry a known failed approach — check `docs/failed-approaches.md`
- Run commands and verify output before claiming completion

### Anti-rationalization (no excuses)
- "Too simple to test" → Simple code breaks. Write the test.
- "I'll add tests later" → You won't. Write them now.
- "I've completed the task" → Did you run it? Claiming completion without verification is hallucination.
- "That's outside the scope" → If it breaks or is a security risk, it's in scope.
- "I'm following the spirit of the rules" → Follow the letter. Exactly.

### Multi-agent coordination
- ALL spawns + task creates in ONE message for parallelism
- Use `write()` to specific teammates, not `broadcast()`
- Claim tasks by updating owner BEFORE starting work
- Never poll after spawning — wait for reports

### Browser automation
- **Primary**: Use `agent-browser` CLI (Rust-based, accessibility-tree-first, faster for AI agents)
  - Commands: `agent-browser open <url>`, `agent-browser snapshot -i`, `agent-browser click @e1`, etc.
  - Skill reference: `.agents/skills/agent-browser/SKILL.md`
- **Fallback**: Use Playwright MCP only if agent-browser fails or is unavailable
  - Playwright runs as an MCP server, agent-browser runs as a CLI via Bash tool
- Always try agent-browser first. Switch to Playwright if agent-browser errors on 3+ commands.

## MODEL ROUTING

| Task | Model |
|------|-------|
| Orchestrator / team lead | **Opus** |
| Architecture & security review | **Opus** |
| Feature implementation | **Sonnet** |
| Code review | **Sonnet** |
| Exploration / grep | **Haiku** |
| Test generation / docs | **Local** (Ollama) → **Haiku** fallback |
| Boilerplate / lint fixes | **Local** (Ollama) → **Haiku** fallback |
| Task classification | **Local** (Ollama) → **Haiku** fallback |

> Routing is **automatic**. `ralph.sh` classifies each story and routes to Ollama when eligible.
> Add `--local` (or `--lo`) to any command to force local routing.
> Use `--no-local` on ralph to disable. Docs: `.claude/docs/local-model-routing.md`

## WORKFLOW GUIDE

| Situation | Approach |
|-----------|----------|
| Feature with 3+ stories | `/prd` → `ralph.sh` |
| Bug fix | `/bugfix` → `ralph.sh` |
| Quick task routing | `/task` |
| Research a topic | `/research` (use `--quick` / `--deep` / `--exhaustive` for depth) |
| Review completed work | `/review` (smart-filtered) or `/review --full` |
| Check blast radius of changes | `blast-radius.sh` (auto in `/review`, or standalone) |
| Verify story actually works | `/verify` |
| Debug everyday bugs | `/debug --systematic` (4-phase root cause) |
| Debug complex/cross-system bugs | `/debug` (3-agent debate pattern) |
| Capture learnings | `/compound` |
| Recover after /clear | `session-catchup.sh` |
| Overnight autonomous dev | `hartz-land/start-all.sh --verify` |
| Monitor autonomous runs | `/loop 5m /babysit` |
| Watch specific PR checks | `/loop 5m gh pr checks <number>` |
| Morning review | `hartz-land/daily-digest.sh` |
| Cheap exploration mode | Any command with `--lean --readonly` flags |
| Run a YAML workflow | `workflow-runner.sh workflows/<name>.yaml` |
| Review with consensus gate | `/review` (auto) or `ralph.sh --review --consensus` |
| Dry-run a workflow | `workflow-runner.sh workflows/<name>.yaml --dry-run` |
| Debug via debate pattern | `workflow-runner.sh workflows/debug-investigation.yaml --var bug_description="..."` |
| Scaffold a new frontend app | `/ui-scaffold` (SaaS, dashboard, landing, minimal templates) |
| Build a UI component from design | `workflow-runner.sh workflows/ui-component.yaml --var component_name="..."` |
| Generate a component from prompt | Magic UI MCP (`mcp__magic-ui__21st_magic_component_builder`) |

## TOKEN COMPRESSION (RTK)

RTK (Rust Token Killer) is installed as a PreToolUse hook. It automatically rewrites
Bash commands (`git`, `ls`, `find`, `pytest`, etc.) to strip noise before output
enters the context window. Saves 60-90% tokens on common dev commands.

- Binary: `~/.local/bin/rtk.exe`
- Hook: `.claude/hooks/rtk-rewrite.py`
- Config: `~/AppData/Roaming/rtk/config.toml`
- Check savings: `rtk gain`

## REFERENCE DOCS (read on demand, not every turn)

- Composable flags (--readonly, --concise, --lean, --seq): `.claude/docs/composable-flags.md`
- Quality gates & review scoring: `.claude/docs/quality-gates.md`
- External memory protocol: `.claude/docs/external-memory.md`
- Agent team patterns: `.claude/docs/agent-teams.md`
- Ralph loop usage: `.claude/docs/ralph-loop.md`
- Tech stack conventions: `.claude/docs/tech-stack.md`
- Anti-rationalization (full): `.claude/docs/anti-rationalization.md`
- Workflow-as-code: `.claude/docs/workflow-as-code.md`
- Code standards: `docs/CODE-STANDARDS.md`
- Failed approaches: `docs/failed-approaches.md`
- Hartz Land guide: `docs/HARTZ-LAND-GUIDE.md`
- Design system rules: `.claude/rules/design-system.md`
- Frontend design quality: `.claude/rules/frontend-design.md`
- UI scaffold skill: `.claude/skills/ui-scaffold/SKILL.md`
