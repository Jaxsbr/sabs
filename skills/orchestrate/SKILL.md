---
name: orchestrate
description: "EXPERIMENTAL (45% failure rate) — chains multiple briefs through the full spec -> build -> review -> retro -> merge cycle autonomously"
allowed-tools: "Bash(git *) Bash(gh *) Bash(npm *) Bash(npx *) Bash(make *) Bash(cargo *) Bash(python *) Bash(date *) Bash(mkdir *) Bash(cat *) Bash(echo *) Bash(grep *) Bash(curl *) Bash(yamllint *) Bash(jq *) Read(*) Write(*) Edit(*) Grep(*) Glob(*)"
disable-model-invocation: true
---

<!-- version: 1 -->
Chain multiple briefs through the full spec -> build -> review -> retro -> merge cycle autonomously.

## Parameters

- `project` — path to the project root (absolute, or relative to cwd; required)
- `briefs` — comma-separated brief topic names, or `all` to process every `status: draft` brief in `docs/briefs/` (required)
- `mode` — `supervised` (default) or `autonomous`. Supervised pauses after the first brief for operator confirmation before continuing. Autonomous chains all briefs without pause.
- `dry_run` — if `true`, run spec-author only (no build/merge) to preview specs. Default `false`.

---

## Safety guardrails

These are non-negotiable. The orchestrator CANNOT override them.

1. **Stop-on-red**: Any failed merge gate halts the entire chain. The operator must inspect and decide whether to continue.
2. **No force-push**: Never `git push --force` or `git reset --hard`.
3. **Must-fix blocks merge**: If phase-retro produces findings with `data-loss` or `security-gap` class, halt and require operator input.
4. **Abort file**: Before each phase checkpoint, check for `docs/plan/.orchestrator-stop` in the project. If it exists, halt the chain immediately and report status.
5. **CI must pass**: PR merge requires all GitHub status checks to pass.
6. **No unresolved review threads**: PR merge requires zero unresolved review conversations.
7. **Retro must complete**: `retro_complete: true` must be set in progress.yaml before merge.
8. **Sequential only**: Each brief runs to full completion (merged to main) before the next begins. No parallel branches.
9. **Merge method**: Always use `gh pr merge --squash` (squash merge). The story milestone commits are preserved in the branch history and PR description; the main branch stays clean.

---

## Resolve project root

Same rules as build-loop (see `${CLAUDE_PLUGIN_ROOT}/skills/build-loop/SKILL.md`, "Resolve project root"):
1. If `project` is absolute, use directly.
2. If relative, resolve against cwd.
3. Validate the directory exists and contains `AGENTS.md`.

Note: The orchestrator does not create projects — it operates on existing ones. The directory confirmation flow (step 4 in the build-loop) only applies to `init`.

---

## Orchestrator log

Write all orchestrator activity to `docs/plan/orchestrator-log.yaml` in the project. Create if it doesn't exist. Format:

```yaml
run_started: "<ISO timestamp>"
mode: "<supervised|autonomous>"
briefs_queued: [<list of brief topics>]
phases: []
# Each phase entry:
# - brief: "<topic>"
#   phase_name: "<derived phase name>"
#   started: "<ISO timestamp>"
#   spec_complete: "<ISO timestamp or null>"
#   build_complete: "<ISO timestamp or null>"
#   review_complete: "<ISO timestamp or null>"
#   retro_complete: "<ISO timestamp or null>"
#   merged: "<ISO timestamp or null>"
#   status: "<running|merged|failed|halted>"
#   failure_reason: "<reason or null>"
#   pr_number: <number or null>
#   retro_findings_count: <number>
#   must_fix_count: <number>
```

Update the log after each milestone. This is the operator's async review artifact.

---

## Execution flow

For each brief in the queue:

### Checkpoint — abort file

Check for `docs/plan/.orchestrator-stop`. If it exists, halt immediately. Report: which briefs completed, which brief was in progress, which briefs remain. Remove the file after reporting.

### Checkpoint — supervised mode pause

- If `mode=supervised`: run the first brief to completion (including merge), then pause. Report results and ask: "Continue with remaining N briefs autonomously?" If confirmed, switch to autonomous for the rest.
- If `mode=autonomous`: no pauses.

### Step 1 — Spec-author (inline)

The orchestrator performs the spec-author work inline by following the spec-author contract:

1. Read the brief from `docs/briefs/<topic>-brief.md`.
2. Read `AGENTS.md`, `docs/product/PRD.md`, existing `docs/product/phases/`, `docs/architecture/ARCHITECTURE.md`, `docs/plan/progress.yaml`.
3. Derive the phase name from the brief topic (e.g., `markdown-toolbar-icons-brief` -> `markdown-toolbar-icons`).
4. Follow the spec-author pipeline:
   - **Step 1 — Clarify intent**: Parse What/Why/Where/Constraints from the brief. Since the operator pre-approved these briefs, do NOT ask clarifying questions — the brief is the source of truth. If critical information is genuinely missing (no "What" or "Where"), halt and report.
   - **Step 2 — Draft user stories**: Write stories following the project's PRD format, using the brief's content. Follow existing ID conventions from the PRD.
   - **Step 3 — Draft done-when criteria**: Translate acceptance criteria into mechanically verifiable checks. Apply all safety criteria rules from the spec-author skill (LLM output safety, async cleanup, API input allowlisting, catch-all route scoping). Write to `docs/plan/phase-goal-draft.md`.
   - **Step 4 — Write phase spec**: Write `docs/product/phases/<phase-name>.md`. Update PRD index. Mark brief `status: specced`. Delete the draft file.
   - **Step 5 — Architecture intent**: Review architecture doc (read-only — no forward-looking content). Identify AGENTS.md impact. Extract golden principles.
   - Run the readiness checklist. If any check fails, halt the chain.
