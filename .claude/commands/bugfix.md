# /bugfix — Bug Fix PRD Generator

Creates a focused, right-sized bug fix PRD with verifiable acceptance criteria.
Designed for Ralph loop execution.

## Usage

```
/bugfix The contact form crashes when company field is null
/bugfix Pipeline view shows wrong deal count for archived listings
```

## What I'll do

1. Ask clarifying questions to understand the bug precisely
2. Identify the minimum reproduction case
3. Define verifiable acceptance criteria (not "it works" — specific test cases)
4. Create a focused prd.json

## Clarifying questions

1. **How to reproduce it?** (exact steps)
2. **What's the expected behaviour vs actual behaviour?**
3. **Is it consistent or intermittent?** (if intermittent, under what conditions?)
4. **What's the impact?** (how many users affected, what breaks?)
5. **Are there any error messages or console logs?**
6. **What changed recently that might have caused it?**

## Output format

```json
{
  "project": "ProjectName",
  "branchName": "ralph-moss/fix-[bug-description]",
  "description": "Fix: [brief description of bug]",
  "bugReport": {
    "symptom": "What the user sees",
    "reproduction": ["Step 1", "Step 2", "Step 3"],
    "expectedBehaviour": "What should happen",
    "actualBehaviour": "What actually happens",
    "errorMessages": "Any console/server errors"
  },
  "userStories": [
    {
      "id": "BUG-001",
      "title": "Fix [bug description]",
      "description": "As a user, I should be able to [action] without [bug occurring]",
      "acceptanceCriteria": [
        "Reproduce case: [specific steps] no longer causes [error]",
        "Edge case: [null/empty/boundary value] handled gracefully",
        "No regression: existing [related feature] still works",
        "TypeScript compiles without errors",
        "All existing tests pass",
        "New test covers the exact reproduction case"
      ],
      "filesLikelyInScope": ["educated guess at relevant files"],
      "priority": 1,
      "passes": false,
      "notes": "Check docs/failed-approaches.md before attempting fixes"
    }
  ]
}
```

Save to: `scripts/ralph-moss/prds/fix-[bug-description]/prd.json`
