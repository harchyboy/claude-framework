#!/bin/bash
# local-model.sh — Route prompts to local Ollama model or fall back to Claude
#
# Usage:
#   bash scripts/local-model.sh <prompt> [options]
#   echo "prompt" | bash scripts/local-model.sh - [options]
#
# Options:
#   --model <name>      Ollama model name (overrides task-type auto-selection)
#   --task-type <type>  Auto-select best model for task type (see TYPE TABLE)
#   --fallback          Fall back to Claude if Ollama unavailable (default: true)
#   --no-fallback       Fail if Ollama unavailable
#   --timeout <sec>     Response timeout in seconds (default: 120)
#   --system <text>     System prompt to prepend
#
# Task-type model selection (TYPE TABLE):
#   classify, lint-fix, summarize  →  qwen2.5-coder:3b  (fast, low memory)
#   test-scaffold, boilerplate     →  qwen2.5-coder:7b  (stronger code gen)
#   docs                           →  qwen2.5-coder:7b  (code-aware docs)
#   (default / unrecognised)       →  qwen2.5-coder:7b
#
# Environment:
#   OLLAMA_HOST       Ollama API URL (default: http://localhost:11434)
#   LOCAL_MODEL       Override default model name (lower priority than --model)
#
# Best for: test generation, documentation, lint fixes, boilerplate code
# Not for: architecture decisions, complex debugging, security review

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
MODEL=""
TASK_TYPE=""
FALLBACK=true
TIMEOUT=120
PROMPT=""
SYSTEM_PROMPT=""

# ─── Parse args ──────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)       MODEL="$2"; shift ;;
    --task-type)   TASK_TYPE="$2"; shift ;;
    --fallback)    FALLBACK=true ;;
    --no-fallback) FALLBACK=false ;;
    --timeout)     TIMEOUT="$2"; shift ;;
    --system)      SYSTEM_PROMPT="$2"; shift ;;
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

# ─── Auto-select model from task type ─────────────────────────────────────────

if [[ -z "$MODEL" ]]; then
  case "$TASK_TYPE" in
    classify|lint-fix|summarize)
      MODEL="${LOCAL_MODEL:-qwen2.5-coder:3b}"
      ;;
    test-scaffold|boilerplate|docs|"")
      MODEL="${LOCAL_MODEL:-qwen2.5-coder:7b}"
      ;;
    *)
      MODEL="${LOCAL_MODEL:-qwen2.5-coder:7b}"
      ;;
  esac
fi

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

  # Build request body — include system prompt if provided
  REQUEST_BODY=$(node -e "
    const body = {
      model: '$MODEL',
      prompt: $(node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8')))" <<< "$PROMPT"),
      stream: false
    };
    if ('$SYSTEM_PROMPT'.trim()) body.system = '$SYSTEM_PROMPT';
    console.log(JSON.stringify(body));
  " 2>/dev/null) || REQUEST_BODY="{\"model\":\"$MODEL\",\"prompt\":$(node -e "process.stdout.write(JSON.stringify(require('fs').readFileSync('/dev/stdin','utf8')))" <<< "$PROMPT"),\"stream\":false}"

  # Call Ollama generate API
  RESPONSE=$(curl -sf --max-time "$TIMEOUT" "${OLLAMA_HOST}/api/generate" \
    -d "$REQUEST_BODY" 2>/dev/null) || {
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
