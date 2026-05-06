# Semi-Autonomous Build System — User Manual

> **Version:** 9
> **Updated:** 2026-03-24
> **Audience:** You (the operator). Written from your perspective, not the agent's.

This manual describes how to take a feature idea from specification through shipped, reviewed, and compounded code — with you driving the spec and approving the final PR, and the agent handling everything in between.

---

## Workflow overview

Four stages, repeating:

```
  You drive          Agent drives         Agent + you              Agent drives
┌──────────┐    ┌──────────────────┐    ┌──────────────────┐    ┌────────────────┐
│   SPEC   │───▶│      BUILD       │───▶│     REVIEW       │───▶│   COMPOUND     │──┐
│          │    │                  │    │                  │    │                │  │
│ Define   │    │ Implement tasks  │    │ Create PR (auto) │    │ PR check gates │  │
│ stories, │    │ Investigate-first│    │ Review PR (auto) │    │ merge until    │  │
│ done-when│    │ Quality checks   │    │ Fix findings     │    │ retro is done  │  │
│ criteria │    │ Phase completion │    │ Re-check (auto)  │    │ ────────────── │  │
│          │    │ gate             │    │                  │    │ YOU: run retro │  │
│          │    │                  │    │ YOU: approve +   │    │ Approve fixes  │  │
│          │    │                  │    │      merge       │    │                │  │
└──────────┘    └──────────────────┘    └──────────────────┘    └────────────────┘  │
     ▲                                                                              │
     └──────────────────────────────────────────────────────────────────────────────┘
```

**Your touchpoints:**

1. **Init** — you answer prompts (GitHub account, repo name, visibility) if the repo doesn't exist yet (once per project)
2. **Spec** — you describe the feature, approve stories and done-when criteria
3. **Retro** — you run `/sabs:phase-retro` before merge (enforced by a PR check)
4. **Approve + merge** — you review a PR that has already been self-reviewed and self-fixed

Everything else is agent-driven.

---

## Idea pipeline

Ideas mature through three directories before becoming running code. Each directory signals readiness — agents and operators can tell at a glance what needs shaping vs what's ready to build.

```
  docs/concepts/          docs/briefs/           docs/product/
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────────┐
│    CONCEPT       │───▶│     BRIEF        │───▶│       SPEC                  │
│                  │    │                  │    │                             │
│ What + Why       │    │ What, Why, Where │    │ PRD.md (index + vision)     │
│ Rough scope      │    │ Constraints      │    │ phases/<name>.md (detail)   │
│ Dependencies     │    │ Key decisions    │    │                             │
│                  │    │ Open questions   │    │ Ready for build             │
│ Needs shaping    │    │ Ready for spec   │    │                             │
└─────────────────┘    └─────────────────┘    └─────────────────────────────┘
   idea-shape              idea-shape              spec-author
   (creates)               (promotes to)           (writes from brief)
```

| Directory | Status | Contains | Next step |
|---|---|---|---|
| `docs/concepts/` | `concept` | What + Why + dependency. Enough to not lose the idea. | Run idea-shape to promote to a brief |
| `docs/briefs/` | `draft` | What, Why, Where, Constraints, key decisions, open questions. Fully shaped. | Run spec-author to write stories and done-when criteria |
| `docs/product/PRD.md` | n/a | Product vision, feature overview, Implementation Phases index table. Links to per-phase spec files. | Stays small — index only |
| `docs/product/phases/<name>.md` | n/a | Full phase spec: user stories, acceptance criteria, done-when checklists. One file per phase. | Run build-loop to execute |

**How ideas flow:**

1. **Loose idea** -> Shape the idea into a brief (`docs/briefs/`). If multi-phase scope emerges, future phases are captured as concepts (`docs/concepts/`).
2. **Concept → Brief** → When ready to build a later phase, run idea-shape in amendment mode. It promotes the concept to a full brief by sharpening What/Why into Where/Constraints/decisions.
3. **Brief -> Spec** -> Run `/sabs:spec-author`. It consumes the brief and produces user stories and done-when criteria in a per-phase spec file (`docs/product/phases/<name>.md`), with a summary row added to the PRD index.
4. **Spec → Build** → Run `/sabs:build-loop action=start phase=<name>` in Claude Code. The agent reads the per-phase spec file and builds autonomously against it.

**Why three stages, not one?** Ideas lose detail when they're crammed into a single artifact too early. A concept captures "we'll need this later" in 30 seconds. A brief captures "here's exactly what and why" in 10 minutes. A spec captures "here's how to verify it's done" in 30 minutes. Each stage adds precision only when you're ready to commit to that precision.

**Scanning for work:** To see what's in the pipeline for a project, check:
- `docs/concepts/` — ideas waiting to be shaped
- `docs/briefs/` — shaped ideas waiting to be specced
- `docs/product/PRD.md` — Implementation Phases index table shows all phases and their status
- `docs/product/phases/` — per-phase spec files with full stories and done-when criteria

---

## Project resolution

All build system commands need to know which project to operate on. The `project` parameter accepts an absolute or relative path to the project root.

**Rules:**

| Action | `project` param | Behaviour |
|---|---|---|
| `init` | **Required** | `init` establishes the project — it cannot infer what doesn't exist yet. If omitted, `init` asks you for the project name. Resolves to an absolute path (relative paths resolve against cwd), confirms the directory with the operator, and creates it if needed. |
| All other actions (`start`, `resume`, `status`, `abort`) | Optional | If provided, resolves to an absolute path. If omitted, checks whether cwd contains a project-level `AGENTS.md` and uses cwd as the project. If cwd has no `AGENTS.md`, errors with "specify project=". |

**Examples:**

