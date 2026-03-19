#!/bin/bash
# vercel-logs.sh — Fetch and parse Vercel build + runtime logs
# Source this file: . scripts/lib/vercel-logs.sh
#
# Requires: VERCEL_TOKEN environment variable
#
# Provides:
#   vercel_check_token        — Verify token is set and valid
#   vercel_find_project       — Find Vercel project ID for current repo
#   vercel_get_latest_deployment — Get most recent deployment
#   vercel_get_build_logs     — Fetch build logs for a deployment
#   vercel_get_runtime_logs   — Fetch serverless function runtime logs
#   vercel_diagnose_deployment — Full diagnosis: build + runtime errors

VERCEL_API="https://api.vercel.com"

# ─── Helpers ────────────────────────────────────────────────────────────────

vercel_check_token() {
  if [[ -z "${VERCEL_TOKEN:-}" ]]; then
    echo "  ⚠️  VERCEL_TOKEN not set — skipping Vercel log check"
    return 1
  fi
  return 0
}

vercel_api() {
  # Usage: vercel_api <endpoint> [extra_curl_args...]
  local endpoint="$1"
  shift
  curl -s -H "Authorization: Bearer $VERCEL_TOKEN" "$@" "${VERCEL_API}${endpoint}" 2>/dev/null
}

# ─── Project Discovery ──────────────────────────────────────────────────────

