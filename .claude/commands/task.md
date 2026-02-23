# /task - Smart Task Router

Automatically classifies a task as feature, bug, or refactor, then routes to the
appropriate workflow including agent teams where needed.

## Usage

```
/task Add loading spinner to the pipeline dashboard
/task Fix the null pointer when company is empty
/task The calendar integration is broken after the Supabase update
```

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
