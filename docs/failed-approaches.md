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

## 2026-03-17 — kepano/obsidian-skills — do not integrate (irrelevant)

**Task:** Evaluate for HCF or Hartz Command enhancement
**Approach:** Reviewed repo contents — 5 skills for Obsidian vault manipulation (markdown syntax, .base files, .canvas files, Obsidian CLI, web scraping via Defuddle)
**Why it failed:** All skills are Obsidian-specific. HCF projects don't use Obsidian vaults, .base files, or wikilinks. The one mildly useful skill (Defuddle web scraping) is already covered by our Firecrawl MCP server.
**What to try instead:** Nothing — no overlap with our use case.

## 2026-03-17 — thedotmack/claude-mem — do not integrate (overlapping, heavy, AGPL)

**Task:** Evaluate persistent memory system for HCF
**Approach:** Reviewed claude-mem — SQLite + Chroma vector DB memory system with lifecycle hooks, web viewer on port 37777, MCP search tools
**Why it failed:** (1) Claude Code already has native auto-memory at `~/.claude/projects/.../memory/`. (2) HCF already has session handoffs, docs/solutions/, lessons-learned.md, failed-approaches.md, and session-catchup.sh. (3) Requires Node.js 18+, Bun, uv, SQLite, Chroma — 5 runtime deps for what we do with markdown. (4) Hooks conflict with HCF/Hartz Command on SessionStart, PostToolUse, Stop, SessionEnd. (5) AGPL-3.0 license — viral copyleft, any modifications must be open-sourced, incompatible with commercial tooling. (6) Promotes a Solana crypto token ($CMEM) in the README.
**What to try instead:** Continue using native Claude memory + HCF's markdown-based knowledge system. If richer search is needed, add a `/memory search` command over docs/solutions/.

## 2026-03-17 — obra/superpowers — do not integrate, but extract ideas

**Task:** Evaluate complete dev workflow system for HCF
**Approach:** Reviewed superpowers — 14 skills covering brainstorming, planning, TDD, subagent-driven development, debugging, code review, worktrees, branch finishing. By Jesse Vincent (obra), MIT licensed, well-engineered.
**Why it failed as a dependency:** HCF already has equivalent or superior versions of 9/14 skills (/prd, ralph.sh, tdd agents, /review, /verify). Installing would create two competing workflow systems fighting for auto-trigger control. Skills overlap on the same events and domains.
**What to try instead:** Extracted 3 ideas and implemented natively: (1) `/debug --systematic` — 4-phase root-cause process for everyday bugs. (2) Agent status protocol — DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED in ralph.sh. (3) "3+ failures = wrong architecture" escalation rule. See commit `9d9c153`.
