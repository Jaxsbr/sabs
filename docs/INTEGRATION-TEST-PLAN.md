# SABS Integration Test Plan

**Version:** 0.2.0
**Date:** 2026-04-10
**Purpose:** End-to-end validation of the SABS plugin.

**How to use this plan:** Work through each section sequentially. Check the box when a test passes. If a test fails, note the failure in the "Notes" column and stop that section -- fix before continuing to the next.

> **Paths in this document use placeholders.** `/Users/{you}/path/to/sabs/` is the absolute path to your local SABS checkout — Claude Code's `--plugin-dir` flag requires an absolute path, so substitute your real path before running the commands. References like `/Users/{you}/legacy/dev/` describe a hypothetical legacy install location used in regression checks; substitute or skip if not applicable.

**Recommended test project:** A small, low-risk project with an existing `AGENTS.md`, prior build-loop history, and a simple verify command (e.g., `npm run lint && npm run test`). If you have multiple candidates, choose one without an active phase in progress.

**Estimated time:** 45-60 minutes for a full pass (30-40 minutes if skipping the full build-loop cycle in Section 4).

---

## Section 1: Plugin Loading Tests

Launch Claude Code with the plugin loaded:

```bash
claude --plugin-dir /Users/{you}/path/to/sabs/
```

| # | Test | What to check | Pass | Notes |
|---|------|---------------|------|-------|
| 1.1 | Plugin loads without errors | No error messages or warnings on startup related to plugin loading | [ ] | |
| 1.2 | Hook loads without errors | No warnings about `hooks/hooks.json` or `gh-identity-guard.sh` | [ ] | |
| 1.3 | All 13 skills visible | Type `/sabs:` and verify tab-completion or listing shows all 13 skills below | [ ] | |
| 1.4 | Skill names match expected | Verify each skill name exactly matches the list below | [ ] | |

### Expected skill names (13 total)

All skills must appear with the `/sabs:` prefix:

| # | Skill Name | Full Invocation |
|---|-----------|-----------------|
| 1 | `build-loop` | `/sabs:build-loop` |
| 2 | `build-loop-init` | `/sabs:build-loop-init` |
| 3 | `build-loop-iterate` | `/sabs:build-loop-iterate` |
| 4 | `verify-gate` | `/sabs:verify-gate` |
| 5 | `test-gate` | `/sabs:test-gate` |
| 6 | `regression-detect` | `/sabs:regression-detect` |
| 7 | `phase-retro` | `/sabs:phase-retro` |
| 8 | `phase-goal-review` | `/sabs:phase-goal-review` |
| 9 | `review-pr` | `/sabs:review-pr` |
| 10 | `handle-pr-review` | `/sabs:handle-pr-review` |
| 11 | `spec-author` | `/sabs:spec-author` |
| 12 | `frontend-design` | `/sabs:frontend-design` |
| 13 | `orchestrate` | `/sabs:orchestrate` |

**Note:** `frontend-design` has `user-invocable: false` in its frontmatter. Verify it still loads (it is referenced by the build-loop during UI tasks) but may not appear in user-facing autocomplete depending on Claude Code's handling of that flag.

---

## Section 2: Identity Guard Tests

The identity guard is a PreToolUse hook on Bash commands. It fires on every Bash tool invocation and checks the git identity against a config file.

### 2.1 No config file (silent no-op)

**Setup:** Ensure neither `${CLAUDE_PLUGIN_DATA}/identities.json` nor `/Users/{you}/path/to/sabs/config/identities.json` exists. (The example file is named `identities.example.json`, not `identities.json`, so the default state is no config.)

| # | Test | Steps | Expected | Pass | Notes |
|---|------|-------|----------|------|-------|
| 2.1.1 | No config = no-op | In a git repo, ask Claude to run any Bash command (e.g., `ls`) | Command runs without any identity warning. No output from the hook. | [ ] | |

### 2.2 Config present but no matching remote

