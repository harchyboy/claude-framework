# Shell Script Rules
# Applies to: **/*.sh, bash hooks, CLI tools, and any script files in scripts/

## Prevention: Blast Radius Issues

These rules directly address five patterns that silently fail or create massive false positive blast radii.

### 1. Platform-Aware Regex (Perl regex unavailable on Git Bash)

**Issue:** `grep -P` (Perl regex) silently fails on Windows Git Bash — returns no output, no error message. The script continues with an empty result set, causing silent logic failures.

**Prevention:**
- **Never use `grep -P`** — not portable to Git Bash, MSYS2, or busybox environments.
- Use `grep -E` (extended regex) — supported everywhere. If you need Perl features, use `perl -ne` directly instead.
- In hooks and cross-platform scripts, always test with `bash --version` + check OS (`uname -s`).
- For platform-specific logic, branch explicitly:
  ```bash
  case "$(uname -s)" in
    MINGW*|MSYS*) use_grep_E_instead ;;
    *) use_grep_P ;;
  esac
  ```
- When downgrading from `grep -P` to `grep -E`, audit the regex. Some Perl features (lookahead, backreferences in certain contexts) don't translate directly.

**Verification:**
- Test grep commands on both Linux and Git Bash before committing.
- Add `-E` explicitly in the grep call; never rely on default regex mode.

---

### 2. Anchored Patterns in sed (prevent prose matches)

**Issue:** Unanchored sed patterns like `s/.*function\s+\(name\).*/\1/p` match anywhere in a line, including markdown files where the pattern appears as documentation text, not code. This inflates blast radius with false positives.

**Prevention:**
- **Always anchor sed patterns to line structure:**
  - Use `^` and `$` to match start and end of line.
  - Prefix patterns with context that distinguishes code from prose (e.g., `^function ` not just `function`).
  - For multi-line patterns, use `sed -z` (null-terminated) or switch to `awk` for clearer intent.

**Example (BAD — matches in comments and markdown):**
```bash
grep -r "function.*name" . | sed 's/.*function\s\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/'
```

**Example (GOOD — anchored and explicit):**
```bash
grep -r "^function [a-zA-Z_]" . | sed 's/^function \([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/'
```

**Advanced:** When analyzing code files, exclude documentation paths upfront:
```bash
git ls-files --exclude-standard | grep -v -E '\.(md|txt|doc)$' | xargs grep "^function"
```

**Verification:**
- Run your pattern against real codebases. Spot-check 3-5 matches to confirm they're actual code, not prose.
- Check against both source files and docs/ directory to confirm false positives are absent.

---

### 3. Arithmetic in set -e Scripts (avoid implicit failure on 0→1)

**Issue:** `set -e` treats any non-zero exit code as fatal. Arithmetic expansions like `((COUNTER++))` return the value of the variable after increment. When `COUNTER` goes from 0→1, `((COUNTER++))` returns 1 (true/non-zero), and `set -e` exits the script.

**Prevention:**
- **Never use bare `((VAR++))`** or `((VAR+=N))` in `set -e` scripts.
- Wrap in explicit truthiness checks or non-failing contexts:
  ```bash
  # BAD in set -e
  ((COUNTER++))  # Exits script if COUNTER was 0

  # GOOD — separate the increment from the return value
  COUNTER=$((COUNTER + 1))  # Does not trigger set -e

  # OR — explicit context
  ((COUNTER++)) || true  # Disarm the exit

  # OR — use if statement
  if ((COUNTER < MAX)); then
    ((COUNTER++))
  fi
  ```

- If you must track state in a loop, prefer array indices or string counters:
  ```bash
  LINES=()
  while read -r line; do
    LINES+=("$line")  # Array append never fails
  done < input.txt
  FINAL_COUNT=${#LINES[@]}
  ```

**Verification:**
- Run the script with `bash -x` to see each arithmetic step.
- Insert a `set +e` boundary before arithmetic operations that should not cause exit:
  ```bash
  set +e
  ((COUNTER++))
  set -e
  ```
- Test with COUNTER=0 explicitly to trigger the edge case.

---

### 4. Pipe Subshell Isolation (while read in pipes loses variables)

**Issue:** When you use `command | while read VAR; do ... done`, the while loop runs in a subshell. Any variable assignments inside the loop are lost when the subshell exits. This silently corrupts the script state.

