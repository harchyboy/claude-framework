#!/bin/bash
# local-model.sh — Route prompts to local Ollama model or fall back to Claude
#
# Usage:
#   bash scripts/local-model.sh <prompt> [options]
#   echo "prompt" | bash scripts/local-model.sh - [options]
#
# Options:
#   --model <name>    Ollama model name (default: qwen2.5-coder:7b)
#   --fallback        Fall back to Claude if Ollama unavailable (default: true)
#   --no-fallback     Fail if Ollama unavailable
#   --timeout <sec>   Response timeout in seconds (default: 120)
#
# Environment:
#   OLLAMA_HOST       Ollama API URL (default: http://localhost:11434)
#   LOCAL_MODEL       Override default model name
#
# Best for: test generation, documentation, lint fixes, boilerplate code
# Not for: architecture decisions, complex debugging, security review

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
MODEL="${LOCAL_MODEL:-qwen2.5-coder:7b}"
FALLBACK=true
TIMEOUT=120
PROMPT=""

# ─── Parse args ──────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)       MODEL="$2"; shift ;;
    --fallback)    FALLBACK=true ;;
    --no-fallback) FALLBACK=false ;;
    --timeout)     TIMEOUT="$2"; shift ;;
    -)             PROMPT=$(cat) ;;  # Read from stdin
    *)
      if [[ -z "$PROMPT" ]]; then
        PROMPT="$1"
      else
        echo "Unknown option: $1" >&2; exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "$PROMPT" ]]; then
  echo "Usage: bash scripts/local-model.sh <prompt> [--model <name>]" >&2
  exit 1
fi

# ─── Check Ollama ────────────────────────────────────────────────────────────

check_ollama() {
  curl -sf "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1
}

check_model() {
  curl -sf "${OLLAMA_HOST}/api/tags" 2>/dev/null | \
    node -e "
      let data = '';
      process.stdin.on('data', c => data += c);
      process.stdin.on('end', () => {
        const tags = JSON.parse(data);
        const found = (tags.models || []).some(m => m.name === '$MODEL' || m.name.startsWith('$MODEL'));
        process.exit(found ? 0 : 1);
      });
    " 2>/dev/null
}

# ─── Execute ─────────────────────────────────────────────────────────────────

if check_ollama; then
  if ! check_model; then
    echo "⬇️  Pulling model: $MODEL..." >&2
    curl -sf "${OLLAMA_HOST}/api/pull" -d "{\"name\": \"$MODEL\"}" > /dev/null 2>&1 || {
      if [[ "$FALLBACK" == "true" ]]; then
        echo "⚠️  Model pull failed — falling back to Claude" >&2
        claude -p "$PROMPT" --output-format text 2>/dev/null
        exit $?
      else
        echo "❌ Model $MODEL not available and pull failed" >&2
        exit 1
      fi
    }
  fi

  # Call Ollama generate API
  RESPONSE=$(curl -sf --max-time "$TIMEOUT" "${OLLAMA_HOST}/api/generate" \
    -d "{
      \"model\": \"$MODEL\",
      \"prompt\": $(node -e "console.log(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8')))" <<< "$PROMPT"),
      \"stream\": false
    }" 2>/dev/null) || {
    if [[ "$FALLBACK" == "true" ]]; then
      echo "⚠️  Ollama request failed — falling back to Claude" >&2
      claude -p "$PROMPT" --output-format text 2>/dev/null
      exit $?
    else
      echo "❌ Ollama request failed" >&2
      exit 1
    fi
  }

  # Extract response text
  echo "$RESPONSE" | node -e "
    let data = '';
    process.stdin.on('data', c => data += c);
    process.stdin.on('end', () => {
      try {
        const parsed = JSON.parse(data);
        process.stdout.write(parsed.response || '');
      } catch(e) {
        process.stdout.write(data);
      }
    });
  "
else
  if [[ "$FALLBACK" == "true" ]]; then
    echo "ℹ️  Ollama not running — using Claude" >&2
    claude -p "$PROMPT" --output-format text 2>/dev/null
  else
    echo "❌ Ollama not available at $OLLAMA_HOST" >&2
    exit 1
  fi
fi