**Setup:** Create `config/identities.json` (copy from `config/identities.example.json`). Ensure no `remote_pattern` matches the current repo's `origin` URL.

```bash
cp /Users/{you}/path/to/sabs/config/identities.example.json \
   /Users/{you}/path/to/sabs/config/identities.json
```

| # | Test | Steps | Expected | Pass | Notes |
|---|------|-------|----------|------|-------|
| 2.2.1 | No matching remote = no-op | Navigate to a repo whose origin does NOT match any pattern in the config. Run a Bash command. | Command runs without any identity warning. | [ ] | |

### 2.3 Matching remote with correct identity

**Setup:** Edit `config/identities.json`. Add an entry whose `remote_pattern` matches the current repo's origin, and set `user_name` and `user_email` to the values currently configured in that repo (`git config user.name` / `git config user.email`).

| # | Test | Steps | Expected | Pass | Notes |
|---|------|-------|----------|------|-------|
| 2.3.1 | Correct identity = silent pass | Run a Bash command in the matching repo. | Command runs without any identity warning. | [ ] | |

### 2.4 Matching remote with wrong identity

**Setup:** Edit `config/identities.json`. Set `user_name` or `user_email` to a value that does NOT match the repo's current git config.

| # | Test | Steps | Expected | Pass | Notes |
|---|------|-------|----------|------|-------|
| 2.4.1 | Wrong identity = warning | Run a Bash command in the matching repo. | Hook output includes `gh-identity-guard: Git identity mismatch` with the expected vs actual values and a `git config` fix command. The Bash command itself still executes (warning only, not blocking). | [ ] | |

**Cleanup:** Delete `config/identities.json` after tests to restore the default no-config state.

```bash
rm /Users/{you}/path/to/sabs/config/identities.json
```

---

## Section 3: Per-Skill Invocation Tests

Test each skill individually. These tests verify the skill loads, accepts parameters, and produces expected output. They do NOT test full end-to-end flows (that is Section 4).

**Test project:** Use the test project chosen above. Ensure you are in the project directory or pass `project=<path>`.

### 3.1 build-loop (router/dispatcher)

**Invocation:** `/sabs:build-loop project=<path> action=status`

| What to check | Expected |
|---------------|----------|
| Skill loads and accepts `project` and `action` parameters | No errors on invocation |
| `action=status` reads `progress.yaml` and reports state | Output includes: phase, status, task number, phase_complete, done-when checklist |
| Read-only -- no file changes | `git status` shows no changes after invocation |

Pass: [ ]

### 3.2 build-loop-init

**Invocation:** `/sabs:build-loop-init project=<path-to-temp-test-dir>`

Create a temporary test directory first:
```bash
mkdir -p /tmp/sabs-test-init
```

| What to check | Expected |
|---------------|----------|
| Skill prompts for project purpose (no AGENTS.md in empty dir) | Asks "What is this project's purpose?" |
| Gate 1 runs (git init) | `.git/` created |
| Gate 2 prompts for GitHub remote | Prompts for account/repo/visibility |
| Gate 7 scaffolds build infrastructure | Creates `docs/plan/`, `docs/plan/log/`, `docs/plan/archive/`, `docs/product/phases/`, `docs/concepts/`, `docs/briefs/`, `progress.yaml`, `phase-goal.md`, `.github/workflows/phase-retro-check.yml`, `.github/pull_request_template.md` |
| Gate 8 checks skill versions | Reports version compatibility (all should be current) |
| Gate 9 checks for command shadows | Reports any shadowing skills in `~/.claude/skills/` or `~/.claude/commands/` |
| README gets build-loop marker | `<!-- build-loop -->` section appended |

**Note:** You can abort at the GitHub remote prompt (Gate 2) if you do not want to create a test repo. The earlier gates still validate. For full testing, allow it to complete all gates.

Pass: [ ]

**Cleanup:**
```bash
rm -rf /tmp/sabs-test-init
```

