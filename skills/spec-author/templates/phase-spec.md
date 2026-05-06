# Phase Spec Templates

Reference templates used by the spec-author skill when producing phase specifications.

## Per-phase spec file template

Written to `docs/product/phases/<phase-name>.md`:

```markdown
# Phase: <phase-name>

Status: draft

## Stories

### US-XX — Story title

As a [role], I want [capability], so that [benefit].

**Acceptance criteria**:
- Criterion 1 (testable, mechanically verifiable)
- Criterion 2
- ...

**User guidance:**
- Discovery: <how the user finds this feature — button location, menu item, URL, config file>
- Manual section: <which manual page/section this belongs to, or "new page: <name>">
- Key steps: <1-3 sentence walkthrough a user would follow>

**Design rationale:** <1 sentence explaining WHY this approach was chosen over alternatives. Required for stories with UI mechanism choices or ambiguous "what" vs "how" decisions. Use "N/A" for straightforward CRUD or internal changes.>

### US-YY — Story title
<full story content>

## Done-when (observable)
- [ ] Criterion 1 [US-XX]
- [ ] Criterion 2 [US-XX]
- [ ] Criterion 3 [US-YY]
- ...

## Golden principles (phase-relevant)
- Principle text (from AGENTS.md)
```

## Phase Specification Format (shared contract with build-loop)

This is the format written to `docs/plan/phase-goal.md`. The spec-author produces it; the build-loop verifies against it.

```markdown
## Phase goal

<Narrative description of the phase objective.>

### Stories in scope
- US-XX — Story title
- US-YY — Story title

### Done-when (observable)
- [ ] Criterion 1 [US-XX] (mechanically verifiable — a specific file exists, endpoint returns a shape, test covers a case)
- [ ] Criterion 2 [US-XX]
- [ ] Criterion 3 [US-YY]
- ...

### Golden principles (phase-relevant)
- Principle text (extracted from AGENTS.md, relevant to this phase's work)
- ...
```

## PRD index table format

```markdown
| Phase | Status | Stories | Spec |
|---|---|---|---|
| foundation | Shipped | US-01, US-02, US-03 | [phases/foundation.md](phases/foundation.md) |
| <new-phase> | Draft | US-XX, US-YY | [phases/<new-phase>.md](phases/<new-phase>.md) |
```

## Gate 2 summary table format (chat output)

```
## Phase: <phase-name> — spec summary

| Story | Title | Criteria | Safety |
|---|---|---|---|
| US-XX | <title> | 4 | 1 |
| US-YY | <title> | 3 | 0 |
| — | Structural | 2 | — |
| **Total** | | **9** | **1** |

Full spec written to `docs/plan/phase-goal-draft.md`.
Review there, or ask me to expand any story inline.

**Learnings review:** <N> gaps auto-fixed, <M> items need your input.
<list any items requiring operator judgment, e.g., phase split, design direction>
```

## Readiness checklist

- [ ] User stories exist in PRD with testable acceptance criteria
- [ ] Phase is listed in the PRD Implementation Phases table
- [ ] Done-when checklist exists with minimum 3 observable criteria
- [ ] Every done-when criterion is mechanically verifiable
- [ ] Every done-when criterion is tagged with a story ID (`[US-XX]`) or `[phase]`
- [ ] Architecture doc reviewed (no forward-looking content added)
- [ ] `AGENTS.md` sections affected by this phase are identified
- [ ] User documentation impact is identified (manual pages to create/update, or justified skip)
- [ ] Every user-facing story has a User guidance block and a corresponding documentation done-when criterion
- [ ] Golden principles relevant to this phase are identified
- [ ] No conflicts with the current running phase in progress.yaml
