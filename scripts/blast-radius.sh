#!/bin/bash
# blast-radius.sh — Determine what code is affected by a set of changes
# Hartz Claude Framework
#
# Given a git diff (or explicit files), extracts changed functions/classes/methods
# and traces callers across the codebase. Outputs a ranked blast-radius report
# showing what else might break.
#
# Usage:
#   bash scripts/blast-radius.sh [options]
#
# Options:
#   --base <ref>       Base ref for diff (default: auto-detect merge-base with main)
#   --head <ref>       Head ref for diff (default: HEAD)
#   --files <f1,f2>    Explicit file list instead of git diff
#   --depth <n>        Max caller-chain depth to trace (default: 3)
#   --json             Output as JSON instead of text
#   --quiet            Minimal output — just the affected file list
#   --help             Show this help
#
# Output: ranked list of affected files with call depth and caller chains
#
# Examples:
#   blast-radius.sh                          # Changes on current branch vs main
#   blast-radius.sh --base HEAD~3            # Last 3 commits
#   blast-radius.sh --files src/auth.ts      # Specific file
#   blast-radius.sh --depth 5 --json         # Deep trace, JSON output

set -euo pipefail

# ─── Defaults ──────────────────────────────────────────────────────────────────

BASE_REF=""
HEAD_REF="HEAD"
EXPLICIT_FILES=""
MAX_DEPTH=3
JSON_OUTPUT=false
QUIET=false

# ─── Colours ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Parse args ────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)    BASE_REF="$2"; shift ;;
    --head)    HEAD_REF="$2"; shift ;;
    --files)   EXPLICIT_FILES="$2"; shift ;;
    --depth)   MAX_DEPTH="$2"; shift ;;
    --json)    JSON_OUTPUT=true ;;
    --quiet)   QUIET=true ;;
    --help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# ─── Helpers ───────────────────────────────────────────────────────────────────

log() {
  if [[ "$QUIET" == "false" && "$JSON_OUTPUT" == "false" ]]; then
    echo -e "$1"
  fi
}

# Temporary files for intermediate results
TMPDIR_BR=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BR"' EXIT

CHANGED_SYMBOLS="$TMPDIR_BR/changed_symbols.txt"
AFFECTED_FILES="$TMPDIR_BR/affected_files.txt"
CALLER_CHAINS="$TMPDIR_BR/caller_chains.txt"
RESULTS_JSON="$TMPDIR_BR/results.json"

touch "$CHANGED_SYMBOLS" "$AFFECTED_FILES" "$CALLER_CHAINS"

# ─── Step 1: Get changed files ────────────────────────────────────────────────

if [[ -n "$EXPLICIT_FILES" ]]; then
  CHANGED_FILES=$(echo "$EXPLICIT_FILES" | tr ',' '\n')
else
  if [[ -z "$BASE_REF" ]]; then
    # Auto-detect: merge-base with main/master, fallback to HEAD~1
    BASE_REF=$(git merge-base HEAD main 2>/dev/null \
            || git merge-base HEAD master 2>/dev/null \
            || echo "HEAD~1")
  fi
  CHANGED_FILES=$(git diff --name-only "$BASE_REF".."$HEAD_REF" 2>/dev/null || true)
fi

if [[ -z "$CHANGED_FILES" ]]; then
  log "${YELLOW}No changed files detected.${NC}"
  exit 0
fi

CHANGED_FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
log "${BOLD}═══════════════════════════════════════${NC}"
log "${BOLD}BLAST RADIUS ANALYSIS${NC}"
log "${BOLD}═══════════════════════════════════════${NC}"
log ""
log "${CYAN}Changed files: ${CHANGED_FILE_COUNT}${NC}"

# ─── Step 2: Extract changed symbols (functions, classes, methods) ─────────────

# Get the actual diff content to find changed function/class/method names
if [[ -n "$EXPLICIT_FILES" ]]; then
  # For explicit files, treat all symbols in those files as changed
  DIFF_CONTENT=""
  for f in $CHANGED_FILES; do
    if [[ -f "$f" ]]; then
      DIFF_CONTENT+=$(cat "$f")
      DIFF_CONTENT+=$'\n'
    fi
  done
else
  DIFF_CONTENT=$(git diff "$BASE_REF".."$HEAD_REF" 2>/dev/null || true)
fi