### 3.3 build-loop-iterate

**Invocation:** `/sabs:build-loop-iterate project=<path> action=start phase=<test-phase>`

| What to check | Expected |
|---------------|----------|
| Reads `progress.yaml` and validates state | If a phase is running, reports "A phase is already running." If idle, proceeds. |
| Creates build branch `build/<phase-name>` | Branch exists after invocation |
| Writes `phase-goal.md` with done-when criteria | File contains Phase Specification Format |
| Creates `log/<phase>.yaml` | Log file exists with empty entries list |
| Updates `progress.yaml` with phase name, status: running | Fields set correctly |
| Enters the iterate loop | Begins Branch A or Branch B execution |

**Note:** This is a long-running test -- it will continue iterating until a stopping condition. Use Ctrl+C or let it complete a few iterations.

Pass: [ ]

### 3.4 verify-gate

**Invocation:** `/sabs:verify-gate project=<path>`

| What to check | Expected |
|---------------|----------|
| Reads `AGENTS.md` for `## Quality checks` section | Reports configured checks |
| Runs `root-agents-immutable` first (non-optional) | Reports pass/fail for immutable check |
| Runs each configured check | Per-check pass/fail results |
| Output format matches spec | `## Verify Gate Results` header, counts, per-check results |
| Read-only -- no file modifications | `git status` unchanged |

Pass: [ ]

### 3.5 test-gate

**Invocation:** `/sabs:test-gate project=<path>`

| What to check | Expected |
|---------------|----------|
| Gate 1 (Verify) runs the project's verify command | Exit code 0 = PASS, non-zero = FAIL |
| Gate 2 (Golden Principles) skipped if no `phase-goal` param | Reports SKIP |
| Gate 3 (Quality Checks) reads AGENTS.md quality checks | Runs configured checks or reports SKIP |
| Gate 4 (Regression Detection) skipped if no `baseline` param | Reports SKIP |
| Output matches structured format | `## Test Gate Results` header, per-gate results, verdict |
| Read-only -- never modifies files | `git status` unchanged |

Pass: [ ]

### 3.6 regression-detect

**Invocation:** `/sabs:regression-detect baseline=<path-to-baseline> current=<path-to-current>`

Create two test files:
```bash
echo "tests/test_a.py::test_one PASSED
tests/test_a.py::test_two PASSED" > /tmp/sabs-baseline.txt

echo "tests/test_a.py::test_one PASSED
tests/test_a.py::test_two FAILED" > /tmp/sabs-current.txt
```

| What to check | Expected |
|---------------|----------|
| Parses both files for test results | Recognizes pytest-style output |
| Identifies regressions | `test_two` listed as regression (was PASS, now FAIL) |
| Verdict is FAIL when regressions exist | `### Verdict: FAIL` |
| Output format matches spec | `## Regression Detection Results` header, sections for regressions/fixes/new/removed |
| Read-only | No files modified |

Pass: [ ]

**Cleanup:**
```bash
rm /tmp/sabs-baseline.txt /tmp/sabs-current.txt
```

### 3.7 phase-retro

**Invocation:** `/sabs:phase-retro project=<path>`

| What to check | Expected |
|---------------|----------|
| Reads `progress.yaml` and identifies target phase | Uses most recently archived phase, or errors if none |
| Reads phase log from `log/` or `archive/` | Finds the correct log file |
| Extracts phase metrics | Reports: total tasks, investigate, fail, rework, rework rate, health |
| Classifies failures using taxonomy | Uses failure classes from `failure-classes.md` |
| Applies twice-seen rule against previous retros | Checks `archive/*.retro.md` for prior occurrences |
| Writes retro to `archive/<phase>.retro.md` | File created with correct format |
| Sets `retro_complete: true` in progress.yaml | Field updated |
| Proposes compounding fixes (if any) | Presents fixes for approval |

**Note:** This requires a completed phase with a log. If the test project has no completed phase, this test can be deferred to Section 4.

