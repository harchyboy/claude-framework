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
  --auto-pr           Auto-create GitHub PR when confidence >= threshold
  --pr-threshold <n>  Confidence threshold for auto-PR (default: 0.9)
  --strict            Fail on lint warnings
```

## Each iteration
0. Clean stale worktrees (>2 hours old)
1. `git pull` — sync with remote
2. Pick highest-priority pending story from PRD
3. Create git worktree: `.worktrees/<story-id>` on branch `ralph/<story-id>`
4. Run Claude inside the worktree — isolated from other agents
5. Implement with tests, run quality gate
6. Run verification (if `--verify`) — generate proof packet, score confidence
7. Auto-PR (if `--auto-pr` and confidence >= threshold) — push branch, `gh pr create`
8. Merge worktree branch back to main branch
9. Clean up worktree
10. Push

**Multi-agent isolation:** Each agent works in its own worktree — no file conflicts, no lock files.

## Local model routing (cost optimization)

For routine subtasks, use a local Ollama model instead of Claude:

```bash
# Route a prompt through local model (falls back to Claude if Ollama unavailable)
bash scripts/local-model.sh "Generate unit tests for src/auth.ts"

# Specify a different model
bash scripts/local-model.sh "Fix ESLint errors" --model codellama:7b

# Pipe from stdin
cat prompt.md | bash scripts/local-model.sh -
```

Requires [Ollama](https://ollama.com) running locally. Default model: `qwen2.5-coder:7b`.

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
- **0.9+**: All criteria verified — auto-PR created (with `--auto-pr`)
- **0.7–0.89**: Mostly verified — queued for human review
- **< 0.7**: Failures found — blocked until reviewed

Review queue: `bash scripts/hartz-land/review-queue.sh`

## Hartz Land (Multi-Project Overnight)

Run Ralph across all projects on a dedicated machine:

```bash
bash scripts/hartz-land/start-all.sh --verify --auto-pr --max-concurrent 3
bash scripts/hartz-land/monitor.sh --watch
tmux attach -t hartz-<project>              # watch an agent work live
bash scripts/hartz-land/daily-digest.sh     # morning review
bash scripts/hartz-land/review-queue.sh     # approve/reject
```

See `docs/HARTZ-LAND-GUIDE.md` for full setup.

### Monitor from Claude Code with /loop

While agents run autonomously, use `/loop` + `/babysit` to get periodic status
updates right in your Claude Code session:

```bash
/loop 5m /babysit              # Pulse check every 5 minutes
/loop 10m /status              # Full status briefing every 10 minutes
/loop 5m gh pr checks <number> # Watch a specific PR's CI status
```

`/babysit` is a lightweight monitor designed for `/loop` — it reports by
exception (only what changed or needs attention) to avoid flooding your session.

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
