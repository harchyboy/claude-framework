# Blast-Radius Technical Patterns

> Non-obvious technical solutions in scripts/blast-radius.sh
> Last updated: 2026-03-17

## 1. Language-Agnostic Symbol Extraction via Sed

### The Pattern
The script uses `sed` with anchored line-start patterns instead of PCRE (`grep -P`), for **Windows/Git Bash compatibility**. Each language (JS, TS, Python, Go, Rust, Shell) has multiple patterns targeting the specific declaration syntax.

### Key Technique: Anchoring to Line Start
```bash
# Pattern structure: ^[[:space:]]*OPTIONAL_KEYWORDS*declaration_keyword[[:space:]]+CAPTURED_NAME
sed -n 's/^[[:space:]]*\(export[[:space:]]\+\)\{0,1\}function[[:space:]]\+\([a-zA-Z_$][a-zA-Z0-9_$]*\).*/\3/p'
```

**Why this works:**
- `^` anchors to line start (after any indentation)
- `[[:space:]]*` permits leading whitespace (methods in classes, etc.)
- `\{0,1\}` matches optional keywords (export, async, pub, etc.) **one time only**
- Capture group `\(name\)` extracts the symbol, not the keywords
- `.*/` consumes rest of line (trailing params, return types, etc.)
- `s//print` via `-n 's/.../p'` only outputs matched patterns

**Critical insight:** Don't use PCRE. POSIX extended regex with `sed -n 's/.../p'` works on all platforms including Git Bash on Windows where `grep -P` fails.

### Language-Specific Patterns
Each language has multiple patterns for different declaration styles:

**JavaScript/TypeScript:**
- Function declarations: `function name(...) {`
- Async functions: `async function name(...) {`
- Exports: `export function name(...)` or `export async function name(...)`
- Arrow/const functions: `const name = (...) => {` or `const name = async (...) => {`
- Classes: `export class Name {`

**Python:**
- Async functions: `async def name(...):` (leading whitespace permitted for indentation)
- Methods within classes: detected by indentation context
- Classes: `class Name(parent):`

**Go:**
- Functions: `func Name(...)` (no optional export; Go uses capitalization)
- Structs: `type Name struct`
- Interfaces: `type Name interface`

**Rust:**
- Pub functions: `pub fn name(...) {` (pub is optional)
- Structs/enums/traits: `pub struct Name`, `pub enum Name`, `pub trait Name`
- Impl blocks: `impl Name` (extracts the type being implemented)

**Shell:**
- Posix style: `name() { ... }` (no optional keywords)
- Function keyword: `function name { ... }`

### How to Extend
To add a new language pattern:
1. Identify all declaration syntaxes (functions, classes, methods, interfaces)
2. Write sed pattern with `^[[:space:]]*` anchor
3. Optional keywords use `\{0,1\}` not `*` (matches exactly once, not zero or more)
4. Test against indented code (methods, nested functions)

---

## 2. Noise Filtering: The is_noise Function

### The Problem
Symbol extraction produces many false positives: keywords (`function`, `class`, `def`), generic utilities (`log`, `warn`, `main`), and short names that are obviously not real exports.

### The Solution
```bash
is_noise() {
  local sym="$1"
  # Too short — likely a false positive from sed
  [[ ${#sym} -lt 3 ]] && return 0
  # Language keywords and builtins
  case "$sym" in
    if|else|for|while|do|done|return|import|export|...|pub|mut|mod|...)
      return 0 ;;
    # Common short utility names
    log|err|warn|info|fail|pass|skip|main|init|ok|die|usage|...)
      return 0 ;;
    # Extremely common shell helper names
    h1|h2|h3|red|green|blue|yellow|cyan|bold|dim|reset|...)
      return 0 ;;
  esac
  return 1  # Not noise — keep it
}
```

**Why this works:**
1. **Length filter** (`${#sym} -lt 3`): Catches one-letter variables and 2-letter abbreviations
2. **Keyword blacklist**: All language keywords that might leak through the sed patterns (e.g., `new`, `this`, `type`, `class`)
3. **Utility function blacklist**: Functions that exist in almost every codebase (`log`, `warn`, `fail`, `main`, `init`) — these are noise unless deeply scoped
4. **Shell-specific color/formatting helpers**: Catches helper functions like `h1`, `red`, `cyan` that are typically infrastructure, not business logic

### Why It's Not Perfect (and That's OK)
- Doesn't catch context-free `process`, `handle`, `check`, `validate` (too generic but sometimes meaningful)
- Doesn't filter per-language keyword sets (Python `pass` is a keyword, not a function, but won't leak through sed anyway)
- Trade-off: False negatives (missing some noise) are better than false positives (incorrectly flagging utilities as important)