vercel_find_project() {
  # Auto-detect Vercel project ID from .vercel/project.json or by repo name
  # Returns project ID or empty string

  # Method 1: Read from .vercel/project.json (most reliable)
  if [[ -f ".vercel/project.json" ]]; then
    local proj_id
    proj_id=$(node -e "
      const p = JSON.parse(require('fs').readFileSync('.vercel/project.json','utf8'));
      if (p.projectId) console.log(p.projectId);
    " 2>/dev/null || echo "")
    if [[ -n "$proj_id" ]]; then
      echo "$proj_id"
      return 0
    fi
  fi

  # Method 2: Match by repo name
  local repo_name
  repo_name=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  local proj_id
  proj_id=$(vercel_api "/v9/projects?limit=50" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    const name = '$repo_name';
    const match = (d.projects || []).find(p =>
      p.name === name ||
      p.name === name.replace(/-/g, '') ||
      (p.link && p.link.repo && p.link.repo.toLowerCase().includes(name))
    );
    if (match) console.log(match.id);
  " 2>/dev/null || echo "")

  echo "$proj_id"
}

# ─── Deployment Info ────────────────────────────────────────────────────────

vercel_get_latest_deployment() {
  # Get the most recent deployment for a project
  # Usage: vercel_get_latest_deployment <project_id>
  # Returns JSON: {id, url, state, created, error}
  local project_id="$1"

  vercel_api "/v6/deployments?projectId=${project_id}&limit=1&state=" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    const dep = (d.deployments || [])[0];
    if (dep) {
      console.log(JSON.stringify({
        id: dep.uid,
        url: dep.url,
        state: dep.state || dep.readyState,
        created: dep.created ? new Date(dep.created).toISOString() : '',
        target: dep.target || 'preview',
        error: dep.errorMessage || ''
      }));
    } else {
      console.log('{}');
    }
  " 2>/dev/null || echo "{}"
}

# ─── Build Logs ─────────────────────────────────────────────────────────────

vercel_get_build_logs() {
  # Fetch build logs for a deployment
  # Usage: vercel_get_build_logs <deployment_id> [output_file]
  local deployment_id="$1"
  local output_file="${2:-}"

  local logs
  logs=$(vercel_api "/v7/deployments/${deployment_id}/events" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    const events = Array.isArray(d) ? d : [];
    events
      .filter(e => e.type === 'stdout' || e.type === 'stderr' || e.type === 'command')
      .forEach(e => {
        const prefix = e.type === 'stderr' ? '[ERR] ' : '';
        console.log(prefix + (e.payload || e.text || ''));
      });
  " 2>/dev/null || echo "")

  if [[ -n "$output_file" ]]; then
    echo "$logs" > "$output_file"
  fi
  echo "$logs"
}

# ─── Runtime Logs ───────────────────────────────────────────────────────────

vercel_get_runtime_logs() {
  # Fetch recent serverless function runtime logs
  # Usage: vercel_get_runtime_logs <project_id> [since_minutes] [output_file]
  local project_id="$1"
  local since_minutes="${2:-30}"
  local output_file="${3:-}"

  local since_ts
  since_ts=$(node -e "console.log(Date.now() - ${since_minutes} * 60 * 1000)" 2>/dev/null || echo "0")

  local logs
  logs=$(vercel_api "/v1/projects/${project_id}/logs?since=${since_ts}&limit=100&direction=backward" | node -e "
    const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
    const logs = Array.isArray(d.data) ? d.data : (Array.isArray(d) ? d : []);
    logs.forEach(l => {
      const ts = l.timestamp ? new Date(l.timestamp).toISOString() : '';
      const level = (l.level || l.type || 'info').toUpperCase();
      const msg = l.message || l.text || l.msg || '';
      const path = l.path || l.requestPath || '';
      const status = l.statusCode || l.status || '';
      if (msg) console.log(ts + ' [' + level + '] ' + (path ? path + ' ' : '') + (status ? status + ' ' : '') + msg);
    });
  " 2>/dev/null || echo "")

  if [[ -n "$output_file" ]]; then
    echo "$logs" > "$output_file"
  fi
  echo "$logs"
}

# ─── Full Diagnosis ─────────────────────────────────────────────────────────

vercel_diagnose_deployment() {
  # Full Vercel diagnosis: check latest deployment, extract errors from build + runtime logs
  # Usage: vercel_diagnose_deployment [output_dir]
  # Returns: JSON diagnosis object
  local output_dir="${1:-agent_logs}"

  vercel_check_token || return 1

  local project_id
  project_id=$(vercel_find_project)
  if [[ -z "$project_id" ]]; then
    echo "  ⚠️  Could not find Vercel project for this repo"
    return 1
  fi

  local deployment_json
  deployment_json=$(vercel_get_latest_deployment "$project_id")

  local dep_id dep_state dep_url dep_error dep_target
  dep_id=$(echo "$deployment_json" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).id || '')" 2>/dev/null || echo "")
  dep_state=$(echo "$deployment_json" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).state || '')" 2>/dev/null || echo "")
  dep_url=$(echo "$deployment_json" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).url || '')" 2>/dev/null || echo "")
  dep_error=$(echo "$deployment_json" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).error || '')" 2>/dev/null || echo "")
  dep_target=$(echo "$deployment_json" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync(0,'utf8')).target || '')" 2>/dev/null || echo "")

  if [[ -z "$dep_id" ]]; then
    echo "  ⚠️  No deployments found"
    return 1
  fi

  echo "  🔍 Vercel: checking deployment ${dep_id:0:12}... (${dep_state}, ${dep_target})"

  mkdir -p "$output_dir"

  # Fetch build logs
  local build_log_file="$output_dir/vercel-build-${dep_id:0:12}.log"
  local build_logs
  build_logs=$(vercel_get_build_logs "$dep_id" "$build_log_file")

  # Fetch runtime logs (last 30 minutes)
  local runtime_log_file="$output_dir/vercel-runtime-${dep_id:0:12}.log"
  local runtime_logs
  runtime_logs=$(vercel_get_runtime_logs "$project_id" 30 "$runtime_log_file")

  # Parse errors from both log sources
  node -e "
    const fs = require('fs');

    const buildLogs = fs.existsSync('$build_log_file') ? fs.readFileSync('$build_log_file', 'utf8') : '';
    const runtimeLogs = fs.existsSync('$runtime_log_file') ? fs.readFileSync('$runtime_log_file', 'utf8') : '';

    const diagnosis = {
      project_id: '$project_id',
      deployment_id: '$dep_id',
      deployment_state: '$dep_state',
      deployment_url: '$dep_url',
      deployment_target: '$dep_target',
      deployment_error: '$dep_error',
      timestamp: new Date().toISOString(),
      build_errors: [],
      runtime_errors: [],
      summary: '',
      suggested_action: ''
    };

    // Parse build log errors
    const buildLines = buildLogs.split('\n');
    for (const line of buildLines) {
      if (/\[ERR\]|error|Error:|ERROR|failed|FAIL/i.test(line) && !/warning/i.test(line)) {
        diagnosis.build_errors.push(line.trim().substring(0, 300));
      }
    }
    // Deduplicate and limit
    diagnosis.build_errors = [...new Set(diagnosis.build_errors)].slice(0, 30);

    // Parse runtime log errors
    const runtimeLines = runtimeLogs.split('\n');
    for (const line of runtimeLines) {
      if (/\[ERROR\]|Error:|FATAL|500|502|503|504|crash|timeout|FUNCTION_INVOCATION/i.test(line)) {
        diagnosis.runtime_errors.push(line.trim().substring(0, 300));
      }
    }
    diagnosis.runtime_errors = [...new Set(diagnosis.runtime_errors)].slice(0, 30);

    // Build summary
    const parts = [];
    if ('$dep_state' === 'ERROR' || '$dep_error') {
      parts.push('Deployment failed: ' + ('$dep_error' || '$dep_state'));
    }
    if (diagnosis.build_errors.length > 0) {
      parts.push(diagnosis.build_errors.length + ' build error(s): ' + diagnosis.build_errors[0].substring(0, 100));
    }
    if (diagnosis.runtime_errors.length > 0) {
      parts.push(diagnosis.runtime_errors.length + ' runtime error(s): ' + diagnosis.runtime_errors[0].substring(0, 100));
    }
    if (parts.length === 0) {
      if ('$dep_state' === 'READY') {
        parts.push('Deployment healthy (state: READY)');
      } else {
        parts.push('Deployment state: $dep_state — no errors detected in logs');
      }
    }
    diagnosis.summary = parts.join('; ');

    // Suggest action
    if (diagnosis.build_errors.length > 0) {
      diagnosis.suggested_action = 'Fix build errors before deploying. Check: ' + '$build_log_file';
    } else if (diagnosis.runtime_errors.length > 0) {
      diagnosis.suggested_action = 'Runtime errors in serverless functions. Check: ' + '$runtime_log_file';
    } else if ('$dep_state' === 'ERROR') {
      diagnosis.suggested_action = 'Deployment failed. Check Vercel dashboard for details.';
    } else {
      diagnosis.suggested_action = 'No action needed — deployment is healthy.';
    }

    // Write diagnosis
    const diagFile = '$output_dir/vercel-diagnosis.json';
    fs.writeFileSync(diagFile, JSON.stringify(diagnosis, null, 2));

    // Append to errors.jsonl if there are actual errors
    if (diagnosis.build_errors.length > 0 || diagnosis.runtime_errors.length > 0 || '$dep_state' === 'ERROR') {
      const errorLine = JSON.stringify({
        story_id: 'vercel-deployment',
        iteration: 0,
        failure_type: 'vercel_' + (diagnosis.build_errors.length > 0 ? 'build' : 'runtime'),
        summary: diagnosis.summary,
        suggested_action: diagnosis.suggested_action,
        error_count: diagnosis.build_errors.length + diagnosis.runtime_errors.length,
        test_failure_count: 0,
        compilation_error_count: diagnosis.build_errors.length,
        stack_trace_count: diagnosis.runtime_errors.length,
        timestamp: diagnosis.timestamp
      });
      fs.appendFileSync('agent_logs/errors.jsonl', errorLine + '\n');
    }

    // Console output
    console.log('  Vercel: ' + diagnosis.summary.substring(0, 200));
    if (diagnosis.build_errors.length > 0) {
      console.log('  Build errors (' + diagnosis.build_errors.length + '):');
      diagnosis.build_errors.slice(0, 5).forEach(e => console.log('    ' + e.substring(0, 120)));
    }
    if (diagnosis.runtime_errors.length > 0) {
      console.log('  Runtime errors (' + diagnosis.runtime_errors.length + '):');
      diagnosis.runtime_errors.slice(0, 5).forEach(e => console.log('    ' + e.substring(0, 120)));
    }
    if (diagnosis.suggested_action) {
      console.log('  Action: ' + diagnosis.suggested_action);
    }
  " 2>/dev/null || echo "  ⚠️  Vercel diagnosis parsing failed (non-blocking)"
}
