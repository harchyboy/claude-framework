# /prd — PRD Generator

Creates a structured PRD with user stories sized for Ralph loop execution.

## What I'll do

1. Ask you clarifying questions (do not skip this step)
2. Identify the exact scope, constraints, and acceptance criteria
3. Decompose into right-sized user stories (each completable in ~10 min of AI work)
4. Output a `prd.json` file ready for `ralph.sh`

## Clarifying questions to ask first

Before writing any PRD, ask ALL of these:

1. **What problem does this solve?** (user pain point, not feature description)
2. **Who is the primary user?** (which persona — e.g. Tom the broker, Max the admin)
3. **What does "done" look like?** (how will you verify it works?)
4. **What are the hard constraints?** (must use X, must not break Y, must complete by Z)
5. **What are the nice-to-haves vs must-haves?** (MoSCoW)
6. **What files/areas of the codebase are in scope?** (helps size stories correctly)
7. **Are there existing patterns to follow?** (point to a similar feature already built)

## Story sizing rules

Each story MUST be completable in ONE Ralph loop iteration (~10 min AI work).

**Right-sized:**
- Add a column to an existing table and update the TypeScript types
- Add a new UI component to an existing page
- Write integration tests for an existing API route
- Update a Supabase Edge Function with new business logic

**Too big — split these:**
- "Build the pipeline management view"
- "Add authentication"
- "Refactor the data layer"
- "Add calendar integration"

## Output format

```json
{
  "project": "ProjectName",
  "branchName": "ralph-moss/feature-name",
  "description": "One-sentence description",
  "context": "Brief context Claude needs to understand the codebase location",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a [persona], I want [action] so that [benefit]",
      "acceptanceCriteria": [
        "Specific, testable criterion 1",
        "Specific, testable criterion 2",
        "TypeScript compiles without errors",
        "All existing tests pass",
        "New tests cover the happy path and error case"
      ],
      "filesInScope": ["src/components/X.tsx", "src/api/Y.ts"],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

Save to: `scripts/ralph-moss/prds/[feature-name]/prd.json`
Also create: `scripts/ralph-moss/prds/[feature-name]/AGENT_PROMPT.md` with project context.
