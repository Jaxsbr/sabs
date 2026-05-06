---
name: build-loop-iterate
description: "Core build loop — starts phases, runs the continuous iterate loop (Branch A/B), manages review lifecycle"
allowed-tools: "Bash(git *) Bash(gh *) Bash(npm *) Bash(npx *) Bash(make *) Bash(cargo *) Bash(python *) Bash(date *) Bash(mkdir *) Bash(cat *) Bash(echo *) Bash(grep *) Bash(curl *) Bash(yamllint *) Read(*) Write(*) Edit(*) Grep(*) Glob(*)"
disable-model-invocation: true
---

<!-- version: 12 -->
<!-- Sub-skill of build-loop. Read the router skill first for shared sections: parameters, scope restriction (including scope-check procedure), concurrency guard, resolve project root, phase spec format. -->
<!-- Router: ${CLAUDE_PLUGIN_ROOT}/skills/build-loop/SKILL.md -->
<!-- State machine reference: ${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/state-machine.md -->

## Action: `start`

Starts a new phase.

**Pre-check — progress state**: Read `docs/plan/progress.yaml`. If `status` is `running` and `phase_complete` is `false`, stop and report "A phase is already running."

**Pre-check — GitHub remote**: Run `git remote get-url origin`. If it fails (no remote configured), stop and report: "No GitHub remote found. The Review stage requires a remote to create PRs. Run `/sabs:build-loop action=init` to set up the remote, or add one manually with `git remote add origin <url>`." If the URL is not a GitHub URL, stop and report: "Remote `origin` does not point to GitHub. The build system requires GitHub for PRs and Actions."

**Dependency check**: If the phase spec (from `docs/product/<phase-name>.md` or the `phase-goal.md` being written) includes a `### Dependencies` section listing phase names, verify each listed phase has an entry in `docs/plan/archive/`. If any dependency is not archived, stop and report: "Phase `<name>` depends on `<missing-phase>` which has not completed. Complete and archive the dependency first."

**Branch management**: Every phase runs on a dedicated branch named `build/<phase-name>`. The `start` action is responsible for creating this branch from a clean, up-to-date default branch. Spec-author does not commit — it leaves spec changes (PRD, architecture docs, briefs) as uncommitted files. The `start` action carries these changes to the new build branch.

1. Determine the default branch name (check `git symbolic-ref refs/remotes/origin/HEAD` or fall back to `main`).
2. Check for uncommitted changes (`git status --porcelain`). If changes exist:
   - Classify every changed or untracked path:
     - **Spec files** — paths under `docs/` (PRD, architecture, briefs, plan drafts). Expected from spec-author.
     - **Non-spec files** — anything else.
   - If any non-spec files are present, stop and report: "Uncommitted non-spec changes detected: `<list>`. Commit or stash them before starting a new phase."
   - If only spec files are present, set `STASHED=true` and stash everything (tracked and untracked): `git stash push --include-untracked -m "spec-author changes for <phase-name>"`. This produces a clean working tree so the branch switch in step 4 cannot conflict.
   - If no uncommitted changes exist, set `STASHED=false`.
3. If the current branch is NOT the default branch:
   - Check for unmerged local commits: `git log origin/<default>..HEAD --oneline`. If any exist, restore the stash first (`git stash pop` if `STASHED`), then stop and report: "Branch `<current-branch>` has unmerged commits. Merge or discard before starting a new phase."
   - Checkout the default branch: `git checkout <default>`.
4. Pull the latest from the remote: `git pull origin <default>`.
5. Create and checkout the new build branch: `git checkout -b build/<phase-name>`.
6. If `STASHED`, pop the stash: `git stash pop`. If the pop reports conflicts, stop and report the conflicting files — the operator must resolve manually before restarting.
7. Push the branch with tracking: `git push -u origin build/<phase-name>`.

**Steps**:

1. If the previous phase is complete (`phase_complete: true` and `phase` is not `null`):
   - Move `docs/plan/log/<previous-phase>.yaml` to `docs/plan/archive/<previous-phase>.yaml`.
   - **Run the Phase Reconciliation Gate** (see below).
2. Check for a spec-author-produced phase spec:
   - **Primary:** Look for `docs/product/phases/<phase-name>.md` — the per-phase spec file (spec-author v4+ writes here).
   - **Fallback:** If no per-phase file exists, look for `docs/product/PRD.md` — read stories tagged for this phase (legacy inline format).
   - **Legacy fallback:** Look for `docs/product/<phase-name>.md` — older standalone spec format.
   - If a spec exists with done-when criteria, use them directly in `phase-goal.md`.
   - If no spec exists, the agent must write observable done-when criteria from the `goal` parameter or by investigating the project. Minimum 3 criteria.
3. Extract golden principles relevant to this phase from `AGENTS.md` and include them in `phase-goal.md`.
4. Update `docs/plan/progress.yaml`:
   - Set `phase`, `status: running`, `phase_complete: false`, `review_stage: null`, `review_complete: false`, `retro_complete: false`, `pr_number: null`, `task_number: 1`, `consecutive_fails: 0`, `completed_stories: []`.
   - **Version sync:** Read the version from `<!-- version: N -->` in the router skill (`${CLAUDE_PLUGIN_ROOT}/skills/build-loop/SKILL.md`). If the current version is not already in `config.build_loop_version.builds`, append it. If `build_loop_version` is missing or flat (legacy scalar), migrate to the structured format: `{ init_version: <existing or current>, builds: [<current>] }`. If the README contains the `<!-- build-loop -->` marker, update it to reflect the full version history (e.g. `init v12 | builds v12, v13`).
5. Write `docs/plan/phase-goal.md` using the Phase Specification Format (defined in the router skill).
6. Create `docs/plan/log/<phase>.yaml` using the log template (empty entries list). See state-machine reference for the template.
7. **Phase size guard:** Count the stories listed under "### Stories in scope" in `phase-goal.md`. If count > 5, refuse to start and report: "Phase has N stories (max 5). Split the phase using spec-author before starting. Evidence: phases with 6+ stories have 3-6x higher rework rates." Revert changes and stop.
8. Stage all changes (spec-author files carried from stash + phase setup files) and commit: `chore: start <phase> phase`
9. Enter the continuous iterate loop (Step 1 of `iterate`). The phase is initialized AND execution begins — the operator does not need to invoke `/sabs:build-loop` again.

**Single-phase execution:** The build loop operates one phase at a time. Multi-phase queuing is not supported. Start each phase individually after the previous one completes (including review and retro).

### Phase Reconciliation Gate

Runs when archiving a completed phase. Ensures the knowledge base reflects what was actually built.

**Crash-safe idempotency:** Reconciliation is a multi-step process. A session crash mid-reconciliation could leave steps partially applied. To handle this, use per-step markers instead of a single archive-exists check:

1. When archiving the phase log to `archive/<previous-phase>.yaml`, add a `reconciliation_status` field:
   ```yaml
   reconciliation_status:
     r0: pending
     r1: pending
     r2: pending
     r3: pending
     r4: pending
     r5: pending
   ```
2. Before each R-step runs, read `reconciliation_status` from the archived log. If the step's marker is `done`, skip it.
3. After each R-step completes successfully, update the marker to `done` in the archived log and save.
4. Step R5 (commit) only runs when R0-R4 are all `done`.
5. On resume after a crash, the agent re-enters reconciliation and each R-step checks its own marker — already-completed steps are skipped, remaining steps execute.

**Step R0 — Bulk PRD extraction (legacy inline phases)**:

Check whether `docs/product/PRD.md` contains inline story definitions (full `### US-XX` story bodies with acceptance criteria) for phases that have already been archived in `docs/plan/archive/`. For each such phase:

1. List all archived phase logs (`docs/plan/archive/*.yaml`) and identify their phase names.
2. For each archived phase, check if `docs/product/phases/<phase-name>.md` already exists. If yes, skip — already extracted.
3. If the per-phase file does NOT exist and the PRD contains inline stories for that phase (identifiable by the story IDs listed in the Implementation Phases table row), extract the stories and done-when criteria into `docs/product/phases/<phase-name>.md` with `Status: shipped` and `[Shipped]` tags.
4. After extracting all legacy phases, remove the inline story bodies and done-when checklists from the PRD — leave only the Implementation Phases table rows with links to the per-phase files.
5. If the PRD has no Implementation Phases table, create one from the extracted phases.

This step is idempotent — it only runs when there are legacy inline phases to extract. Once all phases have per-phase files, R0 is a no-op. R0 runs before R1 so the PRD is clean before the current phase's reconciliation begins.

**Step R1 — Reconcile `docs/architecture/ARCHITECTURE.md`** (if it exists):

1. Read the current architecture doc.
2. From the completed phase's log, identify structural additions: new modules, data flows, contracts, services, resolved decisions.
3. Update the architecture doc to reflect what was actually shipped.

**Step R2 — Reconcile product specs and PRD** (if `docs/product/PRD.md` exists):

R2a. **Per-phase spec file reconciliation:**
1. If `docs/product/phases/<completed-phase>.md` exists (spec-author v4+ format), update the file: set `Status: shipped`, tag completed stories with `[Shipped]`. If acceptance criteria changed during implementation, update them to reflect what shipped.
2. If the per-phase file does NOT exist but the PRD contains inline stories for this phase (legacy format), extract the phase's stories and done-when criteria into a new `docs/product/phases/<completed-phase>.md` with `Status: shipped` and `[Shipped]` tags. Remove the inline stories from the PRD, leaving only the index row. This is the backward-compatible migration path — each completed phase gets extracted on reconciliation.

R2b. **PRD index update:**
1. Ensure the PRD has an Implementation Phases table. If it doesn't, create one.
2. Update (or add) the row for the completed phase: set status to `Shipped`, list completed stories, link to `phases/<completed-phase>.md`.
3. If stories were discovered to be unnecessary, move to `docs/product/backlog.md` with a reason.
4. After extraction of inline stories (R2a step 2), verify the PRD contains no full story bodies for the completed phase — only the index row should remain. The PRD should trend toward being an index + product vision only.

**Step R3 — Reconcile project `AGENTS.md`**:

1. Read the project-level `AGENTS.md` at `PROJECT_ROOT`.
2. From the completed phase's log and shipped code, identify changes that affect agent guidance:
   - New files, modules, or exports -> update file ownership map and directory layout sections.
   - New or changed behavior rules -> update behavior, invariants, or operating rules sections.
   - New test files, fixtures, or conventions -> update testing section.
   - New commands, endpoints, or run instructions -> update running/setup sections.
   - Changed data model, schema fields, or contracts -> update data model section.
   - Changed scope boundaries -> update scope section.
3. Update the relevant sections to reflect what was actually built. Preserve accurate existing content; add, amend, or remove entries as needed.
4. Do not touch sections unrelated to the completed phase's work.

**Step R4 — Reconcile user documentation** (if a user manual or guide exists):

1. Check whether the project has user-facing documentation: look for `docs/manual/`, `docs/GUIDE.md`, or a "User Manual" section in `README.md`.
2. If user documentation exists:
   a. Read the done-when criteria for the completed phase. Identify criteria tagged with user documentation (e.g., "User manual section ... covers ...").
   b. For each shipped story that has user-facing behavior, check if the corresponding manual section or guide entry exists and is current.
   c. If a manual section is missing or stale, create or update it with: feature description, discovery path (where to find it in the UI or CLI), step-by-step usage, and any configuration required.
   d. If the project has a screenshot script (e.g., `docs/manual/take-screenshots.py`), note in the commit message which screenshots may need updating — do not auto-run the script.
3. If no user documentation exists but the phase introduced user-facing features, note this gap in the commit message for human review.

**Step R5 — Commit**: `docs: reconcile knowledge base after <phase> phase`

Reconciliation commits are included in the PR diff and reviewed during the Review stage. No separate operator approval is needed — the PR review catches errors.

Reconciliation must complete before the new phase setup begins.

### Phase retrospective (PR merge gate)

The phase retrospective is **not** run during `start`. It is enforced as a required GitHub PR status check — merge is blocked until phase-retro has been run and `retro_complete: true` is set in `progress.yaml`. See the project's `.github/workflows/phase-retro-check.yml`.

---

## Action: `iterate`

Runs the build loop continuously until the phase is complete or a stopping condition is met. Each iteration executes one unit of work, then loops back to Step 1. **This is a loop, not a single-shot command.**

**Stopping conditions (exit the loop):**
- Phase complete AND review complete (guard rail 4)
- Status set to `paused` (circuit breaker, max tasks, auth failure, inconsistent state)
- Abort requested

After each iteration, return to Step 1 immediately. Do NOT stop to report intermediate progress or ask the operator to re-invoke. The operator expects autonomous execution from invocation until a stopping condition is reached.

### Step 1 — Read state

Run `gh auth status` silently. If it fails, set `status: paused` with reason "GitHub authentication expired or unavailable." Report with instructions to re-authenticate and resume. Do NOT count as a consecutive failure. Stop.

Read `AGENTS.md` and `docs/plan/progress.yaml`. Extract all state and config fields. Read `docs/plan/phase-goal.md` for the done-when checklist and golden principles.

### Step 1.5 — State consistency check

Before guard rails, validate state consistency. If any of these are true, set `status: paused` and report "Inconsistent state detected" with recovery instructions. Stop.

See `${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/state-machine.md` for the full list of invalid state combinations.

- `phase_complete: true` + `review_complete: true` + `status: running` -> invalid (review is done; loop should have stopped).
- `phase: null` + `status: running` -> invalid.
- `task_number: 0` + `status: running` -> invalid.
- `retro_complete: true` + `phase_complete: false` -> invalid.
- `review_complete: true` + `phase_complete: false` -> invalid.

### Step 2 — Guard rails (stop on first match)

1. **status is `paused`**: Report resume instructions. Stop.
2. **consecutive_fails >= 5**: Set `status: paused`, log "circuit breaker — 5 consecutive failures". Report the last 5 failure summaries from `log/<phase>.yaml`. Group failures by type (verify fail, quality check fail, golden principle violation). If all 5 failures are the same type, suggest a specific action (e.g., "All failures are quality check: `no-bare-except`. Consider adding a suppression or fixing the underlying pattern."). Suggest: (a) resume after manual investigation, (b) `action=skip` to bypass the stuck task and re-investigate, (c) abort phase. Stop.
3. **task_number >= max_tasks_per_phase**: Set `status: paused`, log "run limit reached". Stop.
4. **phase_complete is `true` AND `review_complete` is `true`**: Report phase complete — PR is ready for human review and approval. Include the PR URL (from `pr_number` in progress.yaml). Stop. *(When `phase_complete` is `true` but `review_complete` is `false`, the loop falls through to Step 3 where Branch B schedules review tasks.)*

### Step 3 — Branch on next-task

#### Branch A — next-task is set

**If `next_task` starts with `[review]`:** This is a review-cycle task. Execute it following the Review Task Execution procedure (see Review stage section below). On success or failure, update state as described in the Review stage section, then **continue** — return to Step 1 (next iteration). Review tasks flow through the loop like any other task.

**Otherwise:** This is a normal implementation task. Proceed with steps 1-7 below.

1. Read spec files referenced in `AGENTS.md` relevant to this task.
2. **If the task involves UI components or styling**: read the frontend-design skill (Phase 3: `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/SKILL.md`) for design guidelines. If the phase spec or `AGENTS.md` includes a "Design direction" section, use it as the aesthetic brief. Apply the frontend-design principles — distinctive typography, committed color palette, intentional motion, no generic defaults. If no design direction is specified, choose a bold aesthetic that fits the project's purpose and audience, and note the choice in the commit message.
3. Execute the task: write/edit source, tests, or config. One concern only.
4. **Verify**: run the `verify` command. Capture output. Determine pass or fail. If verify passes, save the captured output to `docs/plan/test-baseline-current.txt` (overwrite if exists). This snapshot is used by the regression check in step 7.
5. **If verify passes — run the Golden Principles Gate**:
   - Read each golden principle from `phase-goal.md`.
   - Check whether the change violates any principle.
   - If a violation is found: treat as a fail. Do NOT commit. Queue a fix task that names the specific principle violated. Log as `fail — golden principle: <principle>`.
6. **If golden principles pass — run quality checks**:
   - Read the project's `AGENTS.md` for a `## Quality checks` section. If no such section exists, skip quality checks entirely.
   - For each listed check, run it against the codebase. Standard checks include: `no-silent-pass` (test files with early returns before assertions), `no-bare-except` (exception swallowing without logging), `no-innerhtml-user-data` (XSS via innerHTML with user-controlled data), `contract-validation` (schema files loaded by validation code). See the verify-gate skill (Phase 3) for the full check library.
   - If a check name appears in `quality_check_suppressions` (in progress.yaml config), skip it.
   - If the same quality check fails 3 times in a row on different fix attempts, log a warning: "Quality check `<name>` may be a false positive. Consider adding to suppressions."
   - If any quality check fails: treat as a fail. Do NOT commit. Queue a fix task naming the specific check that failed. Log as `fail — quality-check: <check-name>`.
7. **If quality checks pass — run regression check**:
   - If `docs/plan/test-baseline.txt` exists (from a previous successful task): run the regression-detect skill (Phase 3) with `baseline=docs/plan/test-baseline.txt current=docs/plan/test-baseline-current.txt`.
   - If `docs/plan/test-baseline.txt` does not exist (first task of phase): skip the regression check. The current snapshot will become the baseline after commit.
   - If the regression check returns FAIL (regressions found): treat as a fail. Do NOT commit. Queue a fix task naming the specific regressed tests. Log as `fail — regression: <test names>`.
8. **If pass (verify + golden principles + quality checks + regression check)**:
   - **Scope check:** Before committing, run the scope-check procedure (defined in the router skill's "Scope restriction" section) against every file that was created or modified in this task. If any file fails the scope check, do NOT commit. Log as `fail — scope violation`. Queue a fix task.
   - **Secrets scan:** Before committing, scan staged files for secrets patterns: files named `.env*`, `credentials*`, `*.key`, `*.pem`; file content containing patterns like `API_KEY=`, `SECRET=`, `-----BEGIN.*PRIVATE KEY-----`, `sk-`, `ghp_`, `aws_secret_access_key`. If a secret is detected, do NOT commit. Log as fail. Queue a fix task to remove the secret and add to `.gitignore`.
   - Commit the code change with conventional commit message.
   - **Promote test baseline:** copy `docs/plan/test-baseline-current.txt` to `docs/plan/test-baseline.txt`. This becomes the baseline for the next task's regression check.
   - **Run the Story Completion Gate** (see below).
   - Update `progress.yaml`: increment `task_number`, set `next_task: null`, set `last_result: pass`, reset `consecutive_fails: 0`.
   - Append log entry to `log/<phase>.yaml` (include story, description, result, notes, tokens). Record approximate token usage in the `tokens` field.
   - Commit progress update: `chore: progress #N — pass`
   - **Continue:** return to Step 1 (next iteration).
9. **If fail (verify, golden principles, quality checks, or regression check)**:
   - Do NOT commit broken code.
   - Update `progress.yaml`: increment `task_number`, set `next_task` to a fix description, set `last_result: fail`, increment `consecutive_fails`.
   - Append log entry to `log/<phase>.yaml` with failure summary.
   - Commit only progress update: `chore: progress #N — fail, queued fix`
   - **Continue:** return to Step 1 (next iteration — guard rails will check circuit breaker).

#### Branch B — next-task is "none"

**If `phase_complete: true` and `review_complete: false`:** Enter Review Task Scheduling (see Review stage section below) instead of normal investigation. Do NOT re-investigate done-when criteria or attempt to re-mark phase complete. After scheduling a review task, commit and **continue** — return to Step 1 (next iteration). The loop picks up the scheduled review task via Branch A on the next iteration.

**Otherwise:** Proceed with normal investigation (steps 1-4 below).

1. Investigate the current state:
   - Read `AGENTS.md` fully.
   - List the source directory.
   - Read `docs/plan/phase-goal.md` including done-when criteria.
   - Read the phase spec: check `docs/product/phases/<phase>.md` first, fall back to `docs/product/PRD.md` section for this phase.
   - Read last 5 entries from `docs/plan/log/<phase>.yaml`.
   - Run verify command.
   - Compare `AGENTS.md` against the current project structure. If the file ownership map, directory layout, behavior rules, testing conventions, or other agent guidance is stale relative to what has been built so far in this phase, treat updating `AGENTS.md` as a candidate next task.
   - If `docs/manual/`, `docs/GUIDE.md`, or another user guide exists, check which sections correspond to the current phase's stories. Include user documentation gaps (missing or stale manual sections for shipped features) as candidate tasks when determining the next task.
2. Check phase completion by walking the **done-when checklist**:
   - For each criterion, determine if it is met by inspecting files, test output, or code.
   - A phase is complete ONLY when every done-when criterion is checked AND verify passes.
   - If any criterion is not met, the phase is not complete regardless of other signals.
3. **If phase complete** — run the Phase Completion Gate before marking done:
   - Re-run verify one final time to confirm.
   - **Done-when audit:** Re-read every done-when criterion and verify it is actually met (not just that tests pass — the criterion itself must be true). If any criterion references a file, endpoint, or test by name, verify it exists and behaves as described.
   - **AGENTS.md consistency check:** Read AGENTS.md and identify any rules tagged "non-negotiable" or listed as invariants. For each, verify the code implements the stated behavior. Specifically check: edit policies match the actual enforcement code, schema/contract references point to files that exist, and directory structure descriptions match actual directories.
   - **Error-path spot check:** For each new or modified endpoint in this phase, verify at least one error-path test exists.
   - If any gate check fails: do NOT mark phase-complete. Instead, queue a fix task describing the specific gate failure. Log as `fail — completion gate: <check>`. Return to step 4.
   - If all gate checks pass: walk each done-when criterion and record evidence (file path, test name, or output line that proves it).
   - Update `progress.yaml`: set `phase_complete: true`. Append evidence summary entry to `log/<phase>.yaml`.
   - Commit: `chore: progress #N — <phase> phase complete`
4. **If phase not complete**:
   - **Classify the phase type** (on first investigation only — cache for subsequent iterations):
     - **Server/schema/cross-cutting**: the phase's stories modify server code, schema files, or cross-cutting concerns (edit policy, validation, data model). Every implement task MUST be preceded by an investigate task.
     - **CSS/JS-only (no server changes)**: investigate-first is recommended but not mandatory.
   - Identify unmet done-when criteria. Group them by story (`[US-XX]` tags).
   - Queue the single most valuable next task toward meeting an unmet criterion. **Prefer completing a partially-done story** (some criteria met) over starting a new one.
   - **Investigate-first mandate** (server/schema/cross-cutting phases): if the next task is an implementation task (not a fix for a previous failure), queue it as `"Investigate: <what to check before implementing>"` instead. The investigate task confirms current test count, identifies affected files, and queues the specific implement task on its next iteration. This eliminates the spec-misread class of rework.
   - Priority: unmet criteria for in-progress stories -> unmet criteria for not-started stories -> failing tests -> missing tests -> stale `AGENTS.md` -> stale or missing user documentation -> other documentation gaps.
   - Note which story the queued task advances (from the criterion's `[US-XX]` tag).
   - Update `progress.yaml`: set `next_task` (prefix with the target story ID, e.g., `"[US-XX] implement input validation for capture endpoint"`), reset `consecutive_fails: 0` (investigation is a successful resolution). Append log entry to `log/<phase>.yaml` with story and rationale.
   - Commit: `chore: progress #N — queued next task`
   - **Continue:** return to Step 1 (next iteration — Branch A will execute the queued task).

### Story Completion Gate

Runs after each successful code commit in Branch A. Produces a dedicated story-level milestone commit when all done-when criteria for a user story are met.

**Procedure**:

1. Identify which story the just-completed task was advancing (from the `[US-XX]` prefix in `next_task`).
2. Collect all done-when criteria in `phase-goal.md` tagged with that story's `[US-XX]`.
3. For each criterion, verify it is currently met by inspecting files, running tests, or checking command output.
4. If ALL criteria for the story are met AND the story is not already in `completed_stories`:
   a. Check off the story's criteria boxes in `phase-goal.md` (`- [ ]` -> `- [x]`).
   b. Add the story ID to `completed_stories` in `progress.yaml`.
   c. Commit: `feat(US-XX): complete <story title>` — this is the **story milestone commit**.
   d. Append a note to the current task's log entry in `log/<phase>.yaml`: `US-XX complete`.
5. If a task plausibly affects criteria for other stories (e.g., a shared module or cross-cutting concern), check those stories as well.
6. If criteria are not all met, do nothing — the story is still in progress.

**Orphan criteria (`[phase]` tag):** Criteria tagged `[phase]` instead of a story ID are NOT checked by the Story Completion Gate. They are checked only during the Phase Completion Gate (Branch B, step 3). The Story Completion Gate only processes criteria tagged with a specific story ID `[US-XX]`.

**Why story commits matter**: They create clear, scannable milestones in git history. `git log --grep="^feat(US-"` shows exactly when each user story was delivered, without wading through individual task commits.

---

## Review stage — continuous, task-scheduled

The review cycle runs through the same Branch A/B task mechanism as the build phase. Review tasks are scheduled and executed like any other task — the loop does not stop between them. After the phase completes, the loop continues iterating: Branch B schedules review tasks, Branch A executes them, until `review_complete` is set and guard rail 4 stops the loop.

The operator's only touchpoint is reviewing and merging the final PR. If the operator wants additional review passes beyond the automated first pass, they can manually run review-pr or handle-pr-review.

### Review task scheduling (Branch B)

When Branch B detects `phase_complete: true` and `review_complete: false`, it schedules the next review task based on `review_stage`:

| `review_stage` | Action |
|---|---|
| `null` | Create PR via `gh pr create` from `build/<phase-name>` to the default branch. PR body includes: phase summary (from `phase-goal.md`), stories shipped (from `completed_stories`), done-when evidence (from phase log). Store the PR number in `pr_number`. Set `review_stage: pr_created`. Queue: `[review] review-pr pr=<number> auto=true`. |
| `pr_created` | Queue: `[review] review-pr pr=<pr_number> auto=true`. *(Recovery case — PR exists but review-pr hasn't run yet.)* |
| `review_posted` | Queue: `[review] handle-pr-review pr=<pr_number> auto=true`. |

After scheduling: increment `task_number`, commit `chore: progress #N — queued review task`, then **continue** — return to Step 1. The loop picks up the queued review task on the next iteration via Branch A.

### Review task execution (Branch A)

When Branch A detects a `[review]` prefix on `next_task`:

1. **Parse and execute the review task:**
   - `[review] review-pr pr=N auto=true` -> Read the review-pr skill (Phase 3: `${CLAUDE_PLUGIN_ROOT}/skills/review-pr/SKILL.md`) and follow it with the specified parameters. The review is posted to the PR as inline comments.
   - `[review] handle-pr-review pr=N auto=true` -> Read the handle-pr-review skill (Phase 3: `${CLAUDE_PLUGIN_ROOT}/skills/handle-pr-review/SKILL.md`) and follow it with the specified parameters. Triages review comments, fixes valid issues, challenges incorrect ones, skips nits. After fixes, re-run the project's verify command + quality checks to catch regressions from review fixes. If checks fail, fix within this session (regression fixes are code fixes, not review actions).

2. **On success:**
   - Update `review_stage`:

     | Completed task | New `review_stage` | Next action |
     |---|---|---|
     | `review-pr` | `review_posted` | Loop continues -> Branch B schedules handle-pr-review |
     | `handle-pr-review` | *(not set)* | Set `review_complete: true`. Post summary comment (see below). |

   - Set `next_task: null`, `last_result: pass`, increment `task_number`.
   - Append log entry to `log/<phase>.yaml`.
   - Commit: `chore: progress #N — review task pass`
   - **Continue:** return to Step 1. (If `review_complete` was just set, guard rail 4 will stop the loop and report: "Phase review complete. PR is ready for human review and approval.")

3. **On failure:** Same as normal Branch A failure — do NOT commit broken code. Increment `consecutive_fails`, set `next_task` to a fix description, log the failure. The circuit breaker applies to review tasks the same as build tasks. **Continue:** return to Step 1.

### Post-review summary

When `handle-pr-review` completes successfully and quality checks pass, post a summary comment to the PR before setting `review_complete: true`:

```markdown
## Phase review complete

**Built:** <phase summary from phase-goal.md>
**Stories:** <completed_stories list>
**Reviewed:** <review-pr findings summary — N critical, N concern, N nit>
**Fixed:** <handle-pr-review actions — N fixed, N challenged, N skipped>
**Quality checks:** Pass

Ready for human review and approval.
```

```bash
gh pr comment <pr_number> --body "$(cat <<'EOF'
...summary...
EOF
)"
```
