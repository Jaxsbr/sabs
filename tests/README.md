# SABS Integration Test Suite

Pre-release gate for the Semi-Autonomous Build System (SABS) Claude Code plugin. Validates the entire plugin end-to-end, from structural correctness through skill invocation to a complete build-loop cycle.

## When to Run

**Before cutting a release only.** This is NOT a CI job. Tier 2 and 3 use `claude -p` API calls that cost real money.

## Cost Expectations

| Tier | Model | Cost | Time | What it tests |
|------|-------|------|------|---------------|
| **Tier 1** | — | Free | ~10 seconds | File structure, identity guard, portability, metadata |
| **Tier 2** | haiku | ~$0.05-0.20 | ~10-15 minutes | Individual skill invocations |
| **Tier 3** | sonnet | ~$1-4 | ~15-30 minutes | Full build-loop cycle: init, spec, build, iterate, PR, retro |
| **Full run** | mixed | ~$1-4.20 | ~30-45 minutes | All tiers |

Costs are approximate and depend on current Claude API pricing and how many iterations the build-loop runs in Tier 3.

## Model Configuration

Tier 2 and Tier 3 use different models by default:

- **Tier 2 (haiku):** Simple skill invocations. Haiku handles these well (7/8 pass rate, one failure was a test expectation issue not a model issue).
- **Tier 3 (sonnet):** Full build-loop cycle. Sonnet is required — haiku fails to execute `build-loop-init`'s 9 convergence gates correctly, reporting success without creating any files.

To override the model for all tiers (e.g. for targeted testing):

```bash
./projects/sabs/tests/run-integration-tests.sh --model opus
```

This sets both `CLAUDE_MODEL_TIER2` and `CLAUDE_MODEL_TIER3` to the specified model.

## Prerequisites

- `claude` CLI installed and authenticated
- `gh` CLI installed and authenticated (with `delete_repo` scope)
- `jq` installed
- `git` installed
- Access to the `jaxs-agent-org` GitHub organization (for Tier 2/3 test repos)

## Usage

```bash
# Run all tiers (will prompt before expensive tests)
./projects/sabs/tests/run-integration-tests.sh

# Structural checks only (free, fast)
./projects/sabs/tests/run-integration-tests.sh --tier 1

# Structural + skill invocation
./projects/sabs/tests/run-integration-tests.sh --tier 1,2

# Custom plugin path
./projects/sabs/tests/run-integration-tests.sh --plugin-dir /other/path/to/sabs

# Override model for ALL tiers (e.g. test with opus across the board)
./projects/sabs/tests/run-integration-tests.sh --model opus

# Help
./projects/sabs/tests/run-integration-tests.sh --help
```

## Tier Descriptions

### Tier 1 -- Structural (19 tests)

Free, no Claude API calls. Validates:

- Plugin manifest (`plugin.json`) valid JSON with required fields
- Hook configuration (`hooks.json`) valid JSON
- All 13 skill directories exist with SKILL.md files
- YAML frontmatter has `name` field matching directory name
- Identity guard hook: 4 scenarios (no config, non-matching remote, correct identity, wrong identity)
- **HARD BLOCKER:** Zero `~/dev/` references in skills (portability)
- **HARD BLOCKER:** Zero functional `~/.claude/commands/` references (portability)
- Cross-skill `${CLAUDE_PLUGIN_ROOT}` references resolve to existing files
- `MANUAL.md` exists at plugin docs root; `LEARNINGS.md` is absent (no plugin-shipped baseline)
- Version comments present in 12/13 skills (handle-pr-review excluded)
- `disable-model-invocation: true` in 5 required skills
- `hooks.json` matcher targets Bash only
- `frontend-design` has `user-invocable: false`

### Tier 2 -- Skill Invocation (8 tests)

Uses `claude -p --model haiku` per test. Each skill is invoked with a crafted prompt and the output is checked for expected patterns.

Skills tested:
- `build-loop action=status` -- reads progress.yaml, reports idle state
- `verify-gate` -- reads AGENTS.md, reports quality check results
- `test-gate` -- runs gate structure (gates run or skip)
- `regression-detect` -- detects regressions from fixture files (2 tests: with regression, clean)
- `spec-author` -- produces a phase-goal-draft.md
- `phase-goal-review` -- reads learnings and reviews a draft
- `review-pr mode=local` -- loads and handles the no-PR case gracefully

### Tier 3 -- Full Cycle (7 tests)

Most expensive. Creates a real repo in `jaxs-agent-org`, runs the complete build-loop lifecycle, then cleans up.

Steps:
1. Create test repo in GitHub org
2. `build-loop-init` scaffolds project structure
3. `spec-author` generates a trivially simple phase spec
4. `build-loop start` creates build branch
5. `build-loop iterate` runs capped iterations
6. PR creation verified
7. `phase-retro` on the completed/aborted phase

## Output Format

```
[PASS] 1.01 Plugin manifest valid (name=sabs, version=0.4.0)
[FAIL] 2.03 Identity guard wrong identity warning
       Reason: exit=1 output=...
[SKIP] 3.06 No PR created (phase may not have completed)
       Reason: iterate may need more iterations
...
=============================================
 SUMMARY -- 2026-04-10 14:30:00 NZST
=============================================
Tier 1 (Structural):  19/19 PASS
Tier 2 (Skill):       8/8 PASS
Tier 3 (Full Cycle):  7/7 PASS

Overall: PASS (34/34)
```

## Exit Codes

- `0` -- all tests passed
- `1` -- one or more tests failed

## Test Fixtures

Located in `tests/fixtures/`:

| File | Purpose |
|------|---------|
| `regression-baseline.txt` | Pytest-style output for regression-detect baseline (all pass) |
| `regression-current-with-regression.txt` | Pytest output with one regression (test_subtraction) |
| `regression-current-clean.txt` | Pytest output with no regressions (clean + new test) |
| `test-agents.md` | Minimal AGENTS.md for test projects |
| `test-identities.json` | Identity guard config with correct test identity |
| `test-identities-wrong.json` | Identity guard config with wrong identity (triggers warning) |

## Cleanup

The script uses `trap cleanup EXIT` to ensure cleanup runs even on Ctrl+C or failure:

- Removes local temp directories
- Deletes remote test repos in `jaxs-agent-org`
- Removes any `identities.json` left in the plugin config directory

## Maintenance Notes

- If new skills are added to SABS, update the `EXPECTED_SKILLS` array in the Tier 1 section and add a Tier 2 test for the new skill.
- If version numbers are bumped, update the `EXPECTED_VERSIONS` associative array in test 1.16.
- If the identity guard script behavior changes, update tests 1.07-1.10.
- Tier 3 tests depend on `jaxs-agent-org` GitHub org access. If the org is renamed or access changes, update `GITHUB_ORG`.
