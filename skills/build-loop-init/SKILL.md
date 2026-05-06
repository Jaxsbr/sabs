---
name: build-loop-init
description: "Scaffolds build-loop infrastructure in a project — runs convergence gates for new, legacy, or existing repos"
allowed-tools: "Bash(git *) Bash(gh *) Bash(npm *) Bash(npx *) Bash(make *) Bash(cargo *) Bash(python *) Bash(date *) Bash(mkdir *) Bash(cat *) Bash(echo *) Bash(grep *) Bash(yamllint *) Read(*) Write(*) Edit(*) Grep(*) Glob(*)"
disable-model-invocation: true
---

<!-- version: 12 -->
<!-- Sub-skill of build-loop. Read the router skill first for shared sections: parameters, scope restriction, concurrency guard, resolve project root, phase spec format. -->
<!-- Router: ${CLAUDE_PLUGIN_ROOT}/skills/build-loop/SKILL.md -->

## Action: `init`

Scaffolds build-loop infrastructure in a project. Runs gates to converge the project to the current standard — whether brand new, legacy, or an existing repo without build-loop.

**IMPORTANT: `init` is the entry point for NEW projects.** If the project directory does not exist, `init` creates it after confirming the path with the operator (see "Resolve project root" step 4 in the router skill). The operator can confirm the default path or provide an alternative. If `AGENTS.md` does not exist, `init` scaffolds it (see pre-check below).

**Pre-check — `AGENTS.md`:** Verify `AGENTS.md` exists at `PROJECT_ROOT`. If not:
1. Prompt the operator: "No AGENTS.md found. What is this project's purpose? (1-2 sentences)"
2. Create `AGENTS.md` using the minimal template below, inserting the operator's answer.
3. Report: "Created AGENTS.md with starter quality checks. You can refine it later."

Minimal `AGENTS.md` template for new projects:

```markdown
# <Project Name (inferred from directory)>

## Purpose
<Operator's answer>

## Quality checks

- no-silent-pass
- no-bare-except
- error-path-coverage
- agents-consistency
```

### State assessment (existing repos)

If `.git` exists, scan and classify before touching anything:

| Scenario | Detection signals | Action |
|---|---|---|
| **A — Current** | `docs/plan/progress.yaml` exists with current schema | Idempotent — verify gates, no changes needed. |
| **B — Legacy** | `progress.md` instead of `progress.yaml`, missing `log/` or `archive/` subdirs, old workflow template | List divergences. Prompt operator: "Migrate to current standard?" If declined, abort cleanly. |
| **C — Existing repo, no build-loop** | `.git` exists with history, but no `docs/plan/` | Report what will be added. Prompt operator to confirm before proceeding. |

If no `.git` -> skip assessment, proceed to Gate 1.

**Edge case:** `.git` exists but no commits (unborn HEAD) -> treat as fresh repo, make an initial commit first.

**Legacy migration (Scenario B):**

| Legacy pattern | Migration action |
|---|---|
| `progress.md` instead of `progress.yaml` | Convert content to YAML format, rename file, commit |
| Flat `docs/plan/` without `log/` or `archive/` | Create missing directories, move existing log files into `log/` |
| Missing or outdated `phase-retro-check.yml` | Replace with current template |
| No `## Quality checks` in `AGENTS.md` | Prompt operator to add the starter set |
| Retro files in old locations | Move to `docs/plan/archive/` with current naming |

### Gate 1 — Git repository

If no `.git` directory, run `git init`. Otherwise proceed.

### Gate 2 — GitHub remote

- If no `origin` remote: prompt operator for GitHub account (personal/work), repo name, visibility. Create via `gh repo create` and push default branch.
  - **Public repo data safety check:** Before creating a public repo, scan `AGENTS.md` for keywords indicating personal or sensitive data (`personal`, `people`, `PII`, `sensitive`, `private`, `names`, `confidential`, `person notes`, `daily logs`). If found, warn: "This repo will be PUBLIC. AGENTS.md mentions personal/sensitive data. Confirm you want public visibility, or switch to private (note: phase retro enforcement will be advisory only on private repos without GitHub Pro)." Wait for operator confirmation before proceeding.
- If `origin` exists but is not a GitHub URL: abort — the build system requires GitHub for PRs and Actions.
- If `origin` points to GitHub: proceed.

### Gate 3 — `gh` authentication and permissions

- Run `gh auth status`. If it fails, abort with instructions to run `gh auth login`.
- Check admin access to the repo. If missing, abort — admin access is required for branch protection setup.
- Validate token scopes: run `gh auth status` and inspect the reported scopes. Required scopes: `repo` (full repo access for PRs, branch protection), `workflow` (GitHub Actions management), `actions:read` (workflow run status visibility). If any required scope is missing, report which scopes are missing and abort with: "Re-authenticate with: `gh auth login --scopes repo,workflow,actions:read`".

### Gate 4 — Git identity

- Check repo-level `user.name` and `user.email`. If both set, display for confirmation.
- If either is missing, prompt operator to choose which GitHub account to use. Set per-repo (never `--global`).

### Gate 5 — Default branch

- If default branch is `main`, proceed.
- If different (e.g. `master`), prompt operator: rename to `main`, or keep? If kept, adapt workflow template and branch protection target accordingly.

### Gate 6 — Branch protection

