---
name: phase-retro
description: "Phase retrospective — analyzes completed phase log and PR review findings, classifies failures, applies twice-seen rule, proposes compounding fixes"
allowed-tools: "Bash(git *) Bash(gh *) Bash(date *) Bash(shasum *) Read(*) Write(*) Edit(*) Grep(*) Glob(*)"
---

<!-- version: 4 -->
Run an automated phase retrospective — analyzes a completed phase log and PR review findings, classifies failures, applies the twice-seen rule, and proposes compounding fixes.

## Parameters

- `project` — path to the project root (absolute, or relative to cwd). If omitted, inferred from cwd — cwd must contain a project-level `AGENTS.md`, not the workspace root; error with "specify project=" if not.
- `phase` — phase name to analyze (optional; defaults to most recently archived phase)

## How it works

1. Resolve the project root (same logic as build-loop).
2. Read `docs/plan/progress.yaml`, the target phase log (check `docs/plan/log/<phase>.yaml` first; if not found, fall back to `docs/plan/archive/<phase>.yaml`; if neither exists, report error), list `docs/plan/archive/*.retro.md` (previous retros), the phase spec (check `docs/product/phases/<phase>.md` first, fall back to `docs/product/PRD.md` section), and `AGENTS.md`.
3. Identify the target phase. If not specified, use the most recently archived phase (latest `.yaml` in `archive/`).
4. Check whether a PR exists for the phase branch. If so, fetch its review threads (Step 1.5). If no PR exists, skip Step 1.5 — the retro works on build-log data only.
5. Run the analysis steps below.
6. Write the retrospective and present compounding fixes for approval.

## Analysis steps

### Step 1 — Extract phase metrics

From the phase's log entries (found in Step 2 — either `log/<phase>.yaml` or `archive/<phase>.yaml`), count:
- Total tasks, investigate tasks, implement tasks, fail tasks, rework tasks
- Investigate ratio (investigate / total) and rework rate (rework / total)

Health thresholds:
- **Healthy:** <10% rework, >40% investigate ratio (server phases)
- **Warning:** 10-20% rework or <40% investigate ratio
- **Unhealthy:** >20% rework

### Step 1.5 — Extract review patterns

**Skip if no PR exists for the phase.**

Fetch all review threads from the phase's PR using GraphQL (same query as `/sabs:handle-pr-review`). Filter to threads where the root comment starts with `**Critical:**` or `**Concern:**`. Classify each into a failure class from the taxonomy (see `${CLAUDE_PLUGIN_ROOT}/skills/phase-retro/failure-classes.md`). Deduplicate — multiple comments with the same class collapse into one entry with a count and one representative example.

Output: review-sourced failure classes with `source: "pr-review"`, feeding into Step 2.

### Step 2 — Classify failures

Merge two input streams into a single list of failure classes:

- **Build-log failures:** Assign each fail/rework entry a failure class (source: `build-log`).
- **Review-sourced failures:** Carry forward entries from Step 1.5 (source: `pr-review`).

See `${CLAUDE_PLUGIN_ROOT}/skills/phase-retro/failure-classes.md` for the full failure class taxonomy.

### Step 3 — Apply the twice-seen rule

For each failure class in the combined list, search all previous phase retrospectives in `docs/plan/archive/*.retro.md` for the same failure class. The twice-seen rule applies **across sources** — a class first-seen in a build log and seen again from a PR review still triggers compounding.

- **First occurrence:** Log as "first-seen". No compounding action.
- **Second occurrence (same class):** Pattern confirmed. Produce ONE compounding fix.
- **Exception — data-loss or security:** Compound immediately on first occurrence.

### Step 3.5 — Classify scope for new learnings

When a compounding fix will add a new entry to the project's `docs/plan/LEARNINGS.md` (the project-local learnings file), determine its **scope**:

- **`universal`** — the failure pattern applies regardless of project type (spec ambiguity, phase sizing, workflow handoff, commit hygiene, etc.). This is the default.
- **Domain tag** (e.g., `phaser-game`, `web-app`) — the failure is specific to a framework or project type. Use a domain tag when the learning references framework-specific APIs, rendering models, or architectural patterns that have no equivalent in other project types.

Read the project's `AGENTS.md` for a `## Project type` declaration. If present, use that tag for domain-scoped learnings. If absent, use `universal`.

Add `**Scope:** <tag>` to the learning entry after `**Prevention point:**`. Omit the field (defaults to `universal`) for entries that clearly apply everywhere.

**Learnings file location:** New learnings are written to the **project-local** `docs/plan/LEARNINGS.md` (within the project root). If this file does not exist, create it with the standard header (see template below). The plugin does not ship a baseline learnings file — each project accumulates its own.

**Project-local LEARNINGS.md template (first-run creation):**

```markdown
# Compound Engineering — Project Learnings

> Project-specific learnings from using the semi-autonomous build system.
> Each entry records a failure, its class, what was done about it, and where prevention was added.
>
> **Scope filtering:** Each entry has a `Scope` field — either `universal` (applies to all project types) or a domain tag (e.g., `phaser-game`). Entries without an explicit `Scope` field are `universal` by default.

---
```

