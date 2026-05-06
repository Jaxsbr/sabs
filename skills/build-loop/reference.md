# Build Loop Quick Reference

Quick-reference for stages, actions, and skill dispatch.

## Four-Stage Workflow

```
Spec (human-driven) -> Build (agent-driven) -> Review (agent-driven) -> Compound (agent + human)
```

| Stage | Driven By | Key Skill |
|-------|-----------|-----------|
| Spec | Human (via spec-author) | `/sabs:build-loop action=start` consumes spec output |
| Build | Agent (autonomous) | `/sabs:build-loop action=iterate` |
| Review | Agent (autonomous, human approves) | Review tasks scheduled within iterate loop |
| Compound | Agent analyzes, human approves | `/sabs:phase-retro` (Phase 3+) |

## Action Dispatch

| Action | Handled By | Description |
|--------|-----------|-------------|
| `init` | `/sabs:build-loop-init` | Scaffold build infrastructure in a project (7 gates) |
| `start` | `/sabs:build-loop-iterate` | Start a new phase on a dedicated branch |
| `iterate` | `/sabs:build-loop-iterate` | Run the continuous build loop |
| `skip` | `/sabs:build-loop` (router) | Skip stuck task, re-investigate |
| `resume` | `/sabs:build-loop` (router) | Resume from paused state |
| `abort` | `/sabs:build-loop` (router) | Abandon current phase |
| `status` | `/sabs:build-loop` (router) | Read-only status snapshot |

## Init Gates (build-loop-init)

| Gate | Purpose |
|------|---------|
| 1 | Git repository |
| 2 | GitHub remote |
| 3 | `gh` authentication and permissions |
| 4 | Git identity |
| 5 | Default branch |
| 6 | Branch protection |
| 7 | Build scaffolding (idempotent) |
| 8 | Skill version compatibility |
| 9 | Command shadow check |

## Iterate Loop (build-loop-iterate)

### Branch A — Execute Task (next_task is set)

1. Read spec files from AGENTS.md
2. Check for frontend design guidance (if UI task)
3. Execute task (one concern only)
4. Run verify command
5. Run Golden Principles Gate (if verify passes)
6. Run quality checks (if golden principles pass)
7. Run regression check (if quality checks pass)
8. On pass: scope check, secrets scan, commit, story completion gate, update progress
9. On fail: do NOT commit code, queue fix, update progress

### Branch B — Investigate (next_task is null)

- If `phase_complete: true` and `review_complete: false`: schedule review tasks
- Otherwise: investigate state, check done-when, queue next task

### Stopping Conditions

- Phase complete AND review complete
- Status set to `paused` (circuit breaker, max tasks, auth failure)
- Abort requested

## Guard Rails

| # | Condition | Action |
|---|-----------|--------|
| 1 | Status is `paused` | Report resume instructions, stop |
| 2 | `consecutive_fails >= 5` | Circuit breaker, pause, suggest options |
| 3 | `task_number >= max_tasks_per_phase` | Run limit reached, pause |
| 4 | Phase complete AND review complete | Report done, stop |

## Review Stages

| `review_stage` | Meaning |
|----------------|---------|
| `null` | No review started — create PR |
| `pr_created` | PR exists — run review-pr |
| `review_posted` | Review posted — run handle-pr-review |

## Key Files (per project)

| Path | Purpose |
|------|---------|
| `docs/plan/progress.yaml` | State machine |
| `docs/plan/phase-goal.md` | Current phase spec with done-when criteria |
| `docs/plan/log/<phase>.yaml` | Phase execution log |
| `docs/plan/archive/` | Completed phase logs and retros |
| `docs/product/PRD.md` | Product vision and phase index |
| `docs/product/phases/<phase>.md` | Per-phase spec files |
| `AGENTS.md` | Project-level quality checks and guidance |

## Plugin Documentation (read-only reference, ships with plugin)

| Path | Purpose |
|------|---------|
| `${CLAUDE_PLUGIN_ROOT}/docs/MANUAL.md` | Build system user manual |

## Project-Local Files (created during build-loop execution)

| Path | Purpose |
|------|---------|
| `docs/plan/LEARNINGS.md` | Project-specific compound learnings (appended by phase-retro) |
