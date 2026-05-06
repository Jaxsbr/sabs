# Failure Class Taxonomy

Reference material for the phase-retro skill. Used to classify build-log failures and PR review findings.

## Taxonomy

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

Create new labels if needed. Be consistent across phases.

## Immediate-compound exceptions

These classes trigger compounding fixes on **first occurrence** (skip the twice-seen rule):

- `data-loss`
- `security-gap`

## Prevention point priority

When proposing compounding fixes, choose the earliest prevention point:

| Point | Priority | When |
|---|---|---|
| Spec-author gate | a (highest) | Spec writing |
| AGENTS.md rule | b | Build time |
| Quality check | c | After tests pass |
| Completion gate | d (lowest) | Before phase done |

Choose (a) over (b) over (c) over (d). One fix per pattern — fix the root, not every symptom.