### Step 4 — Propose compounding fixes

For each pattern, propose exactly one fix at the **earliest prevention point** (see `${CLAUDE_PLUGIN_ROOT}/skills/phase-retro/failure-classes.md` for the priority table).

Choose (a) over (b) over (c) over (d). One fix per pattern — fix the root, not every symptom.

Document each fix: what to add, where, and why (cite both occurrences).

### Step 5 — Write the retrospective

```markdown
## Phase retrospective — <phase>

**Metrics:** N tasks, M investigate, K fail, J rework. Rework rate: X%. Investigate ratio: Y%. Health: <status>.

**Build-log failure classes:**
- `<class>` — first-seen (task #N: <description>)
- `<class>` — pattern (task #N + <prev-phase> task #M). Fix proposed.

**Review-sourced failure classes:**
- `<class>` — first-seen (N findings: <representative example>)
- `<class>` — pattern (N findings + <prev-phase>). Fix proposed.

**Compounding fixes proposed:**
- [target] Add <description> to <file/section>. Reason: <class> in <source-1> and <source-2>.
```

Omit the "Review-sourced" section when no PR exists or zero Critical/Concern findings. Omit the "Build-log" section if no build-log failures. Always include at least one section or "No compounding fixes".

Write the retrospective to `docs/plan/archive/<phase>.retro.md`. Set `retro_complete: true` in `docs/plan/progress.yaml`. **Update the PRD index:** if `docs/product/PRD.md` exists and has an Implementation Phases table, update the row for this phase to status "Shipped". This closes the sync gap between `progress.yaml` and the PRD table — without this, spec-author reads a stale "Planned" status when defining the next phase.

**Clean up consumed briefs:** Scan `docs/briefs/` for files with frontmatter `status: specced` (set by spec-author when a brief is consumed into a phase spec). Delete each one — the phase spec in `docs/product/phases/` is the permanent record. If no briefs have `status: specced`, this step is a no-op. Do not delete briefs with `status: draft` — those are unconsumed and may be queued for future phases.

Commit and **push to the remote** — the retro-gate GitHub Action triggers on push events, so the commit must reach the remote for the check to re-run and unblock merge.

### Step 6 — Apply approved fixes

Present fixes for user approval.

**If approved:**
- Apply each fix to the target file.
- Commit: `docs: compound <failure-class> fix from <phase> phase`

**Workspace-level commits (compounding fixes outside project root):**

Compounding fixes targeting workspace-level files (skill SKILL.md files) must be committed to the plugin repo, not the project PR branch:

1. Navigate to the plugin root (`${CLAUDE_PLUGIN_ROOT}`).
2. Stage the modified allowlisted skill files.
3. Commit: `compound: <description>`
4. Push to remote.

**If rejected:**
- Record the rejection in the retro file: `**Rejected:** [target] <description> — Reason: <operator's reason>`.
- In Step 3 (twice-seen rule), when checking previous retros, also check for rejected fixes. If the same fix was previously rejected, do NOT re-propose it. Instead note: "Previously rejected in <phase> retro. Skipping."

**If no fixes:** commit `docs: phase retrospective for <phase>`

## Compounding fix allowlist

Compounding fixes may target workspace-level paths outside the project root, but **only** paths on this allowlist:

- `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md`

**Note:** New learnings are written to the project-local `docs/plan/LEARNINGS.md` (within the project root, so no allowlist entry needed). MANUAL.md is plugin-shipped read-only reference and is not on the allowlist.

Before writing any compounding fix, verify the target path is either within the project root or on this allowlist. Refuse any fix targeting a path outside both.

Before applying any compounding fix, validate the write target against the scope-check procedure defined in the build-loop router skill (`${CLAUDE_PLUGIN_ROOT}/skills/build-loop/SKILL.md`, Scope Enforcement section). Do not duplicate the scope-check logic here — reference the canonical procedure.

## Safety rules

- Read-only by default. Only writes when applying approved fixes.
- Never modify the root workspace `AGENTS.md` (the immutable charter).
- Compounding fixes CANNOT target any AGENTS.md file (workspace-level or project-level). Project AGENTS.md is updated automatically by the build-loop's Phase Reconciliation Gate — not by phase-retro.
- Never modify source code. Fixes target skills, rules, or docs — not application code or AGENTS.md files.
- Note uncertainty if the phase log is ambiguous.

## Integration with build-loop

The phase-retro is enforced as a required GitHub PR status check. When a PR includes `phase_complete: true` in `docs/plan/progress.yaml`, merge is blocked until `retro_complete: true` is also set. Run `/sabs:phase-retro` to produce the retro (written to `archive/<phase>.retro.md`), set `retro_complete: true` in `progress.yaml`, commit to the PR branch, and push to the remote to unblock the check. Compounding fixes that target workspace-level files (skill files, rules) are committed separately outside the project repo.