### Extending the Filter
Add common names in your codebase to the case statements:
```bash
# Add your project-specific noise patterns:
case "$sym" in
  # ... existing cases ...
  transform|format|parse|encode|decode|serialize|deserialize)  # too generic
    return 0 ;;
esac
```

---

## 3. Depth-Based Caller Tracing Algorithm

### The Challenge
Given `changed_symbols` (functions/classes that changed), find all files that reference them. Then, from those files, extract their symbols and repeat at the next depth level. Stop when no new files are found or depth limit is reached.

### The Algorithm
```bash
for (( depth=1; depth<=MAX_DEPTH; depth++ )); do
  NEW_SYMBOLS=""
  FOUND_NEW=false

  while read -r sym; do
    [[ -z "$sym" ]] && continue

    # Search for references: -rl (recursive, list filenames), -w (word boundary)
    MATCHES=$(grep -rl $SEARCH_EXCLUDES -w "$sym" . 2>/dev/null || true)

    while read -r match_file; do
      [[ -z "$match_file" ]] && continue
      match_file="${match_file#./}"  # Normalize: ./path → path

      # Skip if already seen at a closer depth
      if [[ -n "${SEEN_FILES[$match_file]+x}" ]]; then
        continue
      fi

      SEEN_FILES["$match_file"]=1
      FILE_DEPTH["$match_file"]=$depth
      FILE_VIA["$match_file"]="$sym"  # Track which symbol brought us here
      FOUND_NEW=true

      # Extract symbols from this newly affected file for next depth
      if [[ -f "$match_file" && $depth -lt $MAX_DEPTH ]]; then
        NEW_FILE_SYMS=$(extract_symbols "$(cat "$match_file")" 2>/dev/null | head -20 || true)
        if [[ -n "$NEW_FILE_SYMS" ]]; then
          NEW_SYMBOLS+="$NEW_FILE_SYMS"$'\n'
        fi
      fi
    done <<< "$MATCHES"
  done <<< "$CURRENT_SYMBOLS"

  if [[ "$FOUND_NEW" == "false" ]]; then
    log "${DIM}Depth $depth: no new files found. Stopping.${NC}"
    break
  fi

  # Filter new symbols before next depth
  FILTERED_SYMBOLS=""
  while read -r sym; do
    [[ -z "$sym" ]] && continue
    if ! is_noise "$sym"; then
      FILTERED_SYMBOLS+="$sym"$'\n'
    fi
  done <<< "$(echo "$NEW_SYMBOLS" | sort -u)"
  CURRENT_SYMBOLS="$FILTERED_SYMBOLS"
done
```

### Key Insights

**1. Word-Boundary Grep**
```bash
grep -rl $SEARCH_EXCLUDES -w "$sym" .
```
- `-w`: Match whole word only (avoid `validate` matching `validate_input`)
- `-r`: Recursive (traverse directories)
- `-l`: List filenames only (not matches) — huge performance win
- `$SEARCH_EXCLUDES`: Pre-built exclude directives (node_modules, .git, build, dist, etc.)

**2. Early Termination**
```bash
if [[ "$FOUND_NEW" == "false" ]]; then
  break
fi
```
Prevents expensive searching once no new files are discovered. Typical codebases reach a stable state by depth 2-3.

**3. Symbol Extraction from Newly Found Files**
```bash
if [[ -f "$match_file" && $depth -lt $MAX_DEPTH ]]; then
  NEW_FILE_SYMS=$(extract_symbols "$(cat "$match_file")" | head -20 || true)
fi
```
- Only extract symbols if file exists and we haven't hit max depth (optimization)
- `head -20`: Limit to 20 symbols per file (prevents explosion in large files)
- `|| true`: Prevents early exit on error (set -e)

**4. Duplicate Avoidance via Associative Arrays**
```bash
declare -A SEEN_FILES
declare -A FILE_DEPTH
declare -A FILE_VIA

if [[ -n "${SEEN_FILES[$match_file]+x}" ]]; then
  continue  # Already found at shallower depth
fi
SEEN_FILES["$match_file"]=1
```
- `${SEEN_FILES[$match_file]+x}` checks if key exists (not if value is truthy — important distinction)
- Prevents the same file being marked at multiple depths (we only mark once, at the first/shallowest depth)

**5. Noise Filter Between Depths**
Symbols extracted from newly found files are filtered through `is_noise()` before entering the next depth's search. This prevents the symbol set from exploding with utility functions.

