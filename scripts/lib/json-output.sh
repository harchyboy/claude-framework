#!/bin/bash
# json-output.sh — Shared JSON output utilities for HCF scripts
# Source this file: . scripts/lib/json-output.sh
#
# Provides:
#   json_output_init         — Set up temp file for accumulating JSON fields
#   json_output_add          — Add a key-value pair (string or raw JSON)
#   json_output_emit         — Write final JSON object to stdout
#   json_output_cleanup      — Remove temp files (called automatically on EXIT)
#   json_output_log          — Print to stderr only (suppressed from stdout in JSON mode)
#   json_output_suppress     — Returns 0 (true) when JSON_OUTPUT is active

# ─── State ──────────────────────────────────────────────────────────────────

_JSON_TMPFILE=""
_JSON_FIELD_COUNT=0

# ─── Functions ──────────────────────────────────────────────────────────────

json_output_init() {
  _JSON_TMPFILE=$(mktemp)
  _JSON_FIELD_COUNT=0
  echo "{" > "$_JSON_TMPFILE"
}

json_output_add() {
  # Usage: json_output_add <key> <value> [--raw]
  # --raw: value is already valid JSON (number, boolean, array, object)
  # Without --raw: value is treated as a string and quoted
  local key="$1"
  local value="$2"
  local raw="${3:-}"

  if [[ -z "$_JSON_TMPFILE" ]]; then
    json_output_init
  fi

  local comma=""
  if [[ "$_JSON_FIELD_COUNT" -gt 0 ]]; then
    comma=","
  fi

  if [[ "$raw" == "--raw" ]]; then
    echo "${comma}\"${key}\": ${value}" >> "$_JSON_TMPFILE"
  else
    # Escape special characters in string values
    local escaped
    escaped=$(node -e "process.stdout.write(JSON.stringify(process.argv[1]))" -- "$value" 2>/dev/null || printf '"%s"' "$value")
    echo "${comma}\"${key}\": ${escaped}" >> "$_JSON_TMPFILE"
  fi
  _JSON_FIELD_COUNT=$((_JSON_FIELD_COUNT + 1))
}

json_output_emit() {
  # Writes the accumulated JSON object to stdout
  if [[ -z "$_JSON_TMPFILE" ]]; then
    echo "{}"
    return
  fi

  echo "}" >> "$_JSON_TMPFILE"

  # Use node to validate and pretty-print the JSON
  if node -e "
    const fs = require('fs');
    const raw = fs.readFileSync(process.argv[1], 'utf8');
    const obj = JSON.parse(raw);
    process.stdout.write(JSON.stringify(obj, null, 2) + '\n');
  " "$_JSON_TMPFILE" 2>/dev/null; then
    : # success
  else
    # Fallback: emit raw (may have trailing commas etc)
    cat "$_JSON_TMPFILE"
  fi
}

json_output_cleanup() {
  [[ -n "$_JSON_TMPFILE" ]] && rm -f "$_JSON_TMPFILE" 2>/dev/null || true
}

json_output_suppress() {
  # Returns 0 (true) when JSON_OUTPUT is active
  [[ "${JSON_OUTPUT:-false}" == "true" ]]
}

json_output_log() {
  # Print human-readable output to stderr when in JSON mode, stdout otherwise
  if json_output_suppress; then
    echo -e "$@" >&2
  else
    echo -e "$@"
  fi
}