5. **Do not commit** — the build-loop `start` action handles this.

**Phase size gate**: If stories exceed 5, halt and report. The operator must split the brief.

### Step 2 — Build-loop start + iterate

Invoke the build-loop by reading `${CLAUDE_PLUGIN_ROOT}/skills/build-loop/SKILL.md` and following it with:
- `action=start`
- `phase=<phase-name>`
- `project=<project-path>`

The build-loop runs autonomously through build and review stages. It stops when `review_complete: true` (guard rail 4).

If the build-loop pauses (circuit breaker, max tasks, etc.), halt the orchestrator chain and report status.

### Step 3 — Phase-retro

After build-loop reports review complete:

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/phase-retro/SKILL.md` and follow it with `project=<project-path>` and `phase=<phase-name>`.
2. The retro analyzes the phase, classifies failures, applies the twice-seen rule.
3. **Compounding fix handling**: For fixes that would normally require operator approval:
   - **Auto-approve** fixes at prevention points (a) spec-author gate and (c) quality check — these are low-risk additions to guardrails.
   - **Auto-approve** fixes at (b) AGENTS.md rule — these document what was built.
   - **Halt for operator input** on any fix the retro flags as `data-loss` or `security-gap`.
   - Log all auto-approved fixes in the orchestrator log.
4. Push the retro commit to the remote to unblock the retro-gate check.

### Step 4 — Merge gate

**Important: retro-gate vs merge gate.** The retro-gate GitHub Action is a PR status check that *intentionally* fails until phase-retro runs and pushes `retro_complete: true`. This is normal — Step 3 handles it. After Step 3 pushes, the retro-gate re-runs and passes. The merge gate below runs *after* the retro push, when all checks should be green.

Before merging, ALL of these must be true:

1. `retro_complete: true` in progress.yaml (should already be true from Step 3)
2. All GitHub status checks pass: `gh pr checks <pr_number> --watch` (wait up to 5 minutes for retro-gate and any CI to re-run after the retro push)
3. No unresolved PR review conversations: `gh api repos/{owner}/{repo}/pulls/<pr_number>/reviews` — all reviews must be APPROVED or COMMENTED (not CHANGES_REQUESTED)
4. No merge conflicts: `gh pr view <pr_number> --json mergeable -q .mergeable` must be `MERGEABLE`
5. No `must-fix` retro findings (data-loss or security-gap class)

If ANY condition fails:
- Log the failure reason in the orchestrator log.
- Halt the chain. Report which condition failed and what the operator should do.
- Do NOT attempt to fix merge gate failures automatically.

### Step 5 — Merge

```bash
gh pr merge <pr_number> --squash --delete-branch
```

After merge:
- Checkout the default branch and pull: `git checkout main && git pull origin main`
- Update the orchestrator log: set status to `merged`, record timestamp.
- Verify progress.yaml is back to idle state (the build-loop `start` of the next phase handles archiving).

### Step 6 — Brief completion

Log the completed brief. Move to the next brief in the queue. Return to the top of the execution flow.

---

## After all briefs complete

Produce a summary report in the orchestrator log and output to the operator:

```
## Orchestrator run complete

Briefs processed: N/N
Total phases merged: N
Total retro findings: N (M compounding fixes applied)
Halted: <yes/no — reason if yes>

Phase summary:
- <phase-name>: merged (PR #N) — <stories shipped>
- <phase-name>: merged (PR #N) — <stories shipped>
...

Review the app and provide product-owner feedback as new briefs or concepts.
```

### Write completion summary file

Write `docs/orchestrate-completion-summary.md` in the project root. This file is overwritten on each orchestrator run so the operator always has a quick catch-up artifact.

```markdown
# Orchestrate completion summary

**Run started:** <ISO timestamp>
**Run finished:** <ISO timestamp>
**Mode:** <supervised|autonomous>
**Briefs processed:** N/N
**Halted:** <yes/no — reason if yes>

## Phases

| # | Phase | PR | Stories shipped | Retro findings | Compounding fixes | Status |
|---|-------|-----|----------------|----------------|-------------------|--------|
| 1 | <phase-name> | #<pr> | <count> | <count> | <count> | merged |
| 2 | <phase-name> | #<pr> | <count> | <count> | <count> | merged |

## Key changes

<!-- One-paragraph summary per phase: what was built and why it matters. -->

- **<phase-name>**: <summary>
- **<phase-name>**: <summary>

## Retro highlights

<!-- Only if there were notable retro findings or compounding fixes. Omit section if zero findings. -->

- <finding summary + fix applied>

## Next steps

<!-- Carry forward any operator actions from halts, retro must-fixes, or product feedback prompts. -->

- Review the app and provide product-owner feedback as new briefs or concepts.
```

---

## Error recovery

If the orchestrator is re-invoked after a halt:
1. Read `docs/plan/orchestrator-log.yaml`.
2. Find the last phase that was not `merged`.
3. Check its status and determine where it stopped.
4. Resume from that point — do not re-run completed steps.

If the orchestrator log doesn't exist, start fresh.

---

## Scope restriction

Same as build-loop: all file operations confined to the project root, except workspace-level compounding fixes on the allowlist. The orchestrator inherits the build-loop's scope-check procedure.
