# /task - Smart Task Router

Automatically classifies a task as feature, bug, or refactor, then routes to the
appropriate workflow including agent teams where needed.

## Usage

```
/task Add loading spinner to the pipeline dashboard
/task Fix the null pointer when company is empty
/task The calendar integration is broken after the Supabase update
```

## Composable flags

Before processing $ARGUMENTS, parse composable flags per `.claude/docs/composable-flags.md`.
Strip recognized flags (--readonly, --concise, --lean, --seq, --local, --lo and their short forms)
from $ARGUMENTS before treating the remainder as this command's input.

Apply active flags throughout:
- --readonly: skip all file writes and write-capable agent spawns
- --concise: limit output to 20 lines max
- --lean: use haiku for subagents, minimize tool calls
- --seq: execute agents sequentially, not in parallel
- --local/--lo: use Ollama for classification and quick-task execution; fall back to haiku if unavailable

## Classification logic

**Feature** -> Use `/prd` workflow
Indicators: "add", "build", "create", "implement", "new", "support for"

**Bug fix** -> Use `/bugfix` workflow
Indicators: "fix", "broken", "crash", "error", "failing", "wrong", "not working"

**Refactor** -> Use `/prd` workflow with refactor-specific story sizing
Indicators: "refactor", "improve", "clean up", "extract", "move", "simplify"

**Ambiguous** -> Ask one clarifying question: "Is this fixing something broken,
or adding new functionality?"

## Routing

After classification:
- Feature -> run `/prd` questions, then Ralph loop, then agent review
- Bug -> run `/bugfix` questions, then implement, then agent review
- Refactor -> run `/prd` with note that stories should be extractable units, then agent review

## Agent team escalation

After implementation is complete, always run `/review` to spawn the full agent swarm:
- security-sentinel
- typescript-reviewer
- architecture-strategist
- performance-oracle
- data-integrity-guardian
- accessibility-reviewer

Spawn all review agents simultaneously in ONE message for true parallelism.
Each agent claims independent review tasks and reports findings to the lead.
Lead synthesises into a P1/P2/P3 report before any merge.

**Escalate to agent teams BEFORE implementation** when:
- The task touches authentication, RLS policies, or multi-tenant data
- The task changes database schema or Supabase queries
- The task affects 3+ files simultaneously
- The task involves a new API integration or adapter

## Monitoring autonomous runs

When routing to Ralph (feature or bug with PRD), suggest monitoring after handoff:

```
Ralph is running. Monitor from this session:
  /loop 5m /babysit
```

## Quick tasks (no PRD needed)

If the task is clearly completable in a single Claude Code session (<10 min, single file):
- Skip PRD generation
- Create the implementation directly
- Run `/review` when done
- Run `/compound` if anything non-obvious was discovered

Quick task indicators:
- "Update the copy/text in..."
- "Change the colour of..."
- "Add a console.log for debugging..."
- "Fix the typo in..."

## Local model routing

Before spawning any subagent or implementing a quick task, determine the optimal execution path:

```bash
ROUTE=$(bash scripts/route-model.sh --description "$TASK_DESCRIPTION" --check-local --quiet)
```

Then act on the route:
- `local:<model>` → execute via `bash scripts/local-model.sh --task-type <type> - <<< "$PROMPT"`
- `haiku` → spawn subagent with `model: "haiku"`
- `sonnet` → spawn subagent with `model: "sonnet"` (default)
- `opus` → spawn subagent with `model: "opus"`

**Always use local routing for the classification step itself** when `--local` flag is active:
```bash
TASK_CLASS=$(bash scripts/local-model.sh --task-type classify - <<< \
  "Classify this task as one of: feature, bug-fix, refactor, ambiguous. Task: $TASK_DESCRIPTION. Reply with one word only.")
```

Eligible for full local execution (Ollama handles the entire task):
- Writing test scaffolds for existing files
- Generating JSDoc/docstrings from existing code
- Fixing lint errors identified by the quality gate
- Creating boilerplate file structures from templates

Not eligible for local execution (always use Claude):
- Anything touching auth, security, RLS
- Multi-file feature implementation
- Complex bug investigation
- Architecture decisions
