#!/bin/bash
# workflow-runner.sh — Core workflow executor for YAML workflow files
# Hartz Claude Framework
#
# Usage: bash scripts/workflow-runner.sh <workflow.yml> [options]
#
# Options:
#   --var key=value     Variable for interpolation (repeatable)
#   --dry-run           Parse and show what would execute, don't run
#   --phase <name>      Run only this phase
#   --skip-phase <name> Skip this phase (repeatable)
#   --results-dir <p>   Results directory (default: workflow-results/<run-id>/)
#   --help              Show this help

set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Configuration ────────────────────────────────────────────────────────────

WORKFLOW_FILE=""
DRY_RUN=false
ONLY_PHASE=""
SKIP_PHASES=()
RESULTS_DIR=""
declare -A VARS

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"

# Summary counters
PHASES_RUN=0
PHASES_PASSED=0
PHASES_FAILED=0
AGENTS_RUN=0
AGENTS_PASSED=0
AGENTS_FAILED=0

# ─── Argument parsing ─────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  echo -e "${RED}Error: no workflow file specified.${RESET}"
  echo "Usage: bash scripts/workflow-runner.sh <workflow.yml> [options]"
  exit 1
fi

# First positional argument is the workflow file
if [[ "${1:-}" != --* ]]; then
  WORKFLOW_FILE="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var)
      key="${2%%=*}"
      val="${2#*=}"
      VARS["$key"]="$val"
      shift
      ;;
    --dry-run)    DRY_RUN=true ;;
    --phase)      ONLY_PHASE="$2"; shift ;;
    --skip-phase) SKIP_PHASES+=("$2"); shift ;;
    --results-dir) RESULTS_DIR="$2"; shift ;;
    --help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$WORKFLOW_FILE" ]]; then
  echo -e "${RED}Error: no workflow file specified.${RESET}"
  exit 1
fi

if [[ ! -f "$WORKFLOW_FILE" ]]; then
  echo -e "${RED}Error: workflow file not found: $WORKFLOW_FILE${RESET}"
  exit 1
fi

if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="workflow-results/$RUN_ID"
fi

# ─── YAML parsing ────────────────────────────────────────────────────────────

# Detect YAML parser: prefer yq, fall back to node
YAML_TO_JSON=""
if command -v yq &>/dev/null; then
  YAML_TO_JSON="yq"
elif command -v node &>/dev/null && [[ -f "scripts/yaml-to-json.js" ]]; then
  YAML_TO_JSON="node scripts/yaml-to-json.js"
else
  echo -e "${RED}Error: neither yq nor node scripts/yaml-to-json.js is available for YAML parsing.${RESET}"
  exit 1
fi

workflow_to_json() {
  local file="$1"
  if [[ "$YAML_TO_JSON" == "yq" ]]; then
    yq -o=json . "$file"
  else
    node scripts/yaml-to-json.js "$file"
  fi
}

# ─── Variable interpolation ──────────────────────────────────────────────────

