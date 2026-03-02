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