Pass: [ ]

### 3.8 phase-goal-review

**Invocation:** `/sabs:phase-goal-review project=<path>`

| What to check | Expected |
|---------------|----------|
| Reads `docs/plan/phase-goal-draft.md` | Errors if file does not exist ("No phase-goal-draft.md found") |
| Reads project-local `docs/plan/LEARNINGS.md` if present (skips gracefully if absent) | Built-in dimensions still apply when no learnings file exists |
| Reads `AGENTS.md` for project type and golden principles | Uses project type for scope filtering |
| Applies all 10 review dimensions | Checks subjective criteria, spec ambiguity, phase size, error-path, etc. |
| Output format matches spec | `## Phase Goal Review` header, gaps/borderline/clean sections |
| Read-only -- does not edit the draft | No files modified |

**Note:** This requires a `phase-goal-draft.md` to exist. Create one via spec-author first, or create a minimal test file.

Pass: [ ]

### 3.9 review-pr

**Invocation:** `/sabs:review-pr pr=<pr-number> mode=local`

| What to check | Expected |
|---------------|----------|
| Identifies the PR from parameter or current branch | Fetches PR metadata |
| Fetches diff and existing review comments | Uses `gh pr diff` and GraphQL |
| Classifies findings (Critical/Concern/Nit/Skip) | Triage presented |
| `mode=local` displays findings without posting | Nothing posted to GitHub |
| Large PR scoping works (if applicable) | Prioritizes files by churn |

**Note:** Requires an open PR. If none exists, create one or skip this test until Section 4.

Pass: [ ]

### 3.10 handle-pr-review

**Invocation:** `/sabs:handle-pr-review pr=<pr-number>`

| What to check | Expected |
|---------------|----------|
| Checks `gh auth status` | Reports auth status or errors |
| Fetches unresolved review threads via GraphQL | Lists threads with classifications |
| Triages each thread (Fix/Challenge/Skip) | Presents triage for confirmation |
| Holistic analysis before code changes | Groups related threads |
| Posts summary comment after handling | Summary with Fixed/Challenged/Skipped sections |

**Note:** Requires a PR with review comments. If none exists, skip until Section 4.

Pass: [ ]

### 3.11 spec-author

**Invocation:** `/sabs:spec-author project=<path>`

| What to check | Expected |
|---------------|----------|
| Reads `AGENTS.md`, `PRD.md`, existing phase specs | Loads project context |
| Gate 1 asks for scope clarification | Prompts: What/Why/Where/Constraints |
| Gate 2 drafts stories with done-when criteria | Stories use project's ID convention, criteria are mechanically verifiable |
| Writes `docs/plan/phase-goal-draft.md` | Full spec in Phase Specification Format |
| Runs phase-goal-review against built-in dimensions + project-local LEARNINGS.md (if present) | Auto-fixes gaps, reports remaining items |
| Presents compact summary table | Story/Title/Criteria/Safety table in chat |
| Does NOT commit | `git status` shows uncommitted changes only |
| Phase size gate enforced (max 5 stories) | Refuses if > 5 stories |

Pass: [ ]

### 3.12 frontend-design

**Invocation:** Not directly user-invocable (`user-invocable: false`). Referenced by the build-loop during UI tasks.

| What to check | Expected |
|---------------|----------|
| Skill file exists and is well-formed | SKILL.md loads without errors |
| `user-invocable: false` is respected | Skill does not appear in user-facing autocomplete (or is appropriately flagged) |
| Content accessible to build-loop | Build-loop can read the file path `${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/SKILL.md` |