interpolate() {
  local text="$1"
  # Replace {{key}} with value from VARS
  for key in "${!VARS[@]}"; do
    text="${text//\{\{$key\}\}/${VARS[$key]}}"
  done
  echo "$text"
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

log_info()    { echo -e "${BLUE}[workflow]${RESET} $*"; }
log_success() { echo -e "${GREEN}[✔]${RESET} $*"; }
log_warn()    { echo -e "${YELLOW}[⚠]${RESET} $*"; }
log_error()   { echo -e "${RED}[✘]${RESET} $*"; }
log_phase()   { echo -e "\n${BOLD}${CYAN}━━━ Phase: $* ━━━${RESET}"; }
log_agent()   { echo -e "${BLUE}  → agent:${RESET} $*"; }

is_skipped_phase() {
  local name="$1"
  for skip in "${SKIP_PHASES[@]:-}"; do
    [[ "$skip" == "$name" ]] && return 0
  done
  return 1
}

# ─── Agent execution ─────────────────────────────────────────────────────────

run_agent() {
  local phase_name="$1"
  local agent_name="$2"
  local agent_type="$3"     # claude | bash
  local agent_model="$4"    # may be empty
  local agent_timeout="$5"  # may be empty
  local agent_cmd="$6"

  local log_dir="$RESULTS_DIR/phases/$phase_name"
  mkdir -p "$log_dir"
  local log_file="$log_dir/${agent_name}.log"

  local resolved_cmd
  resolved_cmd="$(interpolate "$agent_cmd")"

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ "$agent_type" == "claude" ]]; then
      local model_arg=""
      [[ -n "$agent_model" ]] && model_arg=" --model $agent_model"
      log_agent "${agent_name} [claude${model_arg}]: claude${model_arg} --print \"$resolved_cmd\""
    else
      log_agent "${agent_name} [bash]: $resolved_cmd"
    fi
    return 0
  fi

  log_agent "running $agent_name (type=$agent_type)..."

  local final_cmd
  if [[ "$agent_type" == "claude" ]]; then
    if [[ -n "$agent_model" ]]; then
      final_cmd="claude --model $agent_model --print \"$resolved_cmd\""
    else
      final_cmd="claude --print \"$resolved_cmd\""
    fi
  else
    final_cmd="$resolved_cmd"
  fi

  local exit_code=0
  if [[ -n "$agent_timeout" ]]; then
    timeout "$agent_timeout" bash -c "$final_cmd" >"$log_file" 2>&1 || exit_code=$?
  else
    bash -c "$final_cmd" >"$log_file" 2>&1 || exit_code=$?
  fi

  AGENTS_RUN=$((AGENTS_RUN + 1))

  if [[ $exit_code -eq 0 ]]; then
    AGENTS_PASSED=$((AGENTS_PASSED + 1))
    log_success "  $agent_name passed (log: $log_file)"
  else
    AGENTS_FAILED=$((AGENTS_FAILED + 1))
    log_error "  $agent_name failed with exit $exit_code (log: $log_file)"
  fi

  return $exit_code
}

# ─── Phase execution ─────────────────────────────────────────────────────────

