# progress.yaml State Machine Reference

Field definitions, ownership, and valid transitions for the build loop state machine.

## Field Ownership

Each field has exactly one owner responsible for writes. Other commands may READ any field but must never WRITE fields they don't own.

### Owner Key

| Owner | Source |
|-------|--------|
| `init` | `/sabs:build-loop-init` (scaffolding, one-time creation) |
| `orchestrator` | `/sabs:build-loop` (dispatcher: resume, skip, abort, pause) |
| `iterator` | `/sabs:build-loop-iterate` (continuous loop: start, iterate) |
| `retro` | phase-retro (retrospective gate) |

See `${CLAUDE_PLUGIN_ROOT}/docs/MANUAL.md` section "State ownership" for the full ownership table.

## Config Fields

| Field | Owner | Description |
|-------|-------|-------------|
| `config.verify` | init | Detected verify command (e.g., `npm run lint && npm run test`) |
| `config.max_tasks_per_phase` | init | Upper limit on iterations (default: 200) |
| `config.quality_check_suppressions` | init | List of suppressed quality check names |
| `config.build_loop_version.init_version` | init | Version used during init — set once, never changed |
| `config.build_loop_version.builds` | iterator | Versions used for each `start` — iterator appends if not present |

## State Fields

### Lifecycle (owner: iterator)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `phase` | string/null | `null` | Current phase name. Set by `start`, cleared by `abort`. |
| `phase_complete` | boolean | `false` | Set `true` by Branch B Phase Completion Gate. |
| `status` | string | `idle` | One of: `idle`, `running`, `paused`. Set by orchestrator (pause/resume/skip) and iterator (start sets running). |

### Task Orchestration (owner: iterator)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `task_number` | integer | `1` | Incremented after each task (pass or fail). |
| `next_task` | string/null | `null` | Queued task description. Prefixed with story ID: `[US-XX] <task>`. Branch B queues, Branch A clears. Orchestrator clears on skip. |
| `last_result` | string/null | `null` | `pass` or `fail` from most recent Branch A execution. |
| `consecutive_fails` | integer | `0` | Incremented on fail, reset on pass or skip/resume. Circuit breaker at 5. |

### Review (owner: iterator)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `review_stage` | string/null | `null` | One of: `null`, `pr_created`, `review_posted`. Tracks review workflow progress. |
| `review_complete` | boolean | `false` | Set `true` after handle-pr-review succeeds. |
| `pr_number` | integer/null | `null` | GitHub PR number, set during PR creation. |

### Retrospective (owner: retro)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `retro_complete` | boolean | `false` | Set `true` by phase-retro after writing retrospective. |

### Tracking (owner: iterator)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `completed_stories` | list | `[]` | Story IDs completed in this phase. Appended by Story Completion Gate. |

## Status Transitions

```
idle --[start]--> running
running --[circuit breaker / max tasks / auth fail / inconsistent state]--> paused
running --[phase + review complete]--> (loop exits, status remains running until next action)
paused --[resume]--> running
paused --[skip]--> running
running/paused --[abort]--> idle
```

## State Consistency Rules

The following combinations are invalid. If detected, the loop pauses with "Inconsistent state detected":

| Invalid Combination | Why |
|---------------------|-----|
| `phase_complete: true` + `review_complete: true` + `status: running` | Review is done; loop should have stopped |
| `phase: null` + `status: running` | Cannot be running without a phase |
| `task_number: 0` + `status: running` | Tasks start at 1 |
| `retro_complete: true` + `phase_complete: false` | Retro cannot complete before phase |
| `review_complete: true` + `phase_complete: false` | Review cannot complete before phase |

## Canonical progress.yaml Template

```yaml
# Build Loop — Progress State
# Schema: config + state read every iteration. Validate with yamllint.

config:
  verify: "<detected-verify-command>"
  max_tasks_per_phase: 200
  quality_check_suppressions: []
  build_loop_version:
    init_version: <VERSION>
    builds: []

state:
  # --- Lifecycle (owner: iterator) ---
  phase: null
  phase_complete: false
  status: idle

  # --- Task orchestration (owner: iterator) ---
  task_number: 1
  next_task: null
  last_result: null
  consecutive_fails: 0

  # --- Review (owner: iterator) ---
  review_stage: null
  review_complete: false
  pr_number: null

  # --- Retrospective (owner: retro) ---
  retro_complete: false

  # --- Tracking (owner: iterator) ---
  completed_stories: []
```

## Canonical log/<phase>.yaml Template

Created by the `start` action when a new phase begins:

```yaml
phase: "<phase-name>"
started: "<timestamp>"
entries: []
# Each entry: {task, time, story, description, result, notes, tokens}
```
