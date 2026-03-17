# Workflow-as-Code

> Last updated: 2026-03-17

## Overview

Workflows are YAML files that define multi-phase agent orchestration. The workflow-as-code system
replaces hardcoded bash logic with declarative, composable workflow definitions. Each workflow
specifies the agents to invoke, their execution order, quality gates that must pass between phases,
and failure handling strategies. This makes complex multi-agent pipelines auditable, version-controlled,
and reusable across projects.

---

## Quick Start

Run a workflow by passing the YAML file to `workflow-runner.sh`:

```bash
# Run a code review workflow
bash scripts/workflow-runner.sh workflows/code-review.yaml

# Pass variables at runtime
bash scripts/workflow-runner.sh workflows/feature-development.yaml \
  --var branch=my-feature \
  --var prd_file=prd/prd.json

# Preview what would run without executing
bash scripts/workflow-runner.sh workflows/debug-investigation.yaml \
  --var bug_description="API returns 500 on POST /users" \
  --dry-run
```

---

## Schema Reference

### Top-Level Fields

| Field         | Type   | Description                                                  |
|---------------|--------|--------------------------------------------------------------|
| `name`        | string | Human-readable workflow name                                 |
| `description` | string | One-line summary of what the workflow does                   |
| `version`     | string | Semantic version (e.g., `1.0.0`)                             |
| `variables`   | map    | Default key-value pairs, overridden by `--var` at runtime    |
| `phases`      | list   | Ordered list of phases to execute                            |

### Phase Fields

| Field          | Type                        | Description                                                         |
|----------------|-----------------------------|---------------------------------------------------------------------|
| `name`         | string                      | Phase identifier, used in logs and results                          |
| `execution`    | `parallel` \| `sequential`  | Whether agents in this phase run concurrently or one at a time      |
| `agents`       | list                        | Agents to invoke during this phase                                  |
| `quality_gate` | object                      | Optional gate that must pass before proceeding to the next phase    |
| `timeout`      | duration (e.g., `10m`)      | Maximum wall-clock time for the phase; aborts if exceeded           |
| `on_failure`   | `retry` \| `skip` \| `abort`| Behaviour when the phase fails                                      |
| `max_retries`  | integer                     | Maximum retry attempts when `on_failure: retry`                     |
| `condition`    | string                      | Shell expression; phase is skipped when it evaluates to false       |

### Agent Fields

| Field      | Type                 | Description                                                        |
|------------|----------------------|--------------------------------------------------------------------|
| `name`     | string               | Agent identifier used in logs                                      |
| `command`  | string               | Command to execute; supports `{{variable}}` interpolation          |
| `type`     | `claude` \| `bash`   | `claude` spawns a Claude subagent; `bash` runs a shell command     |
| `model`    | string               | Model override (e.g., `opus`, `sonnet`, `haiku`)                   |
| `timeout`  | duration             | Per-agent timeout; overrides phase timeout for this agent          |
| `required` | boolean              | If `true`, phase fails immediately when this agent fails           |

### Quality Gate Fields

| Field                 | Type    | Description                                                              |
|-----------------------|---------|--------------------------------------------------------------------------|
| `consensus_threshold` | float   | Fraction of agents that must agree (e.g., `0.67` = two-thirds majority) |
| `required_checks`     | list    | Named checks that must pass; evaluated from agent outputs                |
| `script`              | string  | Path to a custom gate script; receives phase results on stdin as JSON    |

---

## Variable Interpolation

Variables use `{{variable}}` syntax throughout the YAML. They are resolved in this order:

1. `--var key=value` flags passed at runtime (highest priority)
2. `variables` block defaults in the workflow YAML

Example workflow snippet:

```yaml
variables:
  branch: main
  prd_file: prd/prd.json

phases:
  - name: implement
    agents:
      - name: feature-agent
        type: claude
        command: "Implement the feature described in {{prd_file}} on branch {{branch}}"
```

Runtime override:

```bash
bash scripts/workflow-runner.sh workflows/feature-development.yaml \
  --var branch=feature/auth-refresh \
  --var prd_file=prd/auth-refresh.json
```

Undefined variables that lack a default cause the runner to exit with an error before any agents start.

---

## Quality Gates

Quality gates sit between phases and block progression until criteria are met. When a phase defines
`consensus_threshold`, the runner calls `scripts/consensus-gate.sh` after all agents complete,
passing agent outputs and the threshold as arguments. The gate script exits 0 on pass, non-zero on fail.

```yaml
quality_gate:
  consensus_threshold: 0.67
  required_checks:
    - tests_pass
    - no_critical_findings
```

When the gate fails, the phase's `on_failure` policy applies:

- `retry` — re-runs the phase up to `max_retries` times, then aborts.
- `skip` — logs the gate failure and continues to the next phase.
- `abort` — halts the entire workflow immediately.

Custom gate logic can be supplied via `script`:

```yaml
quality_gate:
  script: scripts/my-custom-gate.sh
```

---

## Creating Custom Workflows

1. Copy an existing workflow as a starting point:
   ```bash
   cp workflows/code-review.yaml workflows/my-workflow.yaml
   ```

2. Edit `name`, `description`, and `version` at the top.

3. Define `variables` for any values that differ between runs.

4. Add or remove phases; set `execution: parallel` for independent agents and `sequential` for
   agents that depend on prior output.

5. Test the structure before running for real:
   ```bash
   bash scripts/workflow-runner.sh workflows/my-workflow.yaml --dry-run
   ```
   Dry-run prints the resolved phase plan and variable bindings without invoking any agents.

6. Commit the YAML file alongside your project code so workflow changes are code-reviewed.

---

## Built-in Workflows

| File                          | Description                                                              |
|-------------------------------|--------------------------------------------------------------------------|
| `feature-development.yaml`    | Full development loop: sync → implement → gate → review → merge          |
| `code-review.yaml`            | Multi-agent code review with consensus gating before approval            |
| `debug-investigation.yaml`    | Debate-pattern bug investigation with competing hypotheses               |

---

## Results

Each workflow run writes its output to a timestamped directory:

```
workflow-results/
└── <run-id>/               # e.g., 20260317-143022-code-review
    ├── summary.json         # Run metadata: workflow name, start/end time, exit status
    ├── phases/
    │   ├── <phase-name>/
    │   │   ├── agents/
    │   │   │   └── <agent-name>.log   # Raw output from each agent
    │   │   └── gate-result.json       # Quality gate verdict and details
    └── variables.json       # Resolved variable bindings for this run
```

`summary.json` records the overall pass/fail verdict and a phase-by-phase breakdown. Use it for
post-run auditing or to feed results into subsequent workflows.