run_phase() {
  local workflow_json="$1"
  local phase_index="$2"

  local phase_name phase_exec on_failure max_retries phase_timeout condition

  phase_name="$(json_query "
    process.stdout.write(d.phases[$phase_index].name || 'phase-$phase_index');
  ")"

  phase_exec="$(json_query "
    process.stdout.write(d.phases[$phase_index].execution || 'sequential');
  ")"

  on_failure="$(json_query "
    process.stdout.write(d.phases[$phase_index].on_failure || 'abort');
  ")"

  max_retries="$(json_query "
    process.stdout.write(String(d.phases[$phase_index].max_retries || 1));
  ")"

  phase_timeout="$(json_query "
    process.stdout.write(String(d.phases[$phase_index].timeout || ''));
  ")"

  condition="$(json_query "
    process.stdout.write(d.phases[$phase_index].condition || '');
  ")"

  # Condition check
  if [[ -n "$condition" ]]; then
    local resolved_cond
    resolved_cond="$(interpolate "$condition")"
    if ! eval "$resolved_cond" &>/dev/null; then
      log_warn "Phase '$phase_name' skipped (condition false: $resolved_cond)"
      return 0
    fi
  fi

  # Skip check
  if is_skipped_phase "$phase_name"; then
    log_warn "Phase '$phase_name' skipped (--skip-phase)"
    return 0
  fi

  # Only-phase filter
  if [[ -n "$ONLY_PHASE" && "$ONLY_PHASE" != "$phase_name" ]]; then
    return 0
  fi

  log_phase "$phase_name  [execution=$phase_exec]"

  local attempt=0
  local phase_exit=0

  while true; do
    attempt=$((attempt + 1))
    phase_exit=0

    if [[ "$DRY_RUN" != "true" ]]; then
      mkdir -p "$RESULTS_DIR/phases/$phase_name"
    fi

    # Get agent count
    local agent_count
    agent_count="$(json_query "
      process.stdout.write(String((d.phases[$phase_index].agents || []).length));
    ")"

    if [[ "$phase_exec" == "parallel" ]]; then
      # ── Parallel execution ──
      # Use temp dir to collect exit codes from background subshells
      local par_tmp_dir
      par_tmp_dir="$(mktemp -d)"
      declare -A pids
      declare -A agent_names_map
      declare -A agent_required_map

      for ((ai=0; ai<agent_count; ai++)); do
        local a_name a_type a_model a_timeout a_cmd a_required
        a_name="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].name || 'agent-$ai');
        ")"
        a_type="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].type || 'claude');
        ")"
        a_model="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].model || '');
        ")"
        a_timeout="$(json_query "
          process.stdout.write(String(d.phases[$phase_index].agents[$ai].timeout || ''));
        ")"
        a_cmd="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].command || '');
        ")"
        a_required="$(json_query "
          const v = d.phases[$phase_index].agents[$ai].required;
          process.stdout.write(v === false ? 'false' : 'true');
        ")"

        agent_names_map[$ai]="$a_name"
        agent_required_map[$ai]="$a_required"

        if [[ "$DRY_RUN" == "true" ]]; then
          run_agent "$phase_name" "$a_name" "$a_type" "$a_model" "$a_timeout" "$a_cmd"
        else
          # Run in background; write exit code to temp file for parent-shell counting
          local exit_file="$par_tmp_dir/exit-$ai"
          (
            rc=0
            run_agent "$phase_name" "$a_name" "$a_type" "$a_model" "$a_timeout" "$a_cmd" || rc=$?
            echo "$rc" > "$exit_file"
          ) &
          pids[$ai]=$!
        fi
      done

      # Wait for all background jobs and tally results
      if [[ "$DRY_RUN" != "true" ]]; then
        for ai in "${!pids[@]}"; do
          wait "${pids[$ai]}" || true
          local exit_file="$par_tmp_dir/exit-$ai"
          local a_req="${agent_required_map[$ai]}"
          local agent_rc=0
          [[ -f "$exit_file" ]] && agent_rc="$(cat "$exit_file")"
          AGENTS_RUN=$((AGENTS_RUN + 1))
          if [[ "$agent_rc" -eq 0 ]]; then
            AGENTS_PASSED=$((AGENTS_PASSED + 1))
          else
            AGENTS_FAILED=$((AGENTS_FAILED + 1))
            if [[ "$a_req" == "true" ]]; then
              phase_exit=1
            fi
          fi
        done
        rm -rf "$par_tmp_dir"
      fi

    else
      # ── Sequential execution ──
      for ((ai=0; ai<agent_count; ai++)); do
        local a_name a_type a_model a_timeout a_cmd a_required
        a_name="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].name || 'agent-$ai');
        ")"
        a_type="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].type || 'claude');
        ")"
        a_model="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].model || '');
        ")"
        a_timeout="$(json_query "
          process.stdout.write(String(d.phases[$phase_index].agents[$ai].timeout || ''));
        ")"
        a_cmd="$(json_query "
          process.stdout.write(d.phases[$phase_index].agents[$ai].command || '');
        ")"
        a_required="$(json_query "
          const v = d.phases[$phase_index].agents[$ai].required;
          process.stdout.write(v === false ? 'false' : 'true');
        ")"

        local agent_exit=0
        run_agent "$phase_name" "$a_name" "$a_type" "$a_model" "$a_timeout" "$a_cmd" || agent_exit=$?

        if [[ $agent_exit -ne 0 && "$a_required" == "true" ]]; then
          phase_exit=1
          if [[ "$on_failure" == "abort" || "$on_failure" == "retry" ]]; then
            break
          fi
        fi
      done
    fi

    # Phase-level timeout wrapper (only meaningful for sequential; parallel handled per agent)
    # For sequential with phase timeout, the loop above already ran. Log a note if timeout set.
    # (True phase-level timeout wrapping would require subshell; this is a best-effort annotation.)

    # ── Quality gate ──
    if [[ $phase_exit -eq 0 && "$DRY_RUN" != "true" ]]; then
      local has_qg
      has_qg="$(json_query "
        const qg = d.phases[$phase_index].quality_gate;
        process.stdout.write(qg ? 'true' : 'false');
      ")"

      if [[ "$has_qg" == "true" ]]; then
        run_quality_gate "$workflow_json" "$phase_index" "$phase_name" || phase_exit=$?
      fi
    fi

    # ── On-failure strategy ──
    if [[ $phase_exit -ne 0 ]]; then
      case "$on_failure" in
        retry)
          if [[ $attempt -le $max_retries ]]; then
            log_warn "Phase '$phase_name' failed (attempt $attempt/$max_retries), retrying..."
            continue
          else
            log_error "Phase '$phase_name' failed after $max_retries retries."
            PHASES_FAILED=$((PHASES_FAILED + 1))
            return 1
          fi
          ;;
        skip)
          log_warn "Phase '$phase_name' failed — on_failure=skip, continuing."
          PHASES_FAILED=$((PHASES_FAILED + 1))
          return 0
          ;;
        abort|*)
          log_error "Phase '$phase_name' failed — aborting workflow."
          PHASES_FAILED=$((PHASES_FAILED + 1))
          return 1
          ;;
      esac
    else
      break
    fi
  done

  PHASES_RUN=$((PHASES_RUN + 1))
  PHASES_PASSED=$((PHASES_PASSED + 1))
  log_success "Phase '$phase_name' completed."
  return 0
}

