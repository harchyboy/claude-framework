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
