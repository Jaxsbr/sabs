---
name: test-gate
description: "Full verification stack — runs verify command, golden principles, quality checks, and regression detection with short-circuit on first failure"
---

<!-- version: 1 -->
Run the full verification stack against a project: verify command, golden principles, quality checks, and regression detection. Short-circuits on first failure. Returns structured per-gate results.

This skill is **stateless and read-only** — it never modifies files. The caller (build-loop or operator) handles file management like baseline promotion, progress.yaml updates, and commit decisions.

## Parameters

- `project` — path to the project root (absolute, or relative to cwd; required)
- `verify` — the shell command to run for verification (optional; if omitted, read from `AGENTS.md` `## Verify` section)
- `phase-goal` — path to `phase-goal.md` for golden principles extraction (optional; if omitted, Gate 2 is skipped)
- `baseline` — path to the previous test baseline file (optional; if omitted, Gate 4 is skipped)
- `current-out` — path where current verify output should be saved by the caller (optional; used only by Gate 4 as the "after" snapshot — if omitted, Gate 4 is skipped)
- `suppressions` — comma-separated list of quality check names to skip in Gate 3 (optional)

## How it works

1. **Resolve inputs.**
   - Resolve `project` to an absolute path.
   - If `verify` is not provided, read the project's `AGENTS.md` and extract the verify command from `## Verify`. If no verify command is found, report FAIL with "No verify command configured" and stop.

2. **Gate 1 — Verify.**
   - Run the verify command from the project root.
   - Capture stdout+stderr.
   - Determine pass/fail from exit code (0 = pass, non-zero = fail).
   - If FAIL: record the gate result, output the structured report, stop (short-circuit).
   - If PASS: hold the captured output — it is used by Gate 4 as the "current" snapshot.

3. **Gate 2 — Golden Principles.**
   - If `phase-goal` is not provided: record SKIP. Proceed to Gate 3.
   - If provided: read the file, extract bullet points under `### Golden principles (phase-relevant)`.
   - For each principle, check whether the current uncommitted changes (from `git diff` and `git diff --cached`) violate it.
   - If any violation is found: record FAIL with the specific principle violated. Output the structured report, stop.
   - If no violations: record PASS. Proceed to Gate 3.

4. **Gate 3 — Quality Checks.**
   - Read the project's `AGENTS.md` for a `## Quality checks` section. If no such section exists: record SKIP. Proceed to Gate 4.
   - **Always run `root-agents-immutable` first** (non-optional). If it fails, record FAIL, stop.
   - For each configured check: if the check name appears in `suppressions`, skip it.
   - Run each non-suppressed check following the verify-gate check library (same logic as `/sabs:verify-gate`). Do not duplicate the check definitions — follow the procedures described in the verify-gate skill (`${CLAUDE_PLUGIN_ROOT}/skills/verify-gate/SKILL.md`).
   - If any check fails: record FAIL with the specific check name and findings. Output the structured report, stop.
   - If all checks pass: record PASS. Proceed to Gate 4.

5. **Gate 4 — Regression Detection.**
   - If `baseline` is not provided, or `current-out` is not provided, or the baseline file does not exist: record SKIP.
   - Otherwise: compare the baseline file against the Gate 1 verify output using the regression-detect logic (same procedure as `/sabs:regression-detect`). Parse both files for test results, diff the maps, check for regressions.
   - If regressions are found: record FAIL with the regressed test names. Output the structured report, stop.
   - If no regressions: record PASS.

6. **Output.** Produce the structured result (see Output format below).

## Output format

```
## Test Gate Results — <project name>

Gates run: N
Passed: N
Failed: N
Skipped: N

### GATE 1: Verify — PASS | FAIL
<if FAIL: first 20 lines of verify output showing the failure>
<if PASS: summary line — "Exit code 0. N tests passed." or first summary line from output>

### GATE 2: Golden Principles — PASS | FAIL | SKIP
<if FAIL: "Violated: <principle text>" with brief explanation>
<if SKIP: "No phase-goal provided — skipped.">
<if PASS: "No violations detected.">

### GATE 3: Quality Checks — PASS | FAIL | SKIP
<if FAIL: per-check results — "FAIL: <check-name>" with findings>
<if SKIP: "No quality checks configured in AGENTS.md — skipped.">
<if PASS: "N checks passed." with check names listed>

### GATE 4: Regression Detection — PASS | FAIL | SKIP
<if FAIL: list of regressed tests — "was PASS, now FAIL">
<if SKIP: "No baseline provided — skipped." or "No baseline file exists — skipped.">
<if PASS: "No regressions. N tests compared.">

### Verdict: PASS | FAIL
<if FAIL: "Failed at Gate N: <gate name>. Subsequent gates not run.">
<if PASS: "All gates passed.">
```

Gates that were never reached (due to short-circuit) are omitted from the output entirely — they are not marked SKIP.

## Rules

- **Stateless.** Never modify files. Never update progress.yaml. Never commit. The caller is responsible for all state management.
- **Short-circuit on first failure.** Gates run in order 1->2->3->4. On first FAIL, remaining gates are not run.
- **Verify-gate reuse.** Gate 3 follows the same check library and procedures as `/sabs:verify-gate`. If verify-gate evolves (new checks, changed behavior), Gate 3 inherits the changes by reading the same skill file.
- **Regression-detect reuse.** Gate 4 follows the same diff logic as `/sabs:regression-detect`. Same parsing rules, same verdict criteria.
- **No file writes.** The verify output captured in Gate 1 is held in memory for Gate 4. The caller saves it to disk if needed (e.g., build-loop saves to `test-baseline-current.txt` on pass).

## Integration with build-loop

The build-loop's Branch A steps 4-7 currently contain inline verification logic. Test-gate consolidates this into a single call:

**Build-loop invocation (future):**
```
/sabs:test-gate project=<PROJECT_ROOT> phase-goal=docs/plan/phase-goal.md baseline=docs/plan/test-baseline.txt current-out=docs/plan/test-baseline-current.txt
```

**Failure-to-fix-task mapping** (build-loop reads the structured output):

| Failed gate | Fix task description |
|---|---|
| Gate 1: Verify | `fail — verify` |
| Gate 2: Golden Principles | `fail — golden principle: <principle>` |
| Gate 3: Quality Checks | `fail — quality-check: <check-name>` |
| Gate 4: Regression | `fail — regression: <test names>` |

The build-loop passes `suppressions` from `quality_check_suppressions` in progress.yaml. The repeated-failure counting (3 consecutive quality check failures -> suggest suppression) remains in the build-loop since it is orchestration state.

## Standalone usage

Minimal — runs Gate 1 and Gate 3 only (Gates 2 and 4 skipped):
```
/sabs:test-gate project=<path>
```

Full — all four gates:
```
/sabs:test-gate project=<path> verify="npm test" phase-goal=docs/plan/phase-goal.md baseline=docs/plan/test-baseline.txt current-out=docs/plan/test-baseline-current.txt
```