# Extract symbol names from diff hunks
# Matches: function declarations, class declarations, method definitions, exports
# Uses sed instead of grep -P for portability (Git Bash on Windows lacks PCRE)
# IMPORTANT: Patterns are anchored to start-of-line (with optional whitespace/keywords)
# to avoid matching prose like "this function checks..." in markdown/comments
extract_symbols() {
  local content="$1"

  # JS/TS: function declarations (must start at line start or after export/async)
  echo "$content" | sed -n 's/^[[:space:]]*\(export[[:space:]]\+\)\{0,1\}\(async[[:space:]]\+\)\{0,1\}function[[:space:]]\+\([a-zA-Z_$][a-zA-Z0-9_$]*\).*/\3/p' 2>/dev/null || true

  # JS/TS: class declarations
  echo "$content" | sed -n 's/^[[:space:]]*\(export[[:space:]]\+\)\{0,1\}class[[:space:]]\+\([a-zA-Z_$][a-zA-Z0-9_$]*\).*/\2/p' 2>/dev/null || true

  # JS/TS: const/let/var arrow functions or function expressions
  echo "$content" | sed -n 's/^[[:space:]]*\(export[[:space:]]\+\)\{0,1\}\(const\|let\|var\)[[:space:]]\+\([a-zA-Z_$][a-zA-Z0-9_$]*\)[[:space:]]*=[[:space:]]*\(async[[:space:]]*\)\{0,1\}(.*/\3/p' 2>/dev/null || true

  # Python: def and class (must start at line beginning with optional whitespace)
  echo "$content" | sed -n 's/^[[:space:]]*\(async[[:space:]]\+\)\{0,1\}def[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^[[:space:]]*class[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' 2>/dev/null || true

  # Go: func, type struct/interface (must start at line beginning)
  echo "$content" | sed -n 's/^func[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^type[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]\+struct.*/\1/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^type[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]\+interface.*/\1/p' 2>/dev/null || true

  # Rust: fn, struct, enum, trait, impl (anchored with optional pub/whitespace)
  echo "$content" | sed -n 's/^[[:space:]]*\(pub[[:space:]]\+\)\{0,1\}fn[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^[[:space:]]*\(pub[[:space:]]\+\)\{0,1\}struct[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^[[:space:]]*\(pub[[:space:]]\+\)\{0,1\}enum[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^[[:space:]]*\(pub[[:space:]]\+\)\{0,1\}trait[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^[[:space:]]*impl[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' 2>/dev/null || true

  # Shell: function_name() or function function_name (must start at line beginning)
  echo "$content" | sed -n 's/^[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]*()[[:space:]]*{.*/\1/p' 2>/dev/null || true
  echo "$content" | sed -n 's/^[[:space:]]*function[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p' 2>/dev/null || true
}

# Extract relevant lines — for git diffs, only the + lines; for explicit files, all lines
if [[ -n "$EXPLICIT_FILES" ]]; then
  ADDED_LINES="$DIFF_CONTENT"
else
  ADDED_LINES=$(echo "$DIFF_CONTENT" | grep '^[+]' | sed 's/^+//' 2>/dev/null || true)
fi

# Filter extracted symbols: remove keywords, short words, and common noise
is_noise() {
  local sym="$1"
  # Too short — likely a false positive from sed
  [[ ${#sym} -lt 3 ]] && return 0
  # Language keywords and builtins
  case "$sym" in
    if|else|for|while|do|done|return|import|export|from|const|let|var|new|this|true|false|null|undefined|void|type|interface|enum|async|await|try|catch|finally|throw|switch|case|break|continue|default|with|yield|delete|typeof|instanceof|in|of|get|set|static|super|extends|implements|constructor|public|private|protected|abstract|readonly|override|declare|module|namespace|require|__init__|self|None|True|False|print|len|range|str|int|float|list|dict|tuple|set|bool|pass|raise|except|lambda|global|nonlocal|assert|class|def|func|struct|impl|trait|pub|mut|mod|use|crate|extern|unsafe|where|dyn|ref|match|loop|move|then|elif|fi|esac)
      return 0 ;;
    # Common short utility names that cause noise (real but too generic)
    log|err|warn|info|fail|pass|skip|main|init|ok|die|usage|help|debug|trace|noop|todo|done|echo|exit|abort|emit|send|recv|push|pull|call|bind|wrap|load|save|dump|show|hide|next|prev|step|wait|stop|ping|tick|redo|undo|hash)
      return 0 ;;
    # Extremely common shell helper names
    h1|h2|h3|red|green|blue|yellow|cyan|bold|dim|reset|color|checks|returns|exists|format)
      return 0 ;;
  esac
  return 1
}

# Write symbols directly (no subshell pipe issue)
RAW_SYMBOLS=$(extract_symbols "$ADDED_LINES" | sort -u)
while read -r sym; do
  [[ -z "$sym" ]] && continue
  if ! is_noise "$sym"; then
    echo "$sym" >> "$CHANGED_SYMBOLS"
  fi
done <<< "$RAW_SYMBOLS"

SYMBOL_COUNT=$(wc -l < "$CHANGED_SYMBOLS" | tr -d ' ')
log "${CYAN}Changed symbols: ${SYMBOL_COUNT}${NC}"
log ""

