---
name: regression-detect
description: "Diffs test results before and after a code change to identify regressions — new test failures not present in the baseline"
---

<!-- version: 1 -->
Diff test results before and after a code change to identify regressions — new test failures that weren't present in the baseline.

## Parameters

- `baseline` — file path to the previous verify output (the "before" snapshot)
- `current` — file path to the current verify output (the "after" snapshot)
- `project` — project path (optional, used only for display)

## How it works

1. **Read both files.** If the baseline file does not exist, output PASS with note "No baseline available — skipping regression check. Current output will become the baseline." and stop.
2. **Parse test results from each file.** Extract individual test outcomes (test name -> pass/fail). Support these common output formats:
   - **pytest:** lines matching `PASSED`, `FAILED`, `ERROR` with test path (e.g., `tests/test_foo.py::test_bar PASSED`)
   - **jest / vitest:** lines matching `✓` or `✕` or `PASS`/`FAIL` with test name, or summary lines like `Tests: N passed, M failed`
   - **go test:** lines matching `--- PASS:` or `--- FAIL:` with test name
   - **Generic:** lines containing `PASS` or `FAIL` adjacent to an identifier that looks like a test name (word containing `test` or `Test` or `_test` or `.test`)
   - **Verify-gate format:** lines starting with `### PASS:` or `### FAIL:` followed by check name
   When parsing, extract the most specific test identifier available (e.g., `test_foo.py::test_bar` not just `test_bar`). If a line doesn't match any known format, skip it.
3. **Build two maps:** `baseline_results = { test_name: "pass"|"fail" }` and `current_results = { test_name: "pass"|"fail" }`.
4. **Diff the maps:**
   - **Regressions:** tests that are `pass` in baseline but `fail` in current
   - **Fixes:** tests that are `fail` in baseline but `pass` in current
   - **New tests:** tests in current but not in baseline (informational, not a regression)
   - **Removed tests:** tests in baseline but not in current (informational, flag as warning)
5. **Determine verdict:**
   - **FAIL** if any regressions exist
   - **PASS** if zero regressions (fixes and new tests are fine)
6. **Output the result** in the format below.

## Output format

```
## Regression Detection Results

Baseline: N tests (M passed, F failed)
Current:  N tests (M passed, F failed)

### REGRESSIONS (new failures)
- `test_name` — was PASS, now FAIL

### FIXES (new passes)
- `test_name` — was FAIL, now PASS

### NEW TESTS
- `test_name` — PASS|FAIL

### REMOVED TESTS (warning)
- `test_name` — was in baseline, missing from current

### Verdict: PASS | FAIL
Regressions found: N
```

If there are no entries in a section, print "(none)" under that heading.

## Integration with build-loop

The build-loop calls this skill during Branch A between quality checks (step 5) and commit gates (step 6). The flow:

1. After verify passes (step 3), the build-loop saves verify output to `docs/plan/test-baseline-current.txt`.
2. After quality checks pass (step 5), the build-loop calls: `/sabs:regression-detect baseline=docs/plan/test-baseline.txt current=docs/plan/test-baseline-current.txt`
3. If FAIL (regressions found): treat as task failure. Do NOT commit. Queue a fix task naming the regressed tests.
4. If PASS: proceed to commit gates. After successful commit, promote `test-baseline-current.txt` -> `test-baseline.txt`.

The baseline file (`test-baseline.txt`) persists across tasks within a phase. It represents the last known-good test state.

## Standalone usage

Run standalone to compare any two test output files:

```
/sabs:regression-detect baseline=path/to/before.txt current=path/to/after.txt
```

## Rules

- This skill is **read-only** — it never modifies files. The build-loop handles file promotion.
- When parsing test output, be lenient with formats. If you can't parse a line, skip it. If you can't parse either file at all, output PASS with a warning: "Could not parse test results — regression check inconclusive."
- Removed tests (in baseline but not in current) are a **warning**, not a regression. The agent may have intentionally removed or renamed tests. Flag them for visibility but do not fail.
- This skill is stateless — it has no knowledge of the build-loop's orchestration state. It takes two files and produces a diff.