- Check repo visibility: run `gh repo view --json visibility -q .visibility`.
- **If private:** Required status checks need GitHub Pro (or Team/Enterprise). Check if branch protection creation succeeds. If the API returns a 403 or "upgrade your plan" error, warn: "Branch protection status checks require GitHub Pro for private repos. Phase retro enforcement will be advisory — run phase-retro manually before merging." Skip branch protection setup and proceed. Do not abort.
- **If public (or paid plan):** Check if `retro-gate` is a required status check on the default branch. If not, create the branch protection rule via `gh api` using context `retro-gate` (the job `id` from the workflow YAML — this is the actual check name the GitHub Checks API reports; the UI decorates it as `<workflow-name> / <job-id> (<event>)` but the API context is just the job id). If already present, proceed.

### Gate 7 — Build scaffolding (idempotent)

0. Verify `.gitignore` exists. If not, create a minimal one. If it exists, check it includes common secret patterns (`.env`, `.env.*`, `*.key`, `*.pem`, `credentials.json`, `.build-loop.lock`). Add any missing patterns.
1. Detect the verify command by checking in order:
   - If `package.json` exists:
     - Base: `npm run lint && npm run test`
     - If `tsconfig.json` also exists -> prepend `npx tsc --noEmit &&` (TypeScript projects must prove compilation; linters and test runners do not enforce type safety)
   - If `Makefile` exists -> `make lint test`
   - If `Cargo.toml` exists -> `cargo clippy && cargo test`
   - If `pyproject.toml` or `setup.py` exists:
     - Base: `python -m pytest`
     - If `mypy.ini`, `.mypy.ini`, `setup.cfg` with `[mypy]`, or `pyproject.toml` with `[tool.mypy]` exists -> prepend `mypy . &&` (typed Python projects must prove type correctness)
   - Otherwise -> `echo "no verify command configured"`
2. Extract golden principles from `AGENTS.md`. Look for sections titled "Golden principles", "Invariants", "Non-negotiable invariants", or similar.
3. Create directories: `docs/plan/`, `docs/plan/log/`, `docs/plan/archive/`, `docs/product/phases/`, `docs/concepts/`, `docs/briefs/`. The `concepts/` and `briefs/` directories are part of the idea pipeline (see `${CLAUDE_PLUGIN_ROOT}/docs/MANUAL.md` "Idea pipeline"): concepts hold rough future-phase ideas, briefs hold fully shaped ideas ready for spec-author. The `docs/product/phases/` directory holds per-phase spec files — each phase gets its own file instead of being inlined in the PRD.
4. Write `docs/plan/progress.yaml` using the template from the state-machine reference (`${CLAUDE_PLUGIN_ROOT}/skills/build-loop-iterate/state-machine.md`) (skip if it already exists — never overwrite progress state).
5. Write `docs/plan/phase-goal.md` with placeholder content: `No phase started. Run /sabs:build-loop project=<project> action=start phase=<phase> to begin.` (skip if it already exists).
6. Create `.github/workflows/` directory if it doesn't exist.
7. Write `.github/workflows/phase-retro-check.yml` using the workflow template below (replace if outdated).
8. Create `.github/` directory if it doesn't exist. Write `.github/pull_request_template.md` using the PR template below (skip if it already exists). This provides a manual retro checklist that works on all repos regardless of GitHub plan.

### Gate 8 — Skill version compatibility

Read the version frontmatter (`<!-- version: N -->`) from each companion skill. Compare against the minimum required versions listed below. If any skill is below its minimum, warn with the specific skill name, current version, required version, and upgrade instructions. Do not abort — version mismatches are warnings, not blockers.

| Skill/Command | Minimum version |
|---|---|
| build-loop (router) | 12 |
| verify-gate | 3 |
| phase-retro | 3 |
| review-pr | 3 |
| handle-pr-review | 3 |
| spec-author | 4 |

### Gate 9 — Command shadow check

Check whether any plugin skill has a shadowing personal skill at `~/.claude/skills/` or legacy command at `~/.claude/commands/`. For each match, **warn loudly**: "SHADOWED: `~/.claude/skills/<name>/SKILL.md` (or `~/.claude/commands/<name>.md`) exists and may override the plugin version. Delete the personal copy to ensure the plugin version is used." List all shadowed files. Do not abort — this is a warning, not a blocker.

8. **README build-loop insert (idempotent):**
   - If `README.md` does not exist at `PROJECT_ROOT`, create it with a heading derived from the directory name and the build-loop section (see template below).
   - If `README.md` exists but does not contain the marker `<!-- build-loop -->`, append the build-loop section to the end of the file.
   - If the marker already exists, do nothing (idempotent).
   - Read the version from `<!-- version: N -->` in the router skill SKILL.md to populate the version number.

   Build-loop README section template:

   ```markdown

   <!-- build-loop -->
   ---
   *Built with [build-loop](docs/plan/) — init v<VERSION>*
   ```

9. Commit: `chore: scaffold build loop files`
10. Report initialised and next step. The next step is ALWAYS `spec-author`, not `build-loop start`. Output: "Build loop initialised. Next: run spec-author to define your phases and specs. Spec-author will give you the exact `/sabs:build-loop start` command when specs are ready." Include any version warnings from Gate 8 and any shadow warnings from Gate 9.

**Failure mode:** If any gate fails, stop cleanly. Earlier gates must pass before later ones run. Nothing half-scaffolded.

### Phase retro check workflow template

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

### PR template

```markdown
## Summary

<!-- Brief description of what this phase delivers -->

## Stories shipped

<!-- List completed user stories -->

## Pre-merge checklist

- [ ] Phase retro completed (`/sabs:phase-retro`)
- [ ] Quality checks pass
- [ ] Done-when evidence reviewed
```