**Verification method:** During a build-loop iteration on a UI task, check that the agent references frontend-design guidance (look for typography, color, motion keywords in the agent's reasoning). Alternatively, verify the file is readable:

```
Ask Claude: "Read the file at ${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/SKILL.md and summarize the core principle."
```

Pass: [ ]

### 3.13 orchestrate (experimental)

**Invocation:** `/sabs:orchestrate project=<path> briefs=all dry_run=true`

| What to check | Expected |
|---------------|----------|
| Skill loads and accepts parameters | No errors on invocation |
| `dry_run=true` runs spec-author only, no build/merge | Specs drafted but no branches created, no PRs |
| Reads briefs from `docs/briefs/` | Lists draft briefs found (or reports none) |
| Safety guardrails listed in output | Mentions stop-on-red, no force-push, etc. |
| Orchestrator log created at `docs/plan/orchestrator-log.yaml` | File created with run metadata |

**Note:** This skill has a documented 45% failure rate. `dry_run=true` is the safe testing path.

Pass: [ ]

---

## Section 4: Full Build-Loop Cycle Test

Step-by-step walkthrough of a complete spec-to-retro cycle on a test project. This is the most thorough test and validates end-to-end integration.

**Test project:** Your chosen test project from Section 1.
**Pre-requisite:** The test project must have:
- A git repo with a GitHub remote
- An `AGENTS.md` with quality checks
- `docs/plan/progress.yaml` in idle state (no active phase)

If the project has an active phase, either complete it first or use `action=abort` to reset.

### Step 4.1 -- Verify starting state

```
/sabs:build-loop project=<path> action=status
```

| Check | Expected | Pass | Notes |
|-------|----------|------|-------|
| Status is `idle` | `status: idle`, `phase: null` | [ ] | |
| No active build branch | `git branch` shows only main/default | [ ] | |
| progress.yaml exists with current schema | Has `config` and `state` sections | [ ] | |

### Step 4.2 -- Run spec-author for a test phase

```
/sabs:spec-author project=<path>
```

Describe a small, low-risk feature (e.g., "add a help button that shows keyboard shortcuts" or "add a score display animation").

| Check | Expected | Pass | Notes |
|-------|----------|------|-------|
| Gate 1 clarifies scope | Asks What/Why/Where/Constraints | [ ] | |
| Gate 2 drafts stories + done-when | Presents summary table, writes draft file | [ ] | |
| Phase-goal-review runs (built-in dimensions + project LEARNINGS.md if present) | Reports gaps/borderline/clean | [ ] | |
| Approval triggers auto-complete (Steps 3-4) | Per-phase spec file written, PRD updated, readiness checklist passes | [ ] | |
| Files remain uncommitted | `git status` shows modified/new files in docs/ | [ ] | |
| Output includes start command | Shows `/sabs:build-loop project=<path> action=start phase=<name>` | [ ] | |

### Step 4.3 -- Start the build phase

Use the exact command output from spec-author:

```
/sabs:build-loop project=<path> action=start phase=<phase-name>
```

| Check | Expected | Pass | Notes |
|-------|----------|------|-------|
| Spec files stashed and carried to build branch | Stash push, branch create, stash pop succeed | [ ] | |
| Build branch `build/<phase-name>` created | `git branch` shows the new branch | [ ] | |
| Branch pushed to remote with tracking | `git push -u origin build/<phase-name>` succeeds | [ ] | |
| `progress.yaml` updated | phase set, status: running, task_number: 1 | [ ] | |
| `phase-goal.md` written with done-when criteria | Phase Specification Format with criteria, story tags, golden principles | [ ] | |
| `log/<phase>.yaml` created | Empty entries list, phase name, started timestamp | [ ] | |
| Concurrency lock acquired and released | `.build-loop.lock` created on entry, removed on exit | [ ] | |
| Iterate loop starts automatically | Agent begins Branch B investigation | [ ] | |

### Step 4.4 -- Observe iterate loop

Let the loop run for 3-5 iterations. Observe:

| Check | Expected | Pass | Notes |
|-------|----------|------|-------|
| Branch B investigates and queues tasks | `next_task` populated with story-tagged description | [ ] | |
| Branch A executes tasks (one concern per iteration) | Code changes, verify runs, quality checks run | [ ] | |
| Verify command runs on each task | `npm run lint && npm run test` (or project equivalent) | [ ] | |
| Golden principles checked after verify passes | Reports pass or violation | [ ] | |
| Quality checks run after golden principles pass | Runs AGENTS.md-configured checks | [ ] | |
| Regression check runs (after first successful task) | Compares baseline to current test output | [ ] | |
| Passing tasks committed with conventional format | `feat:`, `fix:`, `chore:` prefixes | [ ] | |
| Failing tasks do NOT commit code | Only progress update committed | [ ] | |
| Story Completion Gate fires on story done | `feat(US-XX): complete <title>` commit appears when all criteria for a story are met | [ ] | |
| `progress.yaml` updated each iteration | task_number increments, next_task cycles null->set->null | [ ] | |
| `log/<phase>.yaml` grows | New entries with task, time, story, result, notes, tokens | [ ] | |
| `test-baseline.txt` promoted on pass | Copied from `test-baseline-current.txt` after successful commit | [ ] | |
| Scope check runs before commit | No writes outside project root (except allowlisted paths) | [ ] | |
| Secrets scan runs before commit | No `.env`, credentials, API keys committed | [ ] | |
| Layer rules respected | If AGENTS.md has layer rules, changes comply | [ ] | |

### Step 4.5 -- Observe phase completion and review

When all done-when criteria are met:

| Check | Expected | Pass | Notes |
|-------|----------|------|-------|
| Phase Completion Gate runs | Re-runs verify, audits each done-when criterion, checks AGENTS.md consistency | [ ] | |
| `phase_complete: true` set in progress.yaml | Field updated | [ ] | |
| PR created via `gh pr create` | PR exists on GitHub from `build/<phase>` to default branch | [ ] | |
| PR body includes phase summary, stories, evidence | Meaningful PR description | [ ] | |
| `review_stage: pr_created` set | Field updated, `pr_number` set | [ ] | |
| review-pr runs automatically | Self-review posted to PR as inline comments (COMMENT event) | [ ] | |
| `review_stage: review_posted` set | Field updated | [ ] | |
| handle-pr-review runs automatically | Triages review comments, fixes valid issues, challenges incorrect ones | [ ] | |
| Post-review summary comment posted to PR | Shows Built/Stories/Reviewed/Fixed/Quality checks | [ ] | |
| `review_complete: true` set | Field updated | [ ] | |
| Loop stops (guard rail 4) | Reports "Phase review complete. PR is ready for human review and approval." with PR URL | [ ] | |

### Step 4.6 -- Run phase-retro

```
/sabs:phase-retro project=<path>
```

| Check | Expected | Pass | Notes |
|-------|----------|------|-------|
| Reads completed phase log | Finds log in `log/<phase>.yaml` or `archive/` | [ ] | |
| Extracts metrics | Task counts, rework rate, investigate ratio, health status | [ ] | |
| Fetches PR review threads (if PR exists) | Classifies Critical/Concern findings | [ ] | |
| Classifies failures from build log | Uses failure class taxonomy | [ ] | |
| Applies twice-seen rule | Checks previous retros in `archive/*.retro.md` | [ ] | |
| Writes retro to `archive/<phase>.retro.md` | Correct format with metrics, failure classes, compounding fixes | [ ] | |
| Sets `retro_complete: true` | progress.yaml updated | [ ] | |
| Updates PRD index to "Shipped" | Phase row status changed | [ ] | |
| Cleans up consumed briefs (`status: specced`) | Specced briefs deleted | [ ] | |
| Commits and pushes to remote | Retro commit reaches remote, retro-gate check re-runs | [ ] | |
| Proposes compounding fixes (if patterns found) | Presents fixes for approval | [ ] | |

### Step 4.7 -- Verify PR merge readiness

After retro completes:

| Check | Expected | Pass | Notes |
|-------|----------|------|-------|
| retro-gate GitHub Action passes (green check) | `Phase retro complete -- check passed` | [ ] | |
| All PR status checks pass | `gh pr checks <number>` all green | [ ] | |
| PR is mergeable | `gh pr view <number> --json mergeable` returns `MERGEABLE` | [ ] | |

**DO NOT merge during testing** unless you want to commit the test phase to the project permanently.

---

## Section 5: Regression Checklist

Cross-cutting concerns that span multiple skills. Verify these work correctly across the plugin.

| # | Check | How to verify | Pass | Notes |
|---|-------|---------------|------|-------|
| 5.1 | Cross-skill file references resolve | Skills reference `${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md`. Verify these paths resolve to actual files when the plugin is loaded. Check: build-loop references build-loop-init, build-loop-iterate, verify-gate, frontend-design, review-pr, handle-pr-review, phase-retro. | [ ] | |
| 5.2 | Project-local `LEARNINGS.md` handling | phase-goal-review reads `<project>/docs/plan/LEARNINGS.md` when present and skips gracefully when absent. Verify behavior in both states. | [ ] | |
| 5.3 | `MANUAL.md` referenced correctly | build-loop reference.md mentions `${CLAUDE_PLUGIN_ROOT}/docs/MANUAL.md`. Verify this resolves. | [ ] | |
| 5.4 | `progress.yaml` state machine works | Run `action=status` and verify all fields from the canonical template are present. Check field types match (strings, booleans, integers, lists). | [ ] | |
| 5.5 | Phase logs written correctly | After at least one iterate, verify `log/<phase>.yaml` has entries with: task, time, story, description, result, notes, tokens. | [ ] | |
| 5.6 | GitHub Actions workflow scaffolded on init | After `build-loop-init`, verify `.github/workflows/phase-retro-check.yml` exists with the correct job name `retro-gate`. | [ ] | |
| 5.7 | PR template scaffolded on init | After `build-loop-init`, verify `.github/pull_request_template.md` exists with the pre-merge checklist. | [ ] | |
| 5.8 | No `~/dev/` references in any skill | Search all skill files for hardcoded references to `~/dev/`, `$HOME/dev/`, or `/Users/{you}/legacy/dev/`. Must find zero matches. | [ ] | |
| 5.9 | No hardcoded `~/.claude/commands/` references | Search all skill files for `~/.claude/commands/`. Must find zero matches. Skill references use `${CLAUDE_PLUGIN_ROOT}/skills/` instead. | [ ] | |
| 5.10 | Skill version frontmatter present | Each skill that declares a version has `<!-- version: N -->`. Verify: build-loop (12), build-loop-init (12), build-loop-iterate (12), verify-gate (3), test-gate (1), regression-detect (1), phase-retro (4), phase-goal-review (1), review-pr (3), handle-pr-review (no version comment), spec-author (6), frontend-design (1), orchestrate (1). | [ ] | |
| 5.11 | `disable-model-invocation` respected | Skills with `disable-model-invocation: true` (build-loop, build-loop-init, build-loop-iterate, spec-author, orchestrate) should not trigger model sub-invocations. Verify during invocation. | [ ] | |
| 5.12 | Hook PreToolUse matcher targets Bash only | `hooks.json` matcher is `"Bash"`. Verify the hook does not fire on non-Bash tool uses (e.g., Read, Write, Edit). | [ ] | |
| 5.13 | Concurrency lock (.build-loop.lock) lifecycle | During build-loop execution, verify lock file is created on entry and removed on exit. Verify it is listed in `.gitignore`. | [ ] | |
| 5.14 | Compounding fix allowlist enforced | phase-retro should only write to paths within the project root or on the allowlist: `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md`. | [ ] | |

### Verification command for 5.8 and 5.9

Run these searches against the skills directory (do this outside of Claude Code, in a regular terminal):

```bash
# Check for ~/dev/ references (should return nothing)
grep -r "~/dev/\|\\$HOME/dev/\|/Users/{you}/legacy/dev/" /Users/{you}/path/to/sabs/skills/

# Check for ~/.claude/commands/ references (should return nothing)
grep -r "~/.claude/commands/" /Users/{you}/path/to/sabs/skills/
```

---

## Section 6: Pass/Fail Criteria

### Overall pass

The plugin passes integration testing when ALL of the following are true:

1. **Section 1 (Plugin Loading):** All 4 tests pass. All 13 skills are visible.
2. **Section 2 (Identity Guard):** All 4 scenarios behave as expected (silent no-op x3, warning x1).
3. **Section 3 (Per-Skill Invocation):** At least 11 of 13 skills pass individual invocation tests. Acceptable deferrals:
   - `frontend-design` (non-user-invocable, tested indirectly via build-loop UI tasks)
   - `orchestrate` (experimental, `dry_run` mode tested)
4. **Section 4 (Full Build-Loop Cycle):** All steps from 4.1 through 4.6 pass. Step 4.7 (merge readiness) is informational.
5. **Section 5 (Regression Checklist):** All 14 cross-cutting checks pass. Items 5.8 and 5.9 (no legacy references) are hard blockers.
6. **No data loss, no secrets exposure, no destructive operations** observed during any test.

### Failure categories

| Category | Severity | Action |
|----------|----------|--------|
| **Blocker** | Skill fails to load, hook crashes, `~/dev/` reference found, secrets in commit, data loss | Fix before cutover. Do not ship. |
| **Critical** | Skill produces wrong output, state machine corruption, cross-skill reference broken, PR workflow fails | Fix before cutover if possible. Document workaround if time-constrained. |
| **Minor** | Formatting issues, non-essential warning, non-blocking UX quirk | Document and fix post-cutover. |
| **Cosmetic** | Wording, help text, non-functional display issues | Log for future improvement. |

### Known differences from `~/dev/` version

These are expected changes from the migration and should NOT be treated as failures:

| Difference | Explanation |
|------------|-------------|
| Skill invocations use `/sabs:` prefix | Plugin namespace replaces bare `/` commands |
| File paths use `${CLAUDE_PLUGIN_ROOT}` | Replaces hardcoded `~/dev/.claude/commands/` paths |
| Identity guard is config-driven | Replaces hardcoded identity checks in the old system |
| Learnings written to project-local `docs/plan/LEARNINGS.md` | Plugin no longer ships a baseline learnings file |
| `MANUAL.md` at plugin root `docs/` | Replaces `~/dev/docs/build-system/MANUAL.md` |
| `hooks.json` replaces legacy hook wiring | New Claude Code plugin hook format |

---

## Appendix: Quick Reference

### Plugin launch command
```bash
claude --plugin-dir /Users/{you}/path/to/sabs/
```

### Key file locations (plugin)
| File | Path |
|------|------|
| Plugin manifest | `projects/sabs/.claude-plugin/plugin.json` |
| Hook config | `projects/sabs/hooks/hooks.json` |
| Identity guard script | `projects/sabs/scripts/gh-identity-guard.sh` |
| Identity config example | `projects/sabs/config/identities.example.json` |
| MANUAL.md | `projects/sabs/docs/MANUAL.md` |

### Key file locations (per-project, created by build-loop)
| File | Path |
|------|------|
| Project charter | `AGENTS.md` |
| Progress state | `docs/plan/progress.yaml` |
| Phase goal | `docs/plan/phase-goal.md` |
| Phase log | `docs/plan/log/<phase>.yaml` |
| Phase archive | `docs/plan/archive/<phase>.yaml` |
| Phase retro | `docs/plan/archive/<phase>.retro.md` |
| Phase spec | `docs/product/phases/<phase>.md` |
| PRD index | `docs/product/PRD.md` |
| Retro gate workflow | `.github/workflows/phase-retro-check.yml` |
| PR template | `.github/pull_request_template.md` |