# ─── Quality gate ────────────────────────────────────────────────────────────

run_quality_gate() {
  local workflow_json="$1"
  local phase_index="$2"
  local phase_name="$3"
  local gate_exit=0

  log_info "Running quality gate for phase '$phase_name'..."

  # consensus_threshold
  local threshold
  threshold="$(json_query "
    const qg = d.phases[$phase_index].quality_gate || {};
    process.stdout.write(String(qg.consensus_threshold || ''));
  ")"

  if [[ -n "$threshold" ]]; then
    local verdicts_file="$RESULTS_DIR/phases/$phase_name/verdicts.json"
    if [[ -f "$verdicts_file" ]]; then
      log_info "  Running consensus-gate.sh (threshold=$threshold)..."
      bash scripts/consensus-gate.sh --threshold "$threshold" --json "$verdicts_file" || gate_exit=$?
    else
      log_warn "  consensus_threshold set but no verdicts.json found at $verdicts_file — skipping."
    fi
  fi

  # quality_gate.script
  local gate_script
  gate_script="$(json_query "
    const qg = d.phases[$phase_index].quality_gate || {};
    process.stdout.write(qg.script || '');
  ")"

  if [[ -n "$gate_script" ]]; then
    local resolved_script
    resolved_script="$(interpolate "$gate_script")"
    log_info "  Running gate script: $resolved_script"
    bash -c "$resolved_script" || gate_exit=$?
  fi

  # quality_gate.required_checks (array of commands)
  local check_count
  check_count="$(json_query "
    const checks = (d.phases[$phase_index].quality_gate || {}).required_checks || [];
    process.stdout.write(String(checks.length));
  ")"

  for ((ci=0; ci<check_count; ci++)); do
    local check_cmd
    check_cmd="$(json_query "
      process.stdout.write(d.phases[$phase_index].quality_gate.required_checks[$ci] || '');
    ")"
    local resolved_check
    resolved_check="$(interpolate "$check_cmd")"
    log_info "  Required check: $resolved_check"
    bash -c "$resolved_check" || { log_error "  Check failed: $resolved_check"; gate_exit=1; }
  done

  if [[ $gate_exit -eq 0 ]]; then
    log_success "Quality gate passed for phase '$phase_name'."
  else
    log_error "Quality gate FAILED for phase '$phase_name'."
  fi

  return $gate_exit
}

# ─── Dry-run header ──────────────────────────────────────────────────────────