if [[ "$SYMBOL_COUNT" -eq 0 ]]; then
  log "${YELLOW}No function/class symbols detected in changes.${NC}"
  log "${DIM}(Changes may be config, data, or non-code files)${NC}"

  # Still report changed files even without symbols
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo '{"changed_files":['
    first=true
    echo "$CHANGED_FILES" | while read -r f; do
      if [[ "$first" == "true" ]]; then first=false; else echo ","; fi
      echo "  \"$f\""
    done
    echo '],"symbols":[],"affected_files":[],"depth":0}'
  fi
  exit 0
fi

# ─── Step 3: Trace callers at each depth level ────────────────────────────────

# Build file extension filter for searching (skip binaries, non-code, node_modules, etc.)
SEARCH_EXCLUDES="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir=.next --exclude-dir=__pycache__ --exclude-dir=target --exclude-dir=vendor --exclude-dir=.venv --exclude-dir=venv --exclude-dir=agent_logs --exclude=*.min.js --exclude=*.min.css --exclude=*.map --exclude=*.lock --exclude=package-lock.json --exclude=yarn.lock --exclude=*.md --exclude=*.log --exclude=*.txt --exclude=*.json --exclude=*.yaml --exclude=*.yml --exclude=*.toml --exclude=*.cfg --exclude=*.ini --exclude=*.csv"

# Track all affected files across depth levels
declare -A SEEN_FILES
declare -A FILE_DEPTH
declare -A FILE_VIA

# Mark changed files as depth 0
while read -r f; do
  if [[ -n "$f" ]]; then
    SEEN_FILES["$f"]=1
    FILE_DEPTH["$f"]=0
    FILE_VIA["$f"]="(directly changed)"
  fi
done <<< "$CHANGED_FILES"

# For each depth level, grep for symbol references
CURRENT_SYMBOLS=$(cat "$CHANGED_SYMBOLS")

for (( depth=1; depth<=MAX_DEPTH; depth++ )); do
  NEW_SYMBOLS=""
  FOUND_NEW=false

  while read -r sym; do
    [[ -z "$sym" ]] && continue

    # Search for references to this symbol across the codebase
    # Use word-boundary matching to avoid partial matches
    MATCHES=$(grep -rl $SEARCH_EXCLUDES -w "$sym" . 2>/dev/null || true)

    while read -r match_file; do
      [[ -z "$match_file" ]] && continue
      # Normalize path
      match_file="${match_file#./}"

      # Skip if already seen at a closer depth
      if [[ -n "${SEEN_FILES[$match_file]+x}" ]]; then
        continue
      fi

      SEEN_FILES["$match_file"]=1
      FILE_DEPTH["$match_file"]=$depth
      FILE_VIA["$match_file"]="$sym"
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

  # Filter new symbols through the same noise filter before next depth
  FILTERED_SYMBOLS=""
  while read -r sym; do
    [[ -z "$sym" ]] && continue
    if ! is_noise "$sym"; then
      FILTERED_SYMBOLS+="$sym"$'\n'
    fi
  done <<< "$(echo "$NEW_SYMBOLS" | sort -u)"
  CURRENT_SYMBOLS="$FILTERED_SYMBOLS"
  DEPTH_COUNT=0
  for f in "${!FILE_DEPTH[@]}"; do
    if [[ "${FILE_DEPTH[$f]}" -eq $depth ]]; then
      DEPTH_COUNT=$((DEPTH_COUNT + 1))
    fi
  done
  log "${DIM}Depth $depth: +${DEPTH_COUNT} files${NC}"
done

# ─── Step 4: Build output ─────────────────────────────────────────────────────

# Collect results sorted by depth
TOTAL_AFFECTED=0
for f in "${!FILE_DEPTH[@]}"; do
  if [[ "${FILE_DEPTH[$f]}" -gt 0 ]]; then
    TOTAL_AFFECTED=$((TOTAL_AFFECTED + 1))
    echo "${FILE_DEPTH[$f]}|${f}|${FILE_VIA[$f]}" >> "$AFFECTED_FILES"
  fi
done

# Sort by depth then filename
if [[ -s "$AFFECTED_FILES" ]]; then
  sort -t'|' -k1n -k2 "$AFFECTED_FILES" > "$AFFECTED_FILES.sorted"
  mv "$AFFECTED_FILES.sorted" "$AFFECTED_FILES"
fi