| You're in | You type | Project resolves to |
|---|---|---|
| `/home/user/projects/` | `/sabs:build-loop project=repo-1 action=init` | `/home/user/projects/repo-1` |
| `/home/user/projects/` | `/sabs:build-loop project=repo-1 action=start phase=mvp` | `/home/user/projects/repo-1` |
| `/home/user/projects/repo-1/` | `/sabs:build-loop action=start phase=mvp` | `/home/user/projects/repo-1` (inferred from cwd) |
| `/home/user/projects/repo-1/` | `/sabs:build-loop project=/other/path/repo-1 action=start phase=mvp` | `/other/path/repo-1` (absolute, used as-is) |
| `/home/user/projects/` | `/sabs:build-loop action=start phase=mvp` | Error: "No AGENTS.md found, specify project=" |

**Error messages:**

| Scenario | Error message | What to do |
|---|---|---|
| In a directory without `AGENTS.md` and no `project=` | "No AGENTS.md found in current directory, specify project=" | Navigate to the project directory or add `project=<name>` |
| `project=` points to non-existent directory (non-init action) | "Project directory `<path>` does not exist" | Check the project name or run `action=init` first |
| `action=init` without `project=` | "project is required for init" | Add `project=<name>` to the init command |

---

## Prerequisites

Before using the build system, ensure you have:

1. **Claude Code** — All SABS skills are invoked with `/sabs:<skill-name>` (e.g., `/sabs:build-loop action=start phase=mvp`).
2. **GitHub CLI (`gh`)** — Required for repo creation, branch protection, PR operations. Install: `brew install gh` then `gh auth login`.
3. **Git** — Standard git CLI.

**How skills work:**
- **Plugin skills** (`/sabs:<name>`): Invoke directly in Claude Code. All skills ship with the plugin and are available immediately after installation.

**Required GitHub permissions:**
- `repo` scope for PR operations, branch protection, and status checks.
- Admin access to the repo for branch protection setup during `init`.
- If using a fine-grained token: `contents: write`, `pull_requests: write`, `administration: write`.

---

## Cost awareness

The build system's primary variable cost is LLM tokens. As a nonprofit steward, monitor these:

- **Per-phase token usage** is logged in the phase log (`docs/plan/log/<phase>.yaml`) at the end of each task entry.
- **Approximate ranges:** A 3-5 story phase typically uses 50K-200K tokens depending on codebase size and rework rate. Investigation-heavy phases run higher.
- **Circuit breaker:** The 5-consecutive-failure circuit breaker prevents runaway token burn on stuck problems.
- **Review your phase logs** after each phase. If token usage is higher than expected, consider: smaller phases, more specific done-when criteria, or pre-investigation before starting.
- **Budget decision:** After reviewing a phase's token usage, decide whether your token budget supports the next planned phase. The build system does not enforce budgets — you make this call.
- **Optional budget tracking:** Set `budget_tokens: <number>` in `progress.yaml` to enable budget monitoring. When cumulative token usage exceeds 80% of budget, `action=status` shows a warning. When it exceeds 100%, the build-loop pauses with a budget-exceeded message. You can `action=resume` to override and continue.

---

## Reference: Failure classes

The build-loop and phase-retro classify failures into these classes. You will encounter them in circuit breaker messages (Stage 2), phase retro analysis (Stage 4), and the LEARNINGS log.

| Class | Description |
|---|---|
| `spec-ambiguity` | Spec described what but not why |
| `spec-subjective` | Subjective or unverifiable done-when criteria |
| `edit-policy-drift` | AGENTS.md policy contradicts code |
| `schema-code-drift` | Schema files out of sync with validation |
| `silent-test-pass` | Tests pass without exercising the feature |
| `timezone-math` | Date/time boundary bugs |
| `missing-error-path` | No error-path test coverage |
| `exception-swallow` | Errors caught but not logged |
| `security-gap` | XSS, injection, CSRF, or similar |
| `data-loss` | Records lost, corrupted, or silently dropped |
| `cross-cutting-break` | Change broke an unrelated area |
| `phase-oversize` | >5 stories with cross-cutting dependencies |

New labels can be created as needed. Consistency across phases is what matters.

---

## Project bootstrap checklist

Before using the build system on a project, run `init` once. It handles everything — creating the directory, scaffolding AGENTS.md, GitHub repo creation, and branch protection.

### 1. Initialise the build loop

```bash
# In Claude Code:
/build-loop project=<project> action=init
```

The `init` action is the single entry point for all project infrastructure — whether the project is brand new, a legacy codebase, or a project that used an older version of the build system. It runs gates to converge the project to the current standard.

**For new projects:** `init` creates the project directory and prompts you for the project's purpose. It scaffolds a minimal `AGENTS.md` with starter quality checks:

```markdown
# <Project Name>

## Purpose
<Your answer>

## Quality checks

- no-silent-pass
- no-bare-except
- error-path-coverage
- agents-consistency
```

