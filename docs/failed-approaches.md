# Failed Approaches

> Claude reads this before attempting solutions. Never retry what's already failed.

---

## Template

```
## [Date] — [Brief description of what was tried]

**Task:** What we were trying to accomplish
**Approach:** What we tried
**Why it failed:** Specific error or reason
**What to try instead:** Alternative direction
```

---

## 2026-03-02 — Stop event hooks (check-complete.sh, session-end.sh, prompt hook)

**Task:** Ensure PROGRESS.md is updated and session summary is shown when Claude stops
**Approach:** Added command hooks (check-complete.sh, session-end.sh) and a prompt hook on the Stop event in settings.json
**Why it failed:** The Stop event fires after every Claude turn, not just at session exit. Any hook output (stdout, stderr, or prompt response) gets delivered as a conversation message. Claude must respond to it, ending another turn, which fires Stop again — creating an infinite loop. The prompt hook is the worst offender (forces a full response every cycle), but even command hooks with informational output trigger the loop.
**What to try instead:** Do not use hooks on the Stop event. PROGRESS.md update reminders should be handled via pre-tool-use attention injection or CLAUDE.md behavioural rules instead.

## 2026-03-17 — tirth8205/code-review-graph integration (score 5/12)

**Task:** Add blast-radius / code dependency graph analysis to the review pipeline
**Approach:** Evaluated `tirth8205/code-review-graph` for integration as an MCP server or Claude plugin using the four-analyst pattern (token, architect, quality, skeptic)
**Why it failed:** Project is 19 days old with critical bugs in changelog (NameError in blast-radius, incremental update re-parsing everything). Hard blocker: worktree incompatibility — Ralph's isolation model doesn't mesh with the graph's single-repo assumption. Dependency footprint adds Python + pip packages. We only need ~20% of its features.
**What to try instead:** Built `scripts/blast-radius.sh` — 300 lines of bash using git + grep + sed. Zero dependencies, works in worktrees, deployed to all 10 projects. Re-evaluate the upstream repo after 6 months if it stabilises and resolves worktree paths.