# ─── JSON output ───────────────────────────────────────────────────────────────

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "{"
  echo "  \"base_ref\": \"$BASE_REF\","
  echo "  \"head_ref\": \"$HEAD_REF\","
  echo "  \"changed_file_count\": $CHANGED_FILE_COUNT,"
  echo "  \"symbol_count\": $SYMBOL_COUNT,"
  echo "  \"affected_file_count\": $TOTAL_AFFECTED,"
  echo "  \"max_depth\": $MAX_DEPTH,"
  echo "  \"changed_files\": ["
  first=true
  while read -r f; do
    [[ -z "$f" ]] && continue
    if [[ "$first" == "true" ]]; then first=false; else echo ","; fi
    printf '    "%s"' "$f"
  done <<< "$CHANGED_FILES"
  echo ""
  echo "  ],"
  echo "  \"symbols\": ["
  first=true
  while read -r sym; do
    [[ -z "$sym" ]] && continue
    if [[ "$first" == "true" ]]; then first=false; else echo ","; fi
    printf '    "%s"' "$sym"
  done < "$CHANGED_SYMBOLS"
  echo ""
  echo "  ],"
  echo "  \"affected_files\": ["
  if [[ -s "$AFFECTED_FILES" ]]; then
    first=true
    while IFS='|' read -r d f v; do
      if [[ "$first" == "true" ]]; then first=false; else echo ","; fi
      printf '    {"file": "%s", "depth": %s, "via": "%s"}' "$f" "$d" "$v"
    done < "$AFFECTED_FILES"
    echo ""
  fi
  echo "  ]"
  echo "}"
  exit 0
fi

# ─── Quiet output ─────────────────────────────────────────────────────────────

if [[ "$QUIET" == "true" ]]; then
  if [[ -s "$AFFECTED_FILES" ]]; then
    while IFS='|' read -r d f v; do
      echo "$f"
    done < "$AFFECTED_FILES"
  fi
  exit 0
fi

# ─── Text report ──────────────────────────────────────────────────────────────

log ""
log "${BOLD}──────────────────────────────────────${NC}"
log "${BOLD}CHANGED FILES (depth 0)${NC}"
log "${BOLD}──────────────────────────────────────${NC}"
echo "$CHANGED_FILES" | while read -r f; do
  [[ -z "$f" ]] && continue
  echo -e "  ${GREEN}$f${NC}"
done

if [[ "$TOTAL_AFFECTED" -gt 0 ]]; then
  log ""
  log "${BOLD}──────────────────────────────────────${NC}"
  log "${BOLD}BLAST RADIUS (${TOTAL_AFFECTED} affected files)${NC}"
  log "${BOLD}──────────────────────────────────────${NC}"

  PREV_DEPTH=0
  while IFS='|' read -r depth file via; do
    if [[ "$depth" -ne "$PREV_DEPTH" ]]; then
      echo ""
      case $depth in
        1) echo -e "  ${YELLOW}Depth 1 — Direct callers${NC}" ;;
        2) echo -e "  ${YELLOW}Depth 2 — Callers of callers${NC}" ;;
        *) echo -e "  ${YELLOW}Depth $depth${NC}" ;;
      esac
      PREV_DEPTH=$depth
    fi

    # Classify file risk
    RISK=""
    case "$file" in
      *test*|*spec*|*__tests__*) RISK="${DIM}(test)${NC}" ;;
      *migration*|*schema*|*.sql) RISK="${RED}(data)${NC}" ;;
      *api/*|*route*|*handler*|*controller*) RISK="${RED}(api)${NC}" ;;
      *component*|*page*|*layout*|*view*) RISK="${CYAN}(ui)${NC}" ;;
      *.md|*.txt|*.json|*.yaml|*.yml) RISK="${DIM}(config)${NC}" ;;
    esac

    echo -e "    ${file}  ${DIM}via ${via}${NC}  ${RISK}"
  done < "$AFFECTED_FILES"
else
  log ""
  log "${GREEN}No additional files affected beyond the changed set.${NC}"
fi

# ─── Summary ───────────────────────────────────────────────────────────────────

log ""
log "${BOLD}──────────────────────────────────────${NC}"
log "${BOLD}SUMMARY${NC}"
log "${BOLD}──────────────────────────────────────${NC}"
log "  Changed files:   ${CHANGED_FILE_COUNT}"
log "  Changed symbols: ${SYMBOL_COUNT}"
log "  Affected files:  ${TOTAL_AFFECTED}"
log "  Max depth:       ${MAX_DEPTH}"

# Risk assessment
if [[ "$TOTAL_AFFECTED" -gt 20 ]]; then
  log ""
  log "  ${RED}${BOLD}HIGH BLAST RADIUS${NC} — Consider splitting this change"
elif [[ "$TOTAL_AFFECTED" -gt 10 ]]; then
  log ""
  log "  ${YELLOW}${BOLD}MODERATE BLAST RADIUS${NC} — Review affected files carefully"
elif [[ "$TOTAL_AFFECTED" -gt 0 ]]; then
  log ""
  log "  ${GREEN}${BOLD}LOW BLAST RADIUS${NC} — Changes are well-contained"
else
  log ""
  log "  ${GREEN}${BOLD}ZERO BLAST RADIUS${NC} — No transitive dependencies found"
fi

log ""
