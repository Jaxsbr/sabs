---
name: build-loop
description: "Router/dispatcher for the Semi-Autonomous Build System — runs lifecycle actions on a project's build loop"
allowed-tools: "Bash(git *) Bash(gh *) Bash(npm *) Bash(npx *) Bash(make *) Bash(cargo *) Bash(python *) Bash(date *) Bash(mkdir *) Bash(cat *) Bash(yamllint *) Read(*) Write(*) Edit(*) Grep(*) Glob(*)"
disable-model-invocation: true
---

<!-- version: 13 -->
Run one iteration of the build loop, or perform a lifecycle action on a project's build loop.

## Parameters

- `project` — path to the project root (absolute, or relative to cwd). If omitted, inferred from cwd.
- `action` — one of: `iterate` (default), `init`, `start`, `resume`, `skip`, `status`, `abort`
- `phase` — phase name, required for `start`
- `goal` — phase goal text, optional for `start` (if omitted, agent writes it after investigating)
- `reset_fails` — if `true`, reset `consecutive_fails` to 0 (optional, only for `resume`)

---

## CRITICAL: Scope restriction

All file reads, writes, edits, and shell commands MUST be confined to the resolved project root, **except** compounding fixes approved during phase-retro, which may target workspace-level paths listed in the allowlist below. Refuse writes outside project root AND outside the allowlist.

**Compounding fix allowlist (workspace-level paths):**
- `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md`