print_dry_run_header() {
  local workflow_json="$1"
  local wf_name
  wf_name="$(json_query "
    process.stdout.write(d.name || d.workflow || '(unnamed)');
  ")"
  echo -e "\n${BOLD}${YELLOW}━━━ DRY RUN: $wf_name ━━━${RESET}"
  echo -e "${YELLOW}  Workflow: $WORKFLOW_FILE${RESET}"
  echo -e "${YELLOW}  Run ID:   $RUN_ID${RESET}"
  if [[ ${#VARS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}  Variables:${RESET}"
    for k in "${!VARS[@]}"; do
      echo -e "    ${CYAN}$k${RESET} = ${VARS[$k]}"
    done
  fi
  echo ""
}

# ─── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
  echo -e "\n${BOLD}━━━ Workflow Summary ━━━${RESET}"
  echo -e "  Run ID:         ${CYAN}$RUN_ID${RESET}"
  echo -e "  Results:        ${CYAN}$RESULTS_DIR${RESET}"
  echo -e "  Phases run:     ${BOLD}$PHASES_RUN${RESET}  (passed: ${GREEN}$PHASES_PASSED${RESET}, failed: ${RED}$PHASES_FAILED${RESET})"
  echo -e "  Agents run:     ${BOLD}$AGENTS_RUN${RESET}  (passed: ${GREEN}$AGENTS_PASSED${RESET}, failed: ${RED}$AGENTS_FAILED${RESET})"
  if [[ $PHASES_FAILED -gt 0 || $AGENTS_FAILED -gt 0 ]]; then
    echo -e "\n${RED}${BOLD}Workflow FAILED.${RESET}"
  else
    echo -e "\n${GREEN}${BOLD}Workflow PASSED.${RESET}"
  fi
}

# ─── JSON query helper (Windows-safe, no /dev/stdin) ─────────────────────────

# Write workflow JSON to temp file for node queries (avoids /dev/stdin on Windows)
WORKFLOW_JSON_FILE=""
WORKFLOW_TMP_FILE=""

# Query JSON using node — reads from temp file, not stdin
json_query() {
  local js_expr="$1"
  node -e "
    const d = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
    $js_expr
  " "$WORKFLOW_JSON_FILE"
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  log_info "Loading workflow: $WORKFLOW_FILE"

  local workflow_json
  workflow_json="$(workflow_to_json "$WORKFLOW_FILE")"

  # Write JSON to temp file for Windows-safe node queries
  WORKFLOW_TMP_FILE="$(mktemp)"
  # Convert to Windows path if running under Git Bash / MSYS2 (Node.js needs native paths)
  if command -v cygpath &>/dev/null; then
    WORKFLOW_JSON_FILE="$(cygpath -w "$WORKFLOW_TMP_FILE")"
  else
    WORKFLOW_JSON_FILE="$WORKFLOW_TMP_FILE"
  fi
  trap 'rm -f "$WORKFLOW_TMP_FILE"' EXIT
  echo "$workflow_json" > "$WORKFLOW_TMP_FILE"

  # Load workflow-level default variables
  local default_keys_raw
  default_keys_raw="$(json_query "
    const vars = d.variables || (d.defaults || {}).vars || {};
    Object.keys(vars).forEach(k => {
      process.stdout.write(k + '=' + vars[k] + '\n');
    });
  ")" || true

  while IFS='=' read -r key val; do
    [[ -z "$key" ]] && continue
    if [[ -z "${VARS[$key]+x}" ]]; then
      VARS["$key"]="$val"
    fi
  done <<< "$default_keys_raw"

  if [[ "$DRY_RUN" == "true" ]]; then
    print_dry_run_header "$workflow_json"
  else
    local wf_name
    wf_name="$(json_query "
      process.stdout.write(d.name || d.workflow || '(unnamed)');
    ")"
    echo -e "\n${BOLD}${BLUE}━━━ Workflow: $wf_name ━━━${RESET}"
    log_info "Run ID:  $RUN_ID"
    log_info "Results: $RESULTS_DIR"
    mkdir -p "$RESULTS_DIR"
  fi

  local phase_count
  phase_count="$(json_query "
    process.stdout.write(String((d.phases || []).length));
  ")"

  if [[ "$phase_count" -eq 0 ]]; then
    log_warn "No phases defined in workflow."
    exit 0
  fi

  local overall_exit=0

  for ((pi=0; pi<phase_count; pi++)); do
    run_phase "$workflow_json" "$pi" || {
      overall_exit=1
      # run_phase already handles abort/skip/retry internally
      # If we get here with exit=1, it means abort was triggered
      break
    }
  done

  if [[ "$DRY_RUN" != "true" ]]; then
    print_summary
  fi

  return $overall_exit
}

main