### Complexity & Scaling
- **Best case**: `O(D × |S| × log(N))` where D = max depth, |S| = symbol count, N = file count
- **Worst case**: `O(D × |S| × F)` where F = total lines scanned (with grep)
- In practice: 100-300 files, 50-100 symbols, depth 3-4 typically completes in <5 seconds

---

## 4. Windows/Git Bash Portability Fixes

### Issue 1: PCRE Unavailable in Git Bash

**Original intent:** Use `grep -P` for powerful regex
```bash
# ❌ Fails on Windows Git Bash
grep -P 'pattern' file
```

**Solution:** Rewrite patterns for POSIX sed, not PCRE
```bash
# ✅ Works everywhere (POSIX-compliant sed)
sed -n 's/pattern/g/p' file
```

**Why:** `grep -P` (Perl regex) is unavailable in Git Bash for Windows. Use POSIX extended regex (available in `sed`, `awk`, and `/bin/grep`).

### Issue 2: Arithmetic in set -e Context

**Original intent:** Compute count with `$(( ... ))`
```bash
# ❌ If count is 0, arithmetic fails: "$(( 0 ))" → exit code 1 under set -e
DEPTH_COUNT=$((DEPTH_COUNT + 1))  # or: $(( count ))
```

**Solution:** Chain with `|| true` or use conditional context
```bash
# ✅ Option 1: Ignore arithmetic exit code
DEPTH_COUNT=$((DEPTH_COUNT + 1)) || true

# ✅ Option 2: Use in conditional (bash naturally ignores exit code)
if [[ $depth -lt $MAX_DEPTH ]]; then ...

# ✅ Option 3: Assign from non-zero expression
FILE_DEPTH["$match_file"]=$depth  # $depth is never zero in loop
```

**Why:** Under `set -e`, any command returning non-zero exits immediately. Arithmetic on zero (`$(( 0 ))`) returns exit code 1. Counter increments don't occur if previous value was zero.

**Applied in script:**
```bash
for (( depth=1; depth<=MAX_DEPTH; depth++ )); do  # Loop variable, never zero
  DEPTH_COUNT=0
  for f in "${!FILE_DEPTH[@]}"; do
    if [[ "${FILE_DEPTH[$f]}" -eq $depth ]]; then
      DEPTH_COUNT=$((DEPTH_COUNT + 1))  # ✅ Safe: happens in conditional context
    fi
  done
done
```

### Issue 3: Subshell Pipe Breaks set -e Return Values

**Original intent:** Pipe output while maintaining exit code
```bash
# ❌ set -e doesn't catch error if it's piped
extract_symbols "$ADDED_LINES" | sort -u  # Error in extract_symbols is lost!
```

**Solution:** Use here-string (`<<< ...`) or intermediate variable
```bash
# ✅ Option 1: Here-string (no subshell)
RAW_SYMBOLS=$(extract_symbols "$ADDED_LINES" | sort -u)
while read -r sym; do
  # Process $sym
done <<< "$RAW_SYMBOLS"

# ✅ Option 2: Intermediate variable then pipe (if needed)
TEMP=$(extract_symbols "$ADDED_LINES")
RAW_SYMBOLS=$(echo "$TEMP" | sort -u)
```

