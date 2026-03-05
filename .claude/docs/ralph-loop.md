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
  --verify            Run independent verification + generate proof packets
  --verify-runtime    Include Playwright browser verification
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
8. Run verification (if `--verify`) — generate proof packet, score confidence
9. Update `PROGRESS.md`
10. Commit and push
11. Remove lock file, commit

**If push fails (conflict):** another agent claimed the task — pick a different one.

## Verification & Proof Packets

When `--verify` is enabled, each completed story generates a proof packet:

```
proof/<story-id>/
├── criteria.md        # Original acceptance criteria
├── diff.patch         # Code changes
├── test-results.txt   # Test output
├── verification.md    # Verification report
├── verdict.json       # Machine-readable verdict + confidence score
└── screenshots/       # Evidence (with --verify-runtime)
```

Confidence scoring:
- **0.9+**: All criteria verified — auto-merge candidate
- **0.7–0.89**: Mostly verified — queued for human review
- **< 0.7**: Failures found — blocked until reviewed

Review queue: `bash scripts/hartz-land/review-queue.sh`

## Hartz Land (Multi-Project Overnight)

Run Ralph across all projects on a dedicated machine:

```bash
bash scripts/hartz-land/start-all.sh --verify --max-concurrent 3
bash scripts/hartz-land/monitor.sh --watch
bash scripts/hartz-land/daily-digest.sh     # morning review
bash scripts/hartz-land/review-queue.sh     # approve/reject
```

See `docs/HARTZ-LAND-GUIDE.md` for full setup.

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