You can refine `AGENTS.md` later — add invariants, layer rules, tech stack details — as the project takes shape. The `## Quality checks` section is how the project opts in to automated quality gates. Add checks from the [reference below](#quality-checks-opt-in-reference) as needed.

**For existing projects:** `init` detects the current state and converges to the current standard (see state assessment below).

If no `.git` directory exists, `init` skips straight to Gate 1 — there's nothing to assess yet. The state assessment below only runs when a git repo already exists.

#### State assessment (existing repos only)

When a `.git` directory is present, `init` scans the project before touching anything and classifies it into one of three scenarios. It displays what it found and **asks you how to proceed** before making changes.

| Scenario | Detection signals | What init reports |
|---|---|---|
| **A — Current** | `docs/plan/progress.yaml` exists with current schema, `phase-retro-check.yml` exists, branch protection has the check | "Project is already initialised and up to date." Runs gates to confirm — idempotent, no changes made. |
| **B — Legacy build-loop** | Any of: `progress.md` instead of `progress.yaml`, `docs/plan/` exists but missing `log/` or `archive/`, old-format `phase-retro-check.yml`, scaffold partially present | Lists every divergence found. **Prompts you:** "Migrate to current standard? This will [specific changes]. Existing phase logs and progress data will be preserved." |
| **C — Existing repo, no build-loop** | `.git` exists, has commit history, but no `docs/plan/` directory and no build-loop scaffold | "This is an existing repo with no build-loop scaffold. Init will add build system files without modifying your existing code or history." **Prompts you** to confirm before proceeding. |

**Known legacy divergences** (Scenario B):

| Legacy pattern | Migration action |
|---|---|
| `progress.md` instead of `progress.yaml` | Converts content to YAML format, renames file, commits |
| Flat `docs/plan/` without `log/` or `archive/` subdirectories | Creates missing directories, moves existing log files into `log/` if found |
| Missing or outdated `phase-retro-check.yml` | Replaces with current template |
| Branch protection missing `Phase retro check` | Added by Gate 6 |
| No `## Quality checks` section in `AGENTS.md` | Prompts you to add the starter set |
| Retro files in old locations or formats | Moves to `docs/plan/archive/` with current naming convention |

If you decline migration, `init` aborts cleanly — nothing is changed.

#### Gates (run after assessment)

Once the scenario is identified and you've confirmed the path, `init` runs the following gates in order:

**Gate 1 — Git repository**

| Condition | Action |
|---|---|
| No `.git` directory | Runs `git init` |
| `.git` exists | Proceeds |

**Gate 2 — GitHub remote**

| Condition | Action |
|---|---|
| No `origin` remote | **Prompts you** for: GitHub account (personal or work — see [GitHub identity](#github-identity)), repo name, and visibility (private/public). Creates the repo via `gh repo create` and pushes the default branch. |
| `origin` exists but is not a GitHub URL | Aborts with an error — the build system requires GitHub for PRs and Actions. |
| `origin` points to GitHub | Proceeds |

**Gate 3 — `gh` authentication**

| Condition | Action |
|---|---|
| `gh auth status` fails | Aborts with instructions to run `gh auth login`. |
| Authenticated user does not have admin access to the repo | Aborts — admin access is required for branch protection setup. Displays the authenticated user and repo so you can fix the mismatch. |
| Authenticated with admin access | Proceeds |

**Gate 4 — Git identity**

| Condition | Action |
|---|---|
| Repo-level `user.name` and `user.email` are both set | Displays them for confirmation and proceeds. |
| Either is missing | **Prompts you** to choose which GitHub account to use (personal or work — see [GitHub identity](#github-identity)). Sets `git config user.name` and `git config user.email` at repo level (never `--global`). |

**Gate 5 — Default branch**

| Condition | Action |
|---|---|
| Default branch is `main` | Proceeds |
| Default branch is something else (e.g. `master`) | **Prompts you**: rename to `main`, or keep current name? If kept, the workflow template and branch protection target the actual default branch name instead of hardcoding `main`. |

**Gate 6 — Branch protection (Phase retro check)**

| Condition | Action |
|---|---|
| `Phase retro check` is not a required status check on the default branch | Creates the branch protection rule via `gh api`, requiring the `Phase retro check` status check to pass before merge. |
| Branch protection already includes the check | Proceeds |

**Gate 7 — Build scaffolding (idempotent)**

Scaffolds `docs/plan/progress.yaml`, `docs/plan/phase-goal.md`, `docs/plan/log/`, `docs/plan/archive/`, `docs/product/phases/`, `docs/concepts/`, `docs/briefs/`, and `.github/workflows/phase-retro-check.yml`. The `concepts/` and `briefs/` directories are part of the [idea pipeline](#idea-pipeline). The `docs/product/phases/` directory holds per-phase spec files — each phase gets its own file instead of growing the PRD. Detects your verify command (pytest, npm test, cargo test, etc.) and commits the scaffold.

| Condition | Action |
|---|---|
| Scaffold files do not exist | Creates them and commits |
| Some scaffold files already exist (Scenario B after migration, or partial previous init) | Skips existing files, creates only missing ones. Never overwrites `progress.yaml` or phase logs — these contain state from previous runs. |
| All scaffold files already exist (Scenario A) | Skips scaffolding entirely, reports "already initialised" |

**If any gate fails** (e.g., `gh` not authenticated, insufficient permissions, user declines a prompt), `init` stops with a clear error and instructions. Nothing is half-scaffolded — earlier gates must pass before later ones run.

**What `init` creates — the Phase retro check workflow:**

The `phase-retro-check.yml` workflow is a GitHub Actions status check that blocks merge until a phase retrospective has been completed.

<details>
<summary>Template: <code>.github/workflows/phase-retro-check.yml</code></summary>

```yaml
name: Phase retro check
on:
  pull_request:
    branches: [main]

jobs:
  retro-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check phase retro requirement
        run: |
          PROGRESS="docs/plan/progress.yaml"
          if [ ! -f "$PROGRESS" ]; then
            echo "No progress.yaml — skipping retro check"
            exit 0
          fi
          if grep -q 'phase_complete: true' "$PROGRESS"; then
            if grep -q 'retro_complete: true' "$PROGRESS"; then
              echo "Phase retro complete — check passed"
              exit 0
            else
              echo "::error::Phase is complete but no retrospective found."
              echo "Run /sabs:phase-retro and push to this branch."
              exit 1
            fi
          else
            echo "No completed phase — retro not required"
            exit 0
          fi
```

</details>

### 3. Write the first phase spec

Run the spec-author skill and describe your feature:

```bash
/sabs:spec-author project=<project>
```

Then describe your feature. The skill walks you through stories, done-when criteria, and writes to `docs/product/phases/<phase-name>.md` and `docs/product/PRD.md`.

### 4. Start building

```bash
# From workspace root:
/build-loop project=<project> action=start phase=<phase-name>

# Or from inside the project directory (project is inferred):
/build-loop action=start phase=<phase-name>
```

The agent takes over from here through Build, Review, and Compound.

---

## Stage 1: Spec (you drive)

**When:** Starting a new feature, capturing bugs, or amending shipped work.

**Where:** Claude Code, with the SABS plugin loaded.

**Pre-spec (optional):** If you have a rough idea that needs shaping, start with idea-shape (see [Idea pipeline](#idea-pipeline)). It produces a brief in `docs/briefs/` that spec-author can consume directly. If you already know the What/Why/Where/Constraints clearly, skip straight to spec-author.

**What you do:**

1. Describe the feature or bug (or provide a brief from `docs/briefs/`).
2. Review the stories the skill drafts. Each story has:
   - Acceptance criteria (testable)
   - User guidance (discovery path, key steps)
   - Design rationale (why this approach, not alternatives)
3. Review done-when criteria — these are the contract the build-loop verifies against. Every criterion must be mechanically verifiable (not "looks good" but "POST /api/x returns 201").
4. Approve the phase spec.

**What the agent does automatically:**

- Enforces the **phase size gate**: max 5 stories per phase. If you exceed 5, it asks you to split.
- Applies the **observability gate**: rejects subjective criteria, requires Playwright assertions for UI.
- Auto-adds **safety criteria**: error-path done-when for new endpoints, input validation for user-text fields.
- Writes the full phase spec to `docs/product/phases/<phase-name>.md` and adds a summary row to the PRD index table.
- Updates `docs/architecture/ARCHITECTURE.md`.

**Output:** A per-phase spec file (`docs/product/phases/<phase-name>.md`) with stories and done-when criteria, plus a PRD index entry. Ready for the build-loop.

**Learnings review (automatic):** After writing the draft, spec-author automatically runs phase-goal-review — checking the draft against the 10 built-in failure-pattern dimensions plus any project-local learnings in `docs/plan/LEARNINGS.md`. Gaps that can be resolved mechanically (missing done-when criteria, missing design rationale, missing consumer adaptation notes) are auto-fixed in the draft. Items requiring your judgment (phase split for oversize, design direction choice) are surfaced in the summary table. You can also run `/phase-goal-review` standalone at any time.

**Quick start alternative:** You can use the build-loop's `goal` parameter to provide phase goals directly: `/sabs:build-loop action=start phase=<name> goal="<description>"`. The agent writes observable done-when criteria from the goal text. This skips the interactive spec-author workflow but produces a valid phase specification.

**Next trigger:** You run `/sabs:build-loop action=start phase=<name>` in Claude Code (from the project directory, or with `project=<name>` from the workspace root).

---

## Stage 2: Build (agent drives, you monitor)

**When:** A phase is spec'd and approved.

**Where:** Claude Code.

**What you do:**

1. Start the phase: `/sabs:build-loop action=start phase=<name>`
   - The `start` action automatically checks out the default branch, pulls the latest from the remote, and creates a new `build/<phase-name>` branch. You do not need to manage branches manually between phases.
2. Monitor progress: `/sabs:build-loop action=status` — shows task progress, cumulative token usage for the current phase, and budget percentage if `budget_tokens` is configured in `progress.yaml`.

From the workspace root, add `project=<name>` to any command.

**What the agent does automatically:**

| Step | What happens | You invoke? |
|------|-------------|-------------|
| Investigate-first | For server/schema phases, queues an investigation before each implementation task | No — automatic for server/schema/cross-cutting phases |
| Implement | Writes code, one concern per task | No |
| Verify | Runs the project's test suite | No |
| Golden principles gate | Checks changes against AGENTS.md principles | No |
| Quality checks | Runs every check listed in `## Quality checks` of AGENTS.md | No — reads your AGENTS.md config |
| Story completion gate | Commits a milestone when all done-when criteria for a story are met | No |
| Phase completion gate | Done-when audit, AGENTS.md consistency, error-path spot check before marking phase done | No |

If any gate fails, the agent queues a fix task and loops.

**Gate glossary:**

| Gate | When it runs | What it checks |
|---|---|---|
| Golden Principles Gate | After each task's implementation | Changes comply with AGENTS.md principles |
| Quality Checks | After each task's tests pass | Every check listed in AGENTS.md `## Quality checks` |
| Story Completion Gate | After all done-when criteria for a story are verified | All criteria pass; commits a milestone marker |
| Phase Completion Gate | After all stories complete | Done-when audit, AGENTS.md consistency, error-path spot check |
| Phase Reconciliation Gate | After phase completion, before PR creation | Updates knowledge bases (AGENTS.md, architecture docs) to reflect phase changes. Archives completed phase specs: extracts inline PRD stories to per-phase files, updates PRD index. |

**Single-phase operation:** The build-loop operates one phase at a time. There is no continuous multi-phase mode. After a phase completes and is merged, start the next phase manually with `action=start phase=<next-phase>` — the agent handles branch creation automatically. Multi-phase queuing may be added in a future version.

**Branch convention:** Each phase runs on a `build/<phase-name>` branch. You do not manage branches manually — `start` handles everything. Here is the full flow from spec to build across a phase boundary:

| Step | Where | What happens | Branch state |
|------|-------|-------------|-------------|
| 1 | Claude Code | You run `/sabs:spec-author`. It writes the phase spec to `docs/product/phases/<name>.md`, updates the PRD index, and updates architecture docs. It does **not** commit. | Still on previous phase branch (e.g. `foundation`), with uncommitted spec files |
| 2 | Claude Code | You run `/sabs:build-loop action=start phase=<name>`. Pre-checks pass. | Same |
| 3 | (auto) | `start` sees uncommitted changes, confirms they are all under `docs/`, and stashes them. Working tree is now clean. | Clean working tree on old branch |
| 4 | (auto) | `start` checks the old branch has no unmerged commits (the PR was already merged), then checks out the default branch (`main`). | On `main` (local, possibly behind remote) |
| 5 | (auto) | `start` pulls the latest from the remote. Local `main` is now up to date with all merged work. | On `main`, up to date |
| 6 | (auto) | `start` creates `build/<phase-name>` from `main`. | On `build/<phase-name>`, branched from latest `main` |
| 7 | (auto) | `start` pops the stash. Your spec-author changes are restored as uncommitted files on the new branch. | Spec files restored on new branch |
| 8 | (auto) | `start` runs phase setup (archive previous log, reconciliation, write phase-goal, update progress.yaml), then commits everything — spec-author files and phase setup — in one commit: `chore: start <phase> phase`. | First commit on `build/<phase-name>` |
| 9 | (auto) | `start` enters the continuous iterate loop. Building begins autonomously. | Building on `build/<phase-name>` |

**Output:** A completed phase with all done-when criteria verified, on a build branch.

**Next trigger:** Automatic — the build-loop proceeds to the Review stage.

### State ownership in progress.yaml

Every field in `progress.yaml` has exactly one **owner** — the command responsible for writing it. Other commands may read any field but must never write fields they don't own. This prevents coupling and prepares for future decomposition.

| Owner | Fields | Writes when |
|-------|--------|-------------|
| **init** (build-loop-init) | `config.*` | Scaffolding — one-time creation |
| **orchestrator** (build-loop dispatcher) | `status` | pause, resume, skip, abort |
| | `next_task` | skip (clears stuck task) |
| | `consecutive_fails` | skip/resume (resets counter) |
| **iterator** (build-loop-iterate) | `phase`, `phase_complete` | start (sets), Branch B (marks complete), abort (clears) |
| | `task_number`, `next_task`, `last_result`, `consecutive_fails` | Branch A (after each task), Branch B (queues next) |
| | `review_stage`, `review_complete`, `pr_number` | Review scheduling and execution |
| | `completed_stories` | Story Completion Gate appends |
| | `status` | start (sets running) |
| **retro** (phase-retro) | `retro_complete` | After writing retrospective |

**Shared fields:** `status`, `next_task`, and `consecutive_fails` are written by both orchestrator and iterator. The concurrency lock (`.build-loop.lock`) prevents simultaneous access. The orchestrator writes these only during manual recovery actions (resume, skip), never during autonomous iteration.

---

## Stage 3: Review (agent drives, you approve at the end)

**When:** A phase passes its completion gate.

**Where:** Claude Code — the build-loop continues iterating through the review cycle automatically as part of the same continuous loop that built the phase.

**How it works:** After the phase completion gate passes, the build-loop's iterate loop keeps running. Branch B schedules review tasks, Branch A executes them — the same mechanism used for build tasks. The loop creates the PR, runs `review-pr`, then runs `handle-pr-review`, all without stopping. Guard rail 4 stops the loop when both `phase_complete` and `review_complete` are true.

**What the agent does automatically:**

| Step | What happens | `review_stage` |
|------|-------------|----------------|
| **Create PR** | Phase completion gate passes. Creates PR from build branch to main. Queues `[review] review-pr`. | `null` → `pr_created` |
| **Review** | Runs `review-pr` — reviews for correctness, security, design, and maintainability. Posts findings as inline PR comments (Critical, Concern, Nit). | `pr_created` → `review_posted` |
| **Fix** | Runs `handle-pr-review` — triages review findings (fix, challenge, skip). Applies fixes. Re-runs quality checks. Posts summary comment. Sets `review_complete: true`. Loop stops (guard rail 4). | `review_posted` → complete |

Both `review-pr` and `handle-pr-review` run with `auto=true`, which skips the operator confirmation gate. The agent proceeds directly to posting/fixing. The full triage is logged in the PR summary comment for your review.

The PR may also include **reconciliation commits** that update user-facing documentation (architecture docs, AGENTS.md) and archive the completed phase's spec. The Phase Reconciliation Gate extracts inline PRD stories to per-phase files (`docs/product/phases/`), updates the PRD index, and reconciles AGENTS.md and architecture docs. Review these doc changes alongside code changes — they should accurately describe the shipped behavior.

**What you do:**

1. **Review the PR.** The build-loop has built, self-reviewed, and self-fixed. You see the full audit trail: review comments, fix commits, quality check results, and the final summary. Exercise judgment on the end state.
2. **Approve and merge** — or request further changes. If you want additional review passes beyond the automated first pass, run `review-pr` or `handle-pr-review` manually.

**Why this matters:** Your first touchpoint after starting the build is a PR that has already been self-reviewed and self-fixed. You judge the final state.

**Compound engineering value:** Review comments are the richest source of learnings. Each Critical or Concern finding is a candidate for a new quality check, AGENTS.md rule, or spec-author gate. The Compound stage (next) captures these.

---

## Stage 4: Compound (you trigger, agent analyzes, you approve fixes)

**When:** Before merge — a required GitHub PR check blocks merge until the phase retrospective is complete.

**Where:** GitHub Actions (automatic check) + Claude Code (you run the retro).

**Prerequisite:** The `Phase retro check` workflow must exist in the repo **and** branch protection must require it as a status check. Both are set up automatically by `build-loop init` (see [bootstrap step 2](#2-initialise-the-build-loop)). If `init` was not run or failed partway, the compound stage has no enforcement and PRs can be merged without a retro.

**How to run:** `/sabs:phase-retro phase=<name>` in Claude Code (from the project directory, or with `project=<name>`).

**The flow:**

1. The build-loop completes a phase and creates a PR (Stage 3).
2. The `Phase retro check` GitHub Action detects `phase_complete: true` in `docs/plan/progress.yaml` but `retro_complete` is not `true`. **The check fails — merge is blocked.**
3. You run `/sabs:phase-retro`. The agent reads the phase log **and the PR's review threads**, then:
   - Counts build metrics: total tasks, investigate tasks, fail tasks, rework tasks.
   - **Extracts review patterns** — classifies each Critical/Concern PR review finding into a failure class (e.g., `missing-error-path`, `security-gap`). Multiple comments with the same root cause collapse into one pattern with a count.
   - Classifies build-log failures by class (e.g., `spec-ambiguity`, `schema-code-drift`).
   - Applies the **twice-seen rule across both sources:**
     - **First occurrence:** Logged. No action.
     - **Second occurrence (same class, from any source):** Pattern confirmed. Proposes exactly one fix at the earliest prevention point.
     - **Exception — data-loss or security:** Compounds immediately on first occurrence.
   - Proposes fixes targeting one of four prevention points (in priority order):

| Prevention point | Priority | When it fires |
|---|---|---|
| Spec-author gate | Highest | Spec writing |
| AGENTS.md rule | High | Build time |
| Quality check | Medium | After tests pass |
| Phase completion gate | Lowest | Before phase done |

4. You review proposed compounding fixes. Approve or reject each one. If you reject a proposed fix, it is logged in the retro archive with status `rejected` and your reason. The agent will not re-propose the same fix unless the same failure class is seen again in a future phase retro. Rejection does not reset the twice-seen counter — the prior occurrence is preserved.
5. The retro is written to `docs/plan/archive/<phase>.retro.md`, `retro_complete: true` is set in `progress.yaml`, and approved fixes are committed to the PR branch.
6. The PR check re-runs — `retro_complete: true` found — **check passes, merge is unblocked.**
7. You approve and merge.

**Compounding fixes that target plugin skill files** (`${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md`) live outside the project repo. These are committed separately in the plugin workspace using the following procedure:

```bash
cd <plugin-root>
git add skills/<skill-name>/SKILL.md
git commit -m "compound: <description>"
git push
```

These plugin commits are not part of the project PR and are not gated by branch protection.

**New learnings** are written to the project-local `docs/plan/LEARNINGS.md` (within the project directory). This file is created on first write if it doesn't exist. Project-local learnings are committed as part of the project's PR, not as separate workspace commits.

### Failure class taxonomy

See [Reference: Failure classes](#reference-failure-classes) for the full taxonomy of failure classes used by the phase-retro.

### How the twice-seen rule works

**First occurrence (Project-A, phase 3):** Phase retro finds `spec-subjective` — done-when criteria like "page feels alive" caused rework. Logged as first-seen. No action.

**Second occurrence (Project-A, phase 5):** Phase retro finds `spec-subjective` again — "responsive UI" criterion couldn't be verified. Pattern confirmed. Fix proposed: add observability gate to spec-author that rejects subjective criteria and requires measurable proxies.

**Exception:** `data-loss` and `security-gap` compound on first occurrence — the cost of waiting for a second occurrence is too high.

**Output:** Improved skills and rules that prevent the same class of failure in future phases.

---

## Mid-phase spec correction

If you realize a done-when criterion or story is wrong after the build-loop has started, you have two options depending on how wrong the spec is.

**Option A — Abort and re-spec** (more than 2 criteria wrong, or fundamental direction change):

1. Run `/sabs:build-loop action=abort` to stop the current phase.
2. Amend the phase spec in `docs/product/PRD.md` using spec-author.
3. Run `/sabs:build-loop action=start phase=<name>` with the corrected spec. The build-loop starts fresh with the updated criteria.

**Option B — Pause, amend in place, resume** (1-2 criteria need adjustment, no dependent tasks completed):

1. Wait for the current task to finish (or let the circuit breaker pause the loop).
2. Edit the criterion directly in `docs/product/PRD.md`.
3. Run `/sabs:build-loop action=resume`. The build-loop re-reads the PRD on resume and picks up the amended criteria.

**Which to choose:**

| Situation | Recommended path |
|---|---|
| >2 criteria wrong | Abort and re-spec |
| Fundamental approach change | Abort and re-spec |
| 1 criterion wrong, no dependent tasks done | Amend in place |
| Typo or minor wording fix in a criterion | Amend in place |

**Example:** You spec'd "POST /api/items returns 201" but realize the endpoint should be PUT, not POST. If the build-loop hasn't implemented the endpoint yet, amend in place. If it has already built and tested the POST endpoint, abort and re-spec to avoid compounding wrong work.

---

## Handling bugs

When you find bugs in shipped work:

1. **Spec:** Use spec-author to capture the bug as an amendment or new story.
2. **Build:** Run the build-loop on the fix phase.
3. **Review:** The autonomous review cycle runs on the fix PR.
4. **Compound:** The phase-retro (run before merge) classifies the bug and checks for patterns. If the same failure class appeared before, a compounding fix is proposed.

---

## Failure recovery

**Circuit breaker (automatic).** If the build-loop hits 5 consecutive failures, it pauses automatically and reports the last 5 failure summaries grouped by type (see [Reference: Failure classes](#reference-failure-classes)). This prevents token burn on problems the agent cannot self-fix. You can resume after investigating, skip the stuck task, or abort the phase. Starting a new phase (via `action=start`) resets the consecutive-fail counter to zero automatically.

### Skip — when and how

Run `/sabs:build-loop action=skip` to bypass the current task and have the agent re-investigate for a different path forward.

**When to skip:** The task has hit the circuit breaker and the root cause is unclear, or the task is blocked by an external dependency you cannot resolve immediately.

**What happens:**
- The current task is marked `skipped` in the phase log.
- Any partial work (uncommitted changes) is stashed via `git stash`. The stash reference is logged in the phase log. You can recover with `git stash pop` if needed.
- The consecutive failure counter resets to zero.
- The agent re-investigates and plans a new task to make progress on the phase.

**Story completion interaction:** Skipped tasks do not satisfy done-when criteria. If all tasks for a story are complete except a skipped one, the story completion gate will not fire. You may need to: (a) resume the skipped task later by letting the agent re-plan it, (b) amend the spec to remove the criterion (see [Mid-phase spec correction](#mid-phase-spec-correction)), or (c) abort the phase if the skipped work is essential.

### Debugging playbook — when the circuit breaker fires

1. Read the failure summaries in the pause message.
2. Check the failure pattern:
   - **All failures are the same quality check** (e.g., `no-bare-except`): consider suppressing the check if it's a false positive (see [Suppressing quality checks](#suppressing-quality-checks) below).
   - **All failures are verify failures**: check for environmental issues (missing dependencies, broken test fixtures).
   - **Mixed failures**: the task may be too broad — use `action=skip` and let the agent re-investigate with a narrower approach.
3. After fixing the underlying issue, `action=resume`. Or `action=skip` to try a different task. Or `action=abort` if the phase is misconceived.

### Suppressing quality checks

If a quality check is producing false positives, you can suppress it for the current phase by adding a `quality_check_suppressions` list to `progress.yaml`:

```yaml
quality_check_suppressions:
  - no-bare-except  # false positive on legacy wrapper pattern
```

Suppressed checks are skipped during the build-loop's quality check step. **When to suppress vs. fix:** Suppress only for confirmed false positives. If the check is catching a real issue, fix the code instead. Suppressions are phase-scoped — they persist in `progress.yaml` for the current phase. Remove them when the false positive is resolved or the phase ends.

**Abort a phase.** Run `/sabs:build-loop action=abort` to abandon a phase that is fundamentally stuck or misconceived. Abort preserves all PRD and spec content — stories remain in `docs/product/PRD.md` unchanged. The partial task log is archived for retro analysis. The build branch is not reverted; you decide whether to cherry-pick, revert, or start fresh.

### Session recovery

If a Claude Code session dies mid-phase, the build branch has all committed work. The build-loop creates a `.build-lock` file in the project root while running. If a session crashes, this file persists.

**Recovery checklist:**

1. Check for uncommitted changes: run `git status` in the project directory.
2. Check whether you did any manual work between the crash and recovery.
3. Delete `.build-lock` if no Claude Code session is currently active for this project.
4. Run `/sabs:build-loop action=status` to see current state.
5. If state looks consistent, run `action=resume` to continue from where the agent left off.
6. If state looks inconsistent (e.g., partial commit, missing files, conflicting manual changes), consider `action=abort` and starting the phase fresh.

The structured state in `progress.yaml` gives the new session everything it needs. Manual changes made between crash and recovery are not tracked by the build-loop — review them before resuming.

### Troubleshooting: Phase retro check Action failures

If the `Phase retro check` GitHub Action fails for reasons other than a missing retro:

| Cause | Symptoms | Recovery |
|---|---|---|
| YAML parse error in `progress.yaml` | Action log shows parse error | Fix the YAML syntax in `progress.yaml`, commit, and push to re-trigger |
| Runner unavailable | Action queued but never starts | Wait and re-trigger, or manually re-run from the GitHub Actions tab |
| Networking timeout | Action fails with connection error | Re-run the workflow from the GitHub Actions tab |
| Workflow file syntax error | Action fails immediately | Fix `.github/workflows/phase-retro-check.yml` and push |

To re-run: go to the repo's Actions tab on GitHub, find the failed run, and click "Re-run failed jobs".

**Key guarantee:** Spec and PRD work is never lost. It lives in `docs/product/` (PRD index + per-phase spec files) independent of the build branch. A failed or aborted phase does not discard your specifications.

---

## Rollback playbook

If a merged phase introduced a bug or regression discovered post-merge:

1. **Identify the problem phase's PR number** — check the merge history on the default branch.
2. **Revert the PR:** `gh pr revert <number>` creates a revert PR automatically.
3. **Review and merge the revert PR** — this undoes the phase's code changes.
4. **If a fix is needed** (not just revert): create a new scoped fix phase via spec-author, then run the build-loop on it. This "roll forward" approach is preferred over manual patching.

**Note:** Rollback does not undo compounding fixes applied to workspace-level files (skills, rules, learnings). Review those separately and revert manually if needed.

---

## Scope guidance

Not every change needs the full four-stage workflow.

| Change type | Recommended approach |
|---|---|
| Multi-story feature | Full workflow: spec, build, review, compound |
| Single-story fix or enhancement | Start build-loop with a `goal` parameter — skip formal spec if done-when criteria are obvious |
| Bug fix with clear reproduction | Capture as amendment via spec-author (for traceability), then build-loop |
| Configuration, dependency updates, CI | Direct commit — the build-loop's task-by-task tracking adds no value here |
| Documentation-only changes | Direct commit. Run verify-gate standalone if docs reference code |

---

## When to escalate

If you start a direct commit or small fix and discover it's larger than expected:

1. Commit what you have (even if partial).
2. Use spec-author to capture the remaining work as stories.
3. Start a build-loop phase for the remaining work.
4. The partial commit becomes context the build-loop can reference.

---

## Quality checks opt-in reference

These checks supplement your project's linter and test suite — they catch patterns that standard AST-based tools miss. The project's `verify` command should already run real linters (ruff, eslint, etc.). These are heuristic and may produce false positives.

Add any of these to your project's `AGENTS.md` under `## Quality checks`:

| Check | What it catches | Add this line |
|---|---|---|
| `no-silent-pass` | Tests that pass without exercising any assertion (early returns, conditional asserts) | `- no-silent-pass` |
| `no-bare-except` | Exception swallowing without logging (`except Exception: continue`) | `- no-bare-except` |
| `no-innerhtml-user-data` | XSS via innerHTML with user-controlled data, Jinja vars in JS without `\|tojson` | `- no-innerhtml-user-data` |
| `no-raw-sql` | SQL injection via string interpolation in queries | `- no-raw-sql` |
| `contract-validation` | Schema files not loaded by validation code, phantom file references | `- contract-validation` |
| `agents-consistency` | AGENTS.md rules that contradict actual code behavior | `- agents-consistency` |
| `function-length(N)` | Functions exceeding N lines (default 50) | `- function-length(50)` |
| `error-path-coverage` | API endpoints with no error-path tests (400, 404, 403) | `- error-path-coverage` |
| `fetch-status-check` | JS/TS fetch calls that parse response without checking `response.ok` | `- fetch-status-check` |
| `no-secrets-in-commit` | Scans tracked files for accidentally committed secrets or credentials (file name patterns and content patterns). Hard blocker — pauses build-loop, requires operator intervention. | `- no-secrets-in-commit` |
| `root-agents-immutable` | Verifies root workspace AGENTS.md has not been modified by comparing SHA-256 hash against known-good reference in `.docs/build-system/.agents-hash`. Non-optional — always runs for every project. | `- root-agents-immutable` |

**Recommended starter set** (paste into AGENTS.md):

```markdown
## Quality checks

- no-silent-pass
- no-bare-except
- error-path-coverage
- agents-consistency
```

**Full set** (for mature projects):

```markdown
## Quality checks

- no-silent-pass
- no-bare-except
- no-innerhtml-user-data
- no-raw-sql
- contract-validation
- agents-consistency
- function-length(50)
- error-path-coverage
- fetch-status-check
```

---

## GitHub identity

Operators with multiple GitHub accounts (e.g. personal + work) must ensure agents use the correct identity when committing, creating repos, or interacting with GitHub on a project.

| | Personal | Work |
|---|---|---|
| **GitHub username** | `<personal-handle>` | `<work-handle>` |
| **Git name** | `<personal-name>` | `<work-name>` |
| **Git email** | `<personal-handle>@users.noreply.github.com` | `<you>@<work-domain>` |
| **Use for** | Personal projects, side projects, open source | Work / employer projects |

**How to apply:** Set the identity per-repo using `git config user.name` and `git config user.email` (no `--global`). The `build-loop init` flow prompts for which account to use and sets the local git config accordingly.

**No defaults.** Work and personal projects often overlap. Always check the existing repo-level git config. If not set, ask the operator — never assume.

The `gh-identity-guard` hook (see [README.md](../README.md#identity-guard)) automates the check by warning when the local git identity doesn't match the expected one for the current remote.

---

## Multi-operator onboarding

> **Deferred.** The build system currently supports a single operator. Multi-operator support requires decisions on workspace auth strategy, shared vs. isolated progress state, and concurrent phase execution. This will be addressed in a future manual version.

---

## Skill reference

All skills ship with the SABS plugin. Invoke with `/sabs:<name>`:

| Skill | Invocation | Description |
|---|---|---|
| build-loop | `/sabs:build-loop action=<action>` | Router/dispatcher for the build cycle |
| build-loop-init | `/sabs:build-loop-init` | Project initialization (9 gates) |
| build-loop-iterate | `/sabs:build-loop-iterate` | Core iteration loop (Branch A/B) |
| spec-author | `/sabs:spec-author` | Phase specification authoring |
| verify-gate | `/sabs:verify-gate` | Quality gate (static analysis, security, consistency) |
| test-gate | `/sabs:test-gate` | Full verification stack |
| regression-detect | `/sabs:regression-detect` | Before/after test regression detection |
| phase-retro | `/sabs:phase-retro phase=<name>` | Phase retrospective and compounding |
| phase-goal-review | `/sabs:phase-goal-review` | Phase goal review against learnings |
| review-pr | `/sabs:review-pr pr=<number>` | PR review for correctness, security, design |
| handle-pr-review | `/sabs:handle-pr-review pr=<number>` | PR review comment triage and fixes |
| frontend-design | `/sabs:frontend-design` | UI design guidance (referenced by build-loop) |
| orchestrate | `/sabs:orchestrate` | Multi-brief autonomous chaining |

---

## What's automatic vs what you decide

| Decision | Who | Notes |
|---|---|---|
| GitHub repo creation | Agent (prompts you) | `init` creates the repo via `gh` if none exists; you supply account, name, visibility |
| Branch protection setup | Agent | `init` adds the required status check automatically via `gh api` |
| Feature definition, stories, scope | You | Via spec-author |
| Phase size (max 5 stories) | Enforced | Spec-author and build-loop both refuse >5 |
| Done-when criteria quality | Enforced | Observability gate rejects subjective criteria |
| Task ordering and investigation | Agent | Build-loop plans and sequences tasks |
| Which quality checks run | You | Configured in AGENTS.md `## Quality checks` |
| Quality check execution | Agent | Automatic after each task's tests pass |
| Phase retro check workflow | Agent | Scaffolded by `build-loop init` |
| PR creation and self-review | Agent | Automatic after phase completion |
| Review fix application | Agent | Automatic; re-checked for regressions |
| PR approval and merge | You | Final human judgment on shipped code |
| Phase retro execution | You | Required PR check blocks merge until you run `/sabs:phase-retro` |
| Compounding fix proposals | Agent | Produced during retro analysis |
| Compounding fix approval | You | Fixes are never applied without your consent |

---

## Skill compatibility

This manual version is compatible with:

| Skill / Command | Minimum version |
|---|---|
| spec-author | >= 4 |
| build-loop | >= 9 |
| verify-gate | >= 2 |
| phase-retro | >= 3 |
| review-pr | >= 3 |
| handle-pr-review | >= 3 |

When updating a skill, bump its version in the YAML frontmatter. When updating this manual, verify compatibility with current skill versions.

---

## Living document

This manual is a living document. When the build system's skills or workflow change, update this manual to match. When a compounding fix changes a skill's behavior, note it here if it affects the operator workflow.

Each project that uses SABS maintains its own learnings at `docs/plan/LEARNINGS.md` within the project root, written by `phase-retro` when failure patterns confirm twice-seen.

---

## Quick reference

| Action | Command |
|---|---|
| Init a project | `/sabs:build-loop project=<path> action=init` |
| Spec a phase | `/sabs:spec-author project=<path>` |
| Review phase goal | `/sabs:phase-goal-review project=<path>` |
| Start building | `/sabs:build-loop action=start phase=<name>` |
| Check progress | `/sabs:build-loop action=status` |
| Resume after pause | `/sabs:build-loop action=resume` |
| Skip a stuck task | `/sabs:build-loop action=skip` |
| Abort a phase | `/sabs:build-loop action=abort` |
| Run quality checks | `/sabs:verify-gate` |
| Run phase retro | `/sabs:phase-retro phase=<name>` |
| Review a PR | `/sabs:review-pr pr=<number>` |
| Handle review feedback | `/sabs:handle-pr-review pr=<number>` |
| Chain multiple briefs | `/sabs:orchestrate project=<path> briefs=all` |

**Recovery:**
- Circuit breaker fired -> read failure summaries, fix the issue or `action=skip`
- Session crashed -> `action=status` then `action=resume`
- Phase stuck -> `action=abort` (preserves PRD and spec)
