#!/bin/bash
# route-model.sh — Classify a task and recommend the best execution model
#
# Usage:
#   bash scripts/route-model.sh --task-type <type>
#   bash scripts/route-model.sh --description "Write unit tests for UserService"
#   bash scripts/route-model.sh --task-type test-scaffold --check-local
#
# Options:
#   --task-type <type>     Explicit task type (see TYPE TABLE below)
#   --description <text>  Auto-classify from description (ignores --task-type)
#   --check-local         Also verify Ollama is reachable (adds latency)
#   --quiet               Output route only — no diagnostics on stderr
#
# Output (stdout):
#   local:<model>   Use Ollama with named model
#   haiku           Use claude-haiku-4-5-20251001
#   sonnet          Use claude-opus-4-6
#   opus            Use claude-opus-4-6
#
# Exit codes:
#   0   Route determined
#   1   Invalid input
#
# TYPE TABLE:
#   Local-eligible (Ollama → haiku fallback):
#     classify       classify/triage text input
#     test-scaffold  generate test file skeletons
#     docs           write JSDoc, README, docstrings
#     lint-fix       generate lint/format fixes
#     boilerplate    repetitive scaffolding, CRUD templates
#     summarize      condense long text/file content
#   Cloud (haiku):
#     explore        codebase search, grep, file discovery
#     simple-edit    single-file text change, copy update
#   Cloud (sonnet):
#     feature        implement product features
#     bug-fix        debug and fix issues
#     review         code quality review
#     refactor       restructure existing code
#   Cloud (opus):
#     security       security audit or sensitive auth logic
#     architecture   system design, ADRs, cross-cutting decisions
#     orchestrate    multi-agent coordination and planning
#     escalate       anything that has failed 3+ times

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
TASK_TYPE=""
DESCRIPTION=""
CHECK_LOCAL=false
QUIET=false

# ─── Parse args ───────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-type)    TASK_TYPE="$2";    shift ;;
    --description)  DESCRIPTION="$2"; shift ;;
    --check-local)  CHECK_LOCAL=true ;;
    --quiet)        QUIET=true ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ─── Auto-classify from description ───────────────────────────────────────────

if [[ -n "$DESCRIPTION" ]]; then
  DESC_LOWER=$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]')

  # Opus triggers (checked first — highest priority)
  if echo "$DESC_LOWER" | grep -qE "secur|auth|rbac|rls|row.level|pentest|owasp|injection|xss|csrf|encrypt"; then
    TASK_TYPE="security"
  elif echo "$DESC_LOWER" | grep -qE "architect|adr|system design|migrate (from|to)|extract service|monolith|domain bound"; then
    TASK_TYPE="architecture"
  elif echo "$DESC_LOWER" | grep -qE "orchestrat|coordinate|multi.agent|team lead|dispatch"; then
    TASK_TYPE="orchestrate"

  # Local-eligible triggers
  elif echo "$DESC_LOWER" | grep -qE "write test|generate test|add test|unit test|spec file|test scaffold|test skeleton"; then
    TASK_TYPE="test-scaffold"
  elif echo "$DESC_LOWER" | grep -qE "jsdoc|docstring|readme|documentation|add comment|annotate|document (the|all|public)"; then
    TASK_TYPE="docs"
  elif echo "$DESC_LOWER" | grep -qE "lint|format|eslint|prettier|fix warning|unused import|trailing"; then
    TASK_TYPE="lint-fix"
  elif echo "$DESC_LOWER" | grep -qE "boilerplate|scaffold|template|crud|skeleton|stub|placeholder"; then
    TASK_TYPE="boilerplate"
  elif echo "$DESC_LOWER" | grep -qE "classify|categoris|triage|route|is this a (bug|feature|refactor)"; then
    TASK_TYPE="classify"
  elif echo "$DESC_LOWER" | grep -qE "summar|condense|shorten|tldr"; then
    TASK_TYPE="summarize"

  # Sonnet triggers
  elif echo "$DESC_LOWER" | grep -qE "fix|bug|crash|error|fail|broken|not work|incorrect|wrong"; then
    TASK_TYPE="bug-fix"
  elif echo "$DESC_LOWER" | grep -qE "refactor|extract|move|restructure|simplif|clean up|reorganis"; then
    TASK_TYPE="refactor"
  elif echo "$DESC_LOWER" | grep -qE "review|audit|check|inspect|assess|analys"; then
    TASK_TYPE="review"

  # Haiku triggers
  elif echo "$DESC_LOWER" | grep -qE "find|search|grep|where is|which file|list|explore|lookup"; then
    TASK_TYPE="explore"
  elif echo "$DESC_LOWER" | grep -qE "update (the |copy|text|label|string|message|placeholder|typo|wording)"; then
    TASK_TYPE="simple-edit"

  # Default: feature
  else
    TASK_TYPE="feature"
  fi

  [[ "$QUIET" != "true" ]] && echo "  classified as: $TASK_TYPE" >&2
fi

if [[ -z "$TASK_TYPE" ]]; then
  echo "Usage: bash scripts/route-model.sh --task-type <type> | --description <text>" >&2
  exit 1
fi

# ─── Routing table ────────────────────────────────────────────────────────────

LOCAL_ELIGIBLE=false
FALLBACK_MODEL="haiku"
LOCAL_MODEL_NAME="qwen2.5-coder:7b"

case "$TASK_TYPE" in
  classify|summarize)
    LOCAL_ELIGIBLE=true
    LOCAL_MODEL_NAME="qwen2.5-coder:3b"
    FALLBACK_MODEL="haiku"
    ;;
  test-scaffold|boilerplate)
    LOCAL_ELIGIBLE=true
    LOCAL_MODEL_NAME="qwen2.5-coder:7b"
    FALLBACK_MODEL="haiku"
    ;;
  docs)
    LOCAL_ELIGIBLE=true
    LOCAL_MODEL_NAME="${LOCAL_MODEL:-qwen2.5-coder:7b}"
    FALLBACK_MODEL="haiku"
    ;;
  lint-fix)
    LOCAL_ELIGIBLE=true
    LOCAL_MODEL_NAME="qwen2.5-coder:3b"
    FALLBACK_MODEL="haiku"
    ;;
  explore|simple-edit)
    echo "haiku"
    exit 0
    ;;
  feature|bug-fix|refactor|review)
    echo "sonnet"
    exit 0
    ;;
  security|architecture|orchestrate|escalate)
    echo "opus"
    exit 0
    ;;
  *)
    [[ "$QUIET" != "true" ]] && echo "  unknown task type '$TASK_TYPE' — defaulting to opus" >&2
    echo "sonnet"
    exit 0
    ;;
esac

# ─── Local eligibility check ─────────────────────────────────────────────────

if [[ "$LOCAL_ELIGIBLE" == "true" ]]; then
  if [[ "$CHECK_LOCAL" == "true" ]]; then
    if curl -sf --max-time 2 "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; then
      [[ "$QUIET" != "true" ]] && echo "  Ollama available — routing to local:${LOCAL_MODEL_NAME}" >&2
      echo "local:${LOCAL_MODEL_NAME}"
    else
      [[ "$QUIET" != "true" ]] && echo "  Ollama not available — routing to ${FALLBACK_MODEL}" >&2
      echo "$FALLBACK_MODEL"
    fi
  else
    # Without --check-local, return local route and let caller handle fallback
    echo "local:${LOCAL_MODEL_NAME}"
  fi
fi