**Prevention:**
- **Never use pipe-to-while for stateful operations:**
  ```bash
  # BAD — COUNTER and TOTAL are lost at the end
  cat file.txt | while read line; do
    COUNTER=$((COUNTER + 1))
    TOTAL="$TOTAL $line"
  done
  echo "Found $COUNTER lines" # COUNTER is still 0

  # GOOD — use process substitution (no subshell)
  while read line; do
    COUNTER=$((COUNTER + 1))
    TOTAL="$TOTAL $line"
  done < file.txt
  echo "Found $COUNTER lines" # COUNTER is correct
  ```

- Use `<()` process substitution or direct redirection (`< file.txt`) instead of pipes.
- If you must pipe (e.g., `grep ... | while`), move stateful operations outside the loop:
  ```bash
  # If you must use pipe
  RESULTS=()
  grep pattern file.txt | while read line; do
    RESULTS+=("$line")  # This is lost in the subshell
  done

  # Instead: collect in a file or use a temp variable
  RESULTS=$(grep pattern file.txt)
  while read line; do
    # process $line
  done <<< "$RESULTS"
  ```

**Verification:**
- Add explicit output inside the loop (to stderr) to confirm it executes:
  ```bash
  command | while read var; do
    echo "DEBUG: processed $var" >&2
    COUNTER=$((COUNTER + 1))
  done
  echo "COUNTER=$COUNTER"  # Check if it's correct
  ```
- If COUNTER is 0 when you expect >0, you hit the subshell trap.

---

### 5. Function Naming (avoid generic names for blast radius analysis)

**Issue:** Generic function names like `log()`, `fail()`, `main()` match everywhere in a codebase. When analyzing blast radius, these functions appear as "transitively affecting" thousands of files because they're called from many places. This creates massive false-positive blast radii that obscure real impact.

**Prevention:**
- **Use scoped, descriptive function names:**
  - Include the module or domain: `blast_radius_log()` not `log()`
  - Include the action: `git_get_changed_files()` not `get_files()`
  - Use underscores to separate domains: `blast_radius_run()`, `blast_radius_parse_output()`

**Naming convention for shell scripts:**
```bash
# BAD — too generic
log() { echo "$1" >&2; }
fail() { echo "$1" >&2; exit 1; }
main() { ...; }

# GOOD — scoped to the tool
blast_radius_log() { echo "[blast-radius] $1" >&2; }
blast_radius_die() { echo "[blast-radius] FATAL: $1" >&2; exit 1; }
blast_radius_main() { ...; }

# OR — module prefix matches filename
if_get_changed_files() { ...; }
if_parse_impact() { ...; }
```

**Verification:**
- Before commit, run a search to confirm your functions are only called from expected places:
  ```bash
  grep -r "blast_radius_log" . | wc -l  # Should be small (< 20)
  grep -r "^log()" . | wc -l            # Generic names match everywhere
  ```
- Add a check to blast-radius.sh itself: filter out generic names from the dependency analysis:
  ```bash
  # In blast-radius.sh, skip files that ONLY call generic functions
  GENERIC_FUNCS=("log" "fail" "main" "usage")
  ```

---

## Testing Requirements for Shell Scripts

### Unit-testable patterns
- Extract logic into small, testable functions.
- Use dependency injection: pass file paths, variables as arguments, not globals.
- Mock external commands: wrap `git`, `grep`, `curl` in testable functions.

### Pre-commit verification
- **Shellcheck:** Run `shellcheck -x *.sh` on all scripts before commit. Fix all warnings.
- **Platform test:** Test on both Linux and Git Bash (or WSL) if the script is cross-platform.
- **Dry-run:** Add `--dry-run` mode to dangerous scripts (e.g., blast-radius-check.sh, pre-commit gates).
- **No hidden failures:** If a script uses pipes, temp files, or arithmetic, add explicit log output at every step.

---

## Checklist (use before committing shell scripts)

- [ ] No `grep -P` — use `grep -E` instead
- [ ] sed/awk patterns are anchored with `^` and `$` or use bounded contexts
- [ ] No bare `((VAR++))` in `set -e` scripts — wrap in `|| true` or use `VAR=$((VAR+1))`
- [ ] No pipe-to-while for stateful operations — use `< file.txt` or process substitution instead
- [ ] Function names are scoped and descriptive, not generic (`log()`, `fail()`, `main()`)
- [ ] `shellcheck -x script.sh` passes with zero warnings
- [ ] Tested on both Linux and Git Bash (if cross-platform)
- [ ] Temp files are cleaned up (no `.tmp` orphans)
- [ ] Script exits with explicit status on error, not just "set -e magic"
- [ ] No secrets in log output — sanitise API keys, tokens, paths to user home dirs
