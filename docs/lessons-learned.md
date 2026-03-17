# Lessons Learned

> Solutions discovered while implementing Hartz AI projects. Consult before inventing novel approaches.

---

## 2026-03-17 — Shell Script Blast Radius Prevention Patterns

**Context:** During blast-radius.sh development, five categories of silent failures created massive false positives when analyzing code impact:

1. `grep -P` silently fails on Windows Git Bash (no error, no output)
2. Unanchored sed patterns match prose in markdown, inflating file counts
3. `set -e` + `((COUNTER++))` exits unexpectedly when counters transition 0→1
4. Pipe subshells (`cmd | while read VAR`) lose variable assignments
5. Generic function names (`log()`, `fail()`, `main()`) make every file transitively affected

**Solutions Documented:**
- See `.claude/rules/shell-scripts.md` for full prevention rules and examples.
- All five issues now have explicit checks in the pre-commit shell script checklist.
- Use `grep -E` (portable), anchor regex patterns, avoid arithmetic in `set -e`, use `< file.txt` redirection, name functions with module prefix.

**Key Insight:**
These failures weren't caught by code review because they operate silently — no error messages, just wrong results. Platform-specific issues (grep -P on Windows) are especially invisible to developers on Linux. Prevention requires:
- **Explicit platform testing** before commit (both Linux and Git Bash)
- **Shellcheck validation** to catch some categories
- **Scoped naming conventions** to enable impact analysis without false positives

**Implementation:**
- Created `.claude/rules/shell-scripts.md` with detailed examples for each issue
- Updated `docs/CODE-STANDARDS.md` Section 7 (Shell Scripts) with quick reference
- Added shell script checks to the pre-commit checklist

---

## 2026-03-17 — External Tool Evaluation: 4-Repo Review Session

**Context:** Evaluated 4 external repos in one session for potential HCF integration. Used the four-analyst pattern (docs/solutions/2026-03-17-build-vs-buy-external-tools.md) for the first repo, quick CTO-level assessment for the rest.

**Results:**
| Repo | Verdict | Action |
|------|---------|--------|
| `tirth8205/code-review-graph` | REJECT (5/12) | Built blast-radius.sh instead |
| `kepano/obsidian-skills` | REJECT (irrelevant) | No action |
| `thedotmack/claude-mem` | REJECT (overlapping, AGPL, heavy) | No action |
| `obra/superpowers` | REJECT as dep, EXTRACT ideas | 3 features implemented natively |
| `nextlevelbuilder/ui-ux-pro-max-skill` | ACCEPT as opt-in | Installed on 4 UI-heavy projects |

**Key Insights:**
1. **Per-project opt-in skills** are the right pattern for domain-specific tools (UI/UX, analytics). Don't add to HCF core — install via `uipro init --ai claude` per-project. Lives in `.claude/skills/` which doesn't conflict with HCF's `.claude/agents/` and `.claude/commands/`.
2. **"Mine the ideas, don't adopt the dependency"** is the highest-value approach for well-engineered repos that overlap with existing capabilities (superpowers). Read their skills, extract the patterns, implement natively.
3. **License matters for frameworks** — AGPL-3.0 (claude-mem) is a non-starter for commercial tooling. MIT (superpowers) is fine for idea extraction. Always check before evaluating further.
4. **Crypto token promotion in dev tools** is a credibility red flag — not a dealbreaker alone but combined with other concerns, it tips the scale.

**All rejections documented in:** `docs/failed-approaches.md`

---