**Why:** When you pipe a command in bash, it runs in a subshell. Errors in the left side of the pipe are lost (exit code is the right side's). With `set -e`, the error doesn't propagate.

**Applied in script (line 194-201):**
```bash
# Write symbols directly (no subshell pipe issue)
RAW_SYMBOLS=$(extract_symbols "$ADDED_LINES" | sort -u)  # Store to variable first
while read -r sym; do
  [[ -z "$sym" ]] && continue
  if ! is_noise "$sym"; then
    echo "$sym" >> "$CHANGED_SYMBOLS"
  fi
done <<< "$RAW_SYMBOLS"  # Read from stored variable with here-string
```

This avoids piping `extract_symbols` directly into the `while` loop (which would hide errors).

---

## 5. File Search Excludes Strategy

### The Challenge
Grep a codebase without matching:
- Config files (YAML, JSON, TOML) — false positives on property names
- Lock files (package-lock.json, yarn.lock) — noise
- Minified JS (*.min.js) — unreadable, useless
- Source maps (*.map)
- Binary/compiled dirs (node_modules, dist, build, target, __pycache__)
- Documentation (*.md, *.txt) — matches function names in prose

### The Solution
```bash
SEARCH_EXCLUDES="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist \
  --exclude-dir=build --exclude-dir=.next --exclude-dir=__pycache__ \
  --exclude-dir=target --exclude-dir=vendor --exclude-dir=.venv \
  --exclude-dir=venv --exclude-dir=agent_logs \
  --exclude=*.min.js --exclude=*.min.css --exclude=*.map \
  --exclude=*.lock --exclude=package-lock.json --exclude=yarn.lock \
  --exclude=*.md --exclude=*.log --exclude=*.txt \
  --exclude=*.json --exclude=*.yaml --exclude=*.yml --exclude=*.toml \
  --exclude=*.cfg --exclude=*.ini --exclude=*.csv"
```

**Multi-dimensional filtering:**
1. **By directory** (`--exclude-dir`): Stop traversing known non-code directories
2. **By filename pattern** (`--exclude`): Skip specific file types
3. **By extension** (`--exclude=*.ext`): Catch all instances of config/lock/min/map files

**Why this order matters:**
- Directory exclusions first (cheaper — stops entire traversal)
- Wildcard patterns second (filters files before reading)
- Specific filenames last (targets known culprits)

**Optimization:** `--exclude-dir` uses filesystem traversal, vastly faster than checking every file:
```
grep -rl --exclude-dir=node_modules ... .  # Doesn't descend into node_modules at all
grep -rl --exclude='*/node_modules/*' ... .  # Still reads files, then filters
```

### Extending the Excludes
Add project-specific directories/files:
```bash
# For a monorepo with build outputs:
SEARCH_EXCLUDES="$SEARCH_EXCLUDES --exclude-dir=.next --exclude-dir=out"

# For Go projects with vendor and bin:
SEARCH_EXCLUDES="$SEARCH_EXCLUDES --exclude-dir=vendor --exclude-dir=bin"

# For projects with generated code (not desired for blast-radius):
SEARCH_EXCLUDES="$SEARCH_EXCLUDES --exclude-dir=generated --exclude=*_pb.go"
```

---

## 6. Handling Edge Cases & Error Resilience

### Empty Input
```bash
if [[ -z "$CHANGED_FILES" ]]; then
  log "${YELLOW}No changed files detected.${NC}"
  exit 0
fi
```
Exit early with zero code (not an error — expected for merge commits, etc.).

### Missing Symbols (Config-Only Changes)
```bash
if [[ "$SYMBOL_COUNT" -eq 0 ]]; then
  log "${YELLOW}No function/class symbols detected in changes.${NC}"
  # Still report changed files even without symbols
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo '{"changed_files":[...'
  fi
  exit 0
fi
```
Config changes (YAML, JSON, etc.) produce no symbols. Still valid output, just with zero affected files.

### Graceful Grep Failures
```bash
MATCHES=$(grep -rl $SEARCH_EXCLUDES -w "$sym" . 2>/dev/null || true)
```
Redirect stderr to /dev/null and append `|| true` to prevent exit on "no matches" (exit code 1 from grep).

### Safe File Checks
```bash
if [[ -f "$match_file" && $depth -lt $MAX_DEPTH ]]; then
  NEW_FILE_SYMS=$(extract_symbols "$(cat "$match_file")" 2>/dev/null | head -20 || true)
fi
```
- `-f` check before `cat` (prevents error on directories)
- `2>/dev/null` on extract (in case file encoding is problematic)
- `|| true` after pipeline (handle empty output gracefully)

---

## Summary: When You Need to Modify Blast-Radius

| Task | Pattern to Know |
|------|-----------------|
| Add a new language | Use `sed -n 's/^[[:space:]]*PATTERN/CAPTURE/p'` with line-start anchor. Test against indented code. |
| Reduce noise in results | Add function names to the `is_noise` case statement. Length < 3 and common utilities first. |
| Speed up blast-radius | Adjust `MAX_DEPTH` (2 is usually enough), increase `--exclude-dir` entries, or filter `--exclude=*.pattern` more aggressively. |
| Add new repo structure | Add `--exclude-dir=mydir` to `SEARCH_EXCLUDES` to skip build/generated dirs. |
| Handle special characters in symbol names | The sed patterns use `[a-zA-Z_$][a-zA-Z0-9_$]*` which matches JS `$var` and Rust identifiers. Extend character class if needed. |
| Fix false positives | Check if issue is extraction (sed patterns too broad) or noise filtering (add to `is_noise`). |
| Debug why a file isn't found | Verify grep isn't excluding it: `grep -rl $SEARCH_EXCLUDES -w SYMBOL .` manually. Check `is_noise` filtering. |