**Note on LEARNINGS.md:** Compounding fixes that add new learnings go to the **project-local** `docs/plan/LEARNINGS.md` (created on first write if it doesn't exist). The plugin does not ship a baseline learnings file — each project accumulates its own. Skills that read learnings (phase-goal-review, spec-author) read the project-local file when present and skip gracefully if absent. Skills that write learnings (phase-retro) write only to the project-local file.

### Scope-check procedure

Before any file write, edit, or shell write-redirect, run this check against the target path. This procedure is reusable — phase-retro references it for compounding fix application.

1. Resolve the target to an absolute path.
2. If the target starts with `PROJECT_ROOT` -> **allowed**.
3. If the target matches any path in the compounding fix allowlist -> **allowed**, but only during phase-retro compounding fix application. During normal `iterate` execution, only `PROJECT_ROOT` paths are allowed.
4. If the target is the project's `AGENTS.md` at `PROJECT_ROOT/AGENTS.md` -> **always allowed** (project-level).
5. If the target is the workspace root `AGENTS.md` (outside `PROJECT_ROOT`) -> **always rejected**. The root charter is immutable; no agent action may modify it.
6. Otherwise -> **reject**. Log as `fail — scope violation: <target path>`. Queue a fix task to correct the path.

---

## Concurrency guard

Before any mutating action (`init`, `start`, `iterate`, `resume`, `abort`, `skip`), check for `docs/plan/.build-loop.lock`.

- **If lock exists:** Read its content (session ID, timestamp, action, phase). If the lock is stale (>30 minutes old), warn: "Stale lock from session {session_id} (action: {action}, phase: {phase}, since {timestamp}). Delete `docs/plan/.build-loop.lock` and retry." Offer to break it. If fresh, report "Build loop is locked by session {session_id} (action: {action}, phase: {phase}, since {timestamp})" and stop.
- **On entry:** Create the lock file with: `session_id` (unique per invocation), `timestamp`, `action`, `phase` (current phase name from progress.yaml, or `null` for `init`).
- **On exit** (success or failure): Remove the lock file.
- The lock file should never be committed — add `.build-loop.lock` to `.gitignore` during `init` Gate 7.
- Locks are scoped to the project — different projects can run concurrently.

---

## Resolve project root

1. If `project` is provided and is an absolute path, use it directly.
2. If `project` is provided and is relative, resolve it against the current working directory.
3. If `project` is omitted: check if cwd contains a project-level `AGENTS.md`. If yes, use cwd. If cwd has no `AGENTS.md`, error with "specify project=".
4. If the directory does not exist:
   - **If action is `init`:** The resolved path is the **proposed** project directory. Before creating it:
     1. Present the resolved path to the operator: "Project will be created at: `<resolved-path>`. Confirm, or provide an alternative path."
     2. If the operator confirms (or says "yes", "ok", "proceed", etc.), create the directory with `mkdir -p <resolved-path>`. Report "Created project directory at `<resolved-path>`."
     3. If the operator provides an alternative path, resolve that path (absolute as-is, relative against cwd), then create with `mkdir -p <alternative-path>`. Report "Created project directory at `<alternative-path>`." Use the alternative path as PROJECT_ROOT going forward.
   - If action is NOT `init`: stop and report "Project directory `<path>` does not exist. Run `action=init` first."
5. Set `PROJECT_ROOT` to the resolved (or operator-overridden) path.

---

## Companion tool: spec-author

This build loop is one half of a delivery pair. The other half is the **spec-author** skill, which produces phase specifications with observable done-when criteria.

The build loop consumes what the spec-author produces. Spec-author (v4+) writes per-phase spec files to `docs/product/phases/<phase-name>.md` and adds a summary row to the PRD index. The build loop reads the per-phase file and transposes its done-when criteria into `docs/plan/phase-goal.md` using the **Phase Specification Format** (see below).

If a phase is started without a spec-author-produced specification, the build loop still works, but the agent must write observable done-when criteria during the `start` action before any execution begins.

---

## Phase Specification Format (shared contract)

This is the format written to `docs/plan/phase-goal.md`. The spec-author produces it; the build loop verifies against it.

```markdown
## Phase goal

<Narrative description of the phase objective.>

### Dependencies (optional)
- <phase-name that must be archived before this phase can start>

### Stories in scope
- US-XX — Story title
- US-YY — Story title

### Done-when (observable)
- [ ] Criterion 1 [US-XX] (mechanically verifiable — a specific file exists, endpoint returns a shape, test covers a case)
- [ ] Criterion 2 [US-XX]
- [ ] Criterion 3 [US-YY]
- ...

### Golden principles (phase-relevant)
- Principle text (extracted from AGENTS.md, relevant to this phase's work)
- ...
```

**Rules for done-when criteria:**
- Every criterion must be mechanically verifiable — not "works well" but "POST /api/x returns 201 with { id }".
- Every criterion must be tagged with the story ID it satisfies (e.g., `[US-XX]`). This tag is how the build loop tracks per-story completion and produces story commits. Orphan criteria (not tied to a story) are tagged `[phase]` and need explicit justification.
- Story tags `[US-XX]` must appear at the end of the criterion text, before any parenthetical example. Example: `- [ ] POST /api/x returns 201 with { id } [US-01] (curl or test output)`.
- Minimum 3 criteria per phase.
- The build loop checks these literally during phase completion. If a criterion can't be checked by reading files, running tests, or inspecting output, it's not observable enough.

---

## Action dispatch

Based on the `action` parameter, read the corresponding sub-skill and follow it:

- **`init`**: Read `${CLAUDE_PLUGIN_ROOT}/skills/build-loop-init/SKILL.md` and follow it. Or invoke `/sabs:build-loop-init`.
- **`start`**, **`iterate`**: Read `${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/SKILL.md` and follow it. Or invoke `/sabs:build-loop-iterate`.
- **`skip`**, **`resume`**, **`abort`**, **`status`**: Handled below in this file.

---

## Action: `skip`

Skips the current stuck task and re-investigates.

1. Read `progress.yaml`. Verify `status` is `paused`.
2. Set `next_task: null`, `consecutive_fails: 0`, `status: running`.
3. Commit: `chore: skip stuck task, re-investigating`
4. Enter the continuous iterate loop (read `${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/SKILL.md`, Action: `iterate`, Step 1).

---

## Action: `resume`

1. Read `progress.yaml`. Verify `status` is `paused`.
2. Update `progress.yaml`: set `status: running`. If `reset_fails=true` is passed, also set `consecutive_fails: 0`.
3. Commit: `chore: resume build loop`
4. Enter the continuous iterate loop (read `${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/SKILL.md`, Action: `iterate`, Step 1).

**Note:** If operator added a quality check suppression while paused, they should also pass `reset_fails=true` to avoid the circuit breaker firing prematurely on the next failure.

---

## Action: `abort`

Abandons the current phase without completing it. Preserves all PRD and spec content — only the build branch work is abandoned.

1. Read `progress.yaml`. Verify `status` is not `idle`.
2. Archive: move `log/<phase>.yaml` to `archive/<phase>.yaml` with a `status: aborted` field added.
3. Archive `phase-goal.md` content to `archive/<phase>.retro.md` as context for future retro analysis.
4. Run Phase Reconciliation Gate (defined in `${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/SKILL.md`) on whatever was actually shipped (partial reconciliation — only reconcile what was committed). Do NOT tag incomplete stories as `[Shipped]` in the PRD — only tag stories in `completed_stories`. Skip user documentation reconciliation for stories that weren't completed.
5. Reset `progress.yaml` to idle state (`phase: null`, `status: idle`, `phase_complete: false`, `review_stage: null`, `review_complete: false`, `retro_complete: false`, `pr_number: null`, `consecutive_fails: 0`, `completed_stories: []`).
6. Commit: `chore: abort <phase> phase`
7. Report: tasks completed, stories completed (if any), reason for abort. Note that PRD stories remain in their current state — nothing is removed from the PRD.

The build branch is NOT reverted. The operator decides whether to cherry-pick partial work, revert, or start fresh.

---

## Action: `status`

Read-only snapshot. No file changes.

Read `progress.yaml`, `phase-goal.md`, and tail of `log/<phase>.yaml`. Report: phase, status, task number, phase_complete, last result, next task, done-when checklist with met/unmet markers, last 5 log entries.

---

## Layer rules enforcement

During all code changes (Branch A in `${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/SKILL.md`), if `AGENTS.md` contains layer rules, read them before execution and verify the planned change doesn't violate any rule. If it would, queue a refactoring task instead.

---

## Conventions

- All commits use conventional format: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`.
- **Story commits** use scoped format: `feat(US-XX): complete <story title>`. These are milestone markers in git history — one per user story, produced by the Story Completion Gate.
- Never commit broken code (failing verify or golden principles). Only commit progress updates on failure.
- One concern per iteration.
- Tasks in `next-task` are prefixed with their target story ID: `"[US-XX] <task description>"`.
- If a task description in `next-task` is unclear, investigate (Branch B) to clarify before executing.
- Timestamps via: `date -u +"%Y-%m-%dT%H:%M:%SZ"`
