# /task — Smart Task Router

Automatically classifies a task as feature, bug, or refactor, then routes to the
appropriate workflow.

## Usage

```
/task Add loading spinner to the pipeline dashboard
/task Fix the null pointer when company is empty
/task The calendar integration is broken after the Supabase update
```

## Classification logic

**Feature** → Use `/prd` workflow
Indicators: "add", "build", "create", "implement", "new", "support for"

**Bug fix** → Use `/bugfix` workflow
Indicators: "fix", "broken", "crash", "error", "failing", "wrong", "not working"

**Refactor** → Use `/prd` workflow with refactor-specific story sizing
Indicators: "refactor", "improve", "clean up", "extract", "move", "simplify"

**Ambiguous** → Ask one clarifying question: "Is this fixing something broken,
or adding new functionality?"

## Routing

After classification:
- Feature → run `/prd` questions
- Bug → run `/bugfix` questions
- Refactor → run `/prd` with note that stories should be extractable units

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
