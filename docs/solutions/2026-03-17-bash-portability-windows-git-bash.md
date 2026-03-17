---
title: "Bash portability traps on Windows / Git Bash"
category: pattern
tags: [bash, windows, git-bash, portability, set-e, grep, sed, subshell]
date: 2026-03-17
severity: p2
files_affected:
  - scripts/blast-radius.sh
---

## Problem

Scripts that work on Linux/macOS silently fail or produce wrong results under
Windows Git Bash. Four specific traps were hit during blast-radius.sh development:

1. `grep -P` returns empty output (no error)
2. `((COUNTER++))` exits the script under `set -e`
3. `command | while read` loses variable writes
4. Unanchored `sed` patterns match prose in markdown

## Root cause

Git Bash ships a minimal GNU toolchain. `grep -P` (PCRE) is not compiled in.
Bash arithmetic commands return exit code based on the evaluated value — `((0))`
is falsy and triggers `set -e`. Pipe right-hand sides run in subshells where
variable assignments are invisible to the parent.

## Solution

### Trap 1 — grep -P silently fails

```bash
# BROKEN on Git Bash — returns nothing, no error
grep -oP '(?:export\s+)?function\s+\K\w+' file.js

# FIXED — use sed with POSIX patterns
sed -n 's/^[[:space:]]*function[[:space:]]\+\([a-zA-Z_$][a-zA-Z0-9_$]*\).*/\1/p' file.js
```

### Trap 2 — arithmetic under set -e

```bash
# BROKEN — exits when COUNTER is 0 (evaluates to falsy)
((COUNTER++))

# FIXED — arithmetic expansion doesn't trigger set -e
COUNTER=$((COUNTER + 1))
```

### Trap 3 — pipe subshell loses state

```bash
# BROKEN — TOTAL is 0 after the loop
TOTAL=0
some_command | while read -r line; do
    TOTAL=$((TOTAL + 1))
done
echo "$TOTAL"  # prints 0

# FIXED — heredoc keeps loop in current shell
OUTPUT=$(some_command)
while read -r line; do
    TOTAL=$((TOTAL + 1))
done <<< "$OUTPUT"
```

### Trap 4 — unanchored sed matches prose

```bash
# BROKEN — matches "this function checks if..." in comments
sed -n 's/.*function[[:space:]]\+\([a-zA-Z_]*\).*/\1/p' file.sh

# FIXED — anchor to start-of-line
sed -n 's/^[[:space:]]*function[[:space:]]\+\([a-zA-Z_]*\).*/\1/p' file.sh
```

## Prevention

- Never use `grep -P` in cross-platform scripts — use `grep -E` or `sed`
- Never use bare `((expr))` under `set -e` — use `$((expr))` assignment
- Never use `cmd | while read` for stateful loops — use `<<< "$var"` or `< <(cmd)`
- Always anchor `sed` patterns with `^` to avoid matching prose
- Run `shellcheck -x` before committing shell scripts
- Add `.claude/rules/shell-scripts.md` checklist to code review

## Related

- `.claude/rules/shell-scripts.md` — full prevention rules
- `docs/CODE-STANDARDS.md` Section 7 — shell script checklist
- `docs/solutions/blast-radius-patterns.md` — technical patterns in blast-radius.sh
