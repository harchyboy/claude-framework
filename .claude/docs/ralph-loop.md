# Ralph Loop (autonomous development)

For unattended autonomous development:

```bash
bash scripts/ralph.sh [max_iterations] [options]

Options:
  --max-plan          Track iterations not cost (Anthropic Max plan users)
  --max-cost <n>      Hard stop if total cost exceeds $n
  --model <model-id>  Override the Claude model (default: claude-sonnet-4-6)
  --timeout <min>     Per-iteration timeout in minutes (default: 30)
  --quality-gate      Run typecheck/lint/tests after each iteration
  --review            Spawn review agent after implementation
  --strict            Fail on lint warnings
```

## Each iteration
0. Clean stale task locks (>2 hours old) — prevents crashed agents from blocking stories
1. `git pull origin main` — sync with remote
2. Read `PROGRESS.md` and `docs/solutions/` — bootstrap context
3. Check `current_tasks/` — skip locked tasks
4. Pick highest-priority uncomplete task from PRD
5. Claim it: `echo "task description" > current_tasks/task-name.txt && git add && git commit && git push`
6. Implement with tests
7. Run quality gate — fix failures before continuing
8. Update `PROGRESS.md`
9. Commit and push
10. Remove lock file, commit

**If push fails (conflict):** another agent claimed the task — pick a different one.

---

## PRD Format

Create PRDs at `scripts/ralph-moss/prds/[feature-name]/prd.json`:

```json
{
  "project": "ProjectName",
  "branchName": "ralph-moss/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Specific criterion 1",
        "Specific criterion 2",
        "TypeScript compiles without errors",
        "All existing tests pass"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

**Story sizing rule:** each story MUST be completable in ONE iteration (~10 min of AI work).
Split anything that sounds like: "Build the entire X", "Add authentication", "Refactor the Y".

---

## Compiler Oracle Pattern

When a task resists decomposition (many agents hitting the same blocking issue):
1. Identify a reference implementation or known-good version (production code, previous commit, test suite)
2. Use it to partition the problem: run the reference on 90% of files, your implementation on 10%
3. If mixed system works, the bug is not in your 10% — adjust partition
4. Delta debug until the failing subset is minimal
5. Fix the isolated root cause once — document in `docs/solutions/`

This pattern prevents N agents independently fixing the same bug and overwriting each other.
