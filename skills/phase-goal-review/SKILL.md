---
name: phase-goal-review
description: "Reviews a phase-goal draft against built-in failure patterns and project-local LEARNINGS.md — produces structured gaps and suggested additions"
---

<!-- version: 2 -->
Reviews a phase-goal-draft against a fixed set of built-in failure-pattern dimensions, plus any additional patterns recorded in the project's local `docs/plan/LEARNINGS.md`. Produces a structured review with concrete gaps and suggested additions — not vague advice. Read-only: reviews and reports but does not edit the draft.

## Parameters

- `project` — path to the project root (absolute, or relative to cwd). If omitted, inferred from cwd — cwd must contain a project-level `AGENTS.md`, not the workspace root; error with "specify project=" if not.

---

# Phase Goal Review

Checks a phase-goal-draft against a fixed set of built-in failure-pattern dimensions, plus any additional patterns recorded in the project's local LEARNINGS.md.

## Trigger phrases

"review phase goal", "check phase goal draft", "audit phase spec", "review done-when criteria", "check spec against learnings"

## Before starting

1. Determine the **target project root** using the `project` parameter or cwd (same resolution rules as other build skills).
2. Read these files:
   - `docs/plan/phase-goal-draft.md` in the project root — the draft to review. If the file does not exist, error with: "No phase-goal-draft.md found. Run spec-author first to produce a draft."
   - `docs/plan/LEARNINGS.md` in the project root — project-local learnings (may not exist on first run; if missing, skip the "Additional findings" pass — the built-in dimensions still apply).
   - `AGENTS.md` in the project root — for golden principles, layer rules, and **project type** (see step 4).
3. Parse the draft into: phase narrative, stories in scope, done-when criteria, golden principles, design direction (if present), safety criteria section (if present).
4. If `docs/plan/LEARNINGS.md` exists, parse each entry into: number, failure class, description, action taken, prevention point, **scope**.
   - **Scope filtering:** Read `## Project type` from the project's `AGENTS.md`. If present (e.g., `phaser-game`), include learnings where `Scope` is `universal` (or absent) OR matches the project type. Exclude learnings with a different domain-specific scope. If no `## Project type` is declared, include only `universal` learnings (safe default — domain-specific learnings require an explicit match).

## Review dimensions

Apply each dimension below to the draft. For each, determine: **gap** (missing entirely), **borderline** (present but could be tighter), or **clean** (no issue).

### 1. Subjective criteria check

**Class:** `spec-subjective`
**What to check:** Every done-when criterion in the draft.
**Flag when:** A criterion cannot be mechanically verified by running a command, reading a file, or checking test output. Watch for: "feels alive", "looks good", "is fast", "feels responsive", "is intuitive", "works well".
**Suggested fix format:** "Criterion '<text>' is subjective. Replace with measurable proxy: <specific suggestion, e.g., 'animation completes in < 300ms', 'Playwright screenshot matches reference at >95% similarity'>."

### 2. Spec ambiguity check

**Class:** `spec-ambiguity`
**What to check:** Every story's acceptance criteria and done-when items.
**Flag when:**
- A story lacks a **Design rationale** field or contains "alternatively" phrasing without resolution.
- The spec does not address **state boundaries** between systems — e.g., which component owns a piece of state, what happens at handoff points.
- A new screen or flow is introduced without specifying **user journey context**: how the user arrives, how they navigate back, how they know their current state.
- Path restructuring is specified without a **migration checklist** — old paths referenced elsewhere, imports to update, config to change.
- A shared library extraction is specified without a **Consumer adaptation** note listing hardcoded values that become parameters for consumer-specific behavior.
**Suggested fix format:** "Story US-XX: <specific ambiguity>. Add: <specific addition, e.g., 'Design rationale explaining why X over Y', 'Consumer adaptation note listing parameterised values'>."

### 3. Phase size check

**Class:** `phase-oversize`
**What to check:** Count of stories in scope.
**Flag when:** More than 5 user stories in a single phase.
**Suggested fix format:** "Phase has <N> stories (max 5). Split into: Phase A (<stories>) and Phase B (<stories>), ensuring no cross-phase dependencies within the split."

### 4. Error-path coverage check

**Class:** `missing-error-path`
**What to check:** Every state transition, conditional branch, and external interaction implied by the stories.
**Flag when:** The spec addresses the happy path but omits failure/edge cases. Specifically check:
- API endpoints without error-response criteria (400, 404, 403, 500).
- Data operations without empty/null/missing-field handling.
- External service calls without timeout/unavailable handling.
- State transitions without "what happens when X is empty/full/zero/unavailable?" criteria.
**Suggested fix format:** "Story US-XX introduces <interaction>. Missing error-path criterion. Add: '<specific done-when criterion for the failure case>'."

### 5. Non-deterministic input check

**Class:** `silent-test-pass`
**What to check:** Stories that consume LLM output, external API responses, or other non-deterministic input.
**Flag when:** The spec lacks:
- A done-when criterion for **degraded/partial response** handling (e.g., LLM returns incomplete JSON, API returns 429, response is truncated).
- A done-when criterion for a **real-input smoke test** (not just mocked responses).
**Suggested fix format:** "Story US-XX consumes <non-deterministic source>. Add: (1) 'Handler gracefully degrades when <source> returns partial/malformed response [US-XX]', (2) 'Smoke test exercises real <source> call with live credentials [US-XX]'."

### 6. Config vs hardcoded values check

**Class:** Cross-reference (golden principles vs done-when criteria)
**What to check:** If golden principles or design rationale mention "config-driven", "configurable", or "environment-specific", check whether done-when criteria reference named constants, config objects, or environment variables — not hardcoded literals.
**Flag when:** A done-when criterion hardcodes a specific value (port number, URL, threshold, file path) that the golden principles say should be configurable.
**Suggested fix format:** "Golden principle says '<principle>'. Criterion '<text>' hardcodes <value>. Replace with reference to config: '<rewritten criterion using named constant or config key>'."

### 7. Forward-looking architecture check

**Class:** `edit-policy-drift`
**What to check:** The draft and any referenced architecture updates.
**Flag when:**
- The draft contains or implies "planned for" or "structural intent" sections targeting `ARCHITECTURE.md`. Architecture docs describe shipped state only — planned sections drift before implementation and cause edit-policy-drift.
- Done-when criteria reference architecture entries for features not yet built.
**Suggested fix format:** "Draft references planned architecture for <feature>. Remove planned sections from ARCHITECTURE.md scope — architecture is updated at phase completion by the build-loop's Phase Reconciliation Gate, not at spec time."

### 8. Safety criteria check

**Class:** `security-gap`
**What to check:** Whether the phase introduces API endpoints, user text input fields, or query interpolation.
**Flag when:**
- The phase introduces endpoints but has no error-path done-when criteria (400/404/403).
- The phase accepts user text but has no input-validation done-when criteria (type check, max length, required fields).
- The phase builds queries from user data but has no parameterised-query criterion.
- **None of the above apply** but the draft has no explicit statement explaining why safety criteria are not needed.
**Suggested fix format:** "Phase introduces <endpoint/input/query>. Missing safety criterion. Add: '<specific done-when criterion>'. OR: Add explicit note: 'Safety criteria: N/A — this phase introduces no endpoints, user input fields, or query interpolation.'"

### 9. Design taste check

**Class:** `missing-design-taste`
**What to check:** Phases with user-facing UI.
**Flag when:** No "Design direction" section exists, or the section contains only generic terms ("clean", "modern", "simple") without an opinionated aesthetic direction.
**Suggested fix format:** "Phase has user-facing UI but no opinionated design direction. Add a 'Design direction' section with a specific aesthetic (e.g., 'playful and colorful for kids', 'dense data-dashboard with monospace type', 'retro-futuristic with scanline effects'). Generic terms like 'clean' or 'modern' are insufficient."

### 10. User journey completeness check

**Class:** `spec-ambiguity` (user-journey facet)
**What to check:** Every new screen, navigation flow, or identity/state concept introduced by the phase.
**Flag when:** The spec does not address all three:
- (a) How the user knows their **current state** from any screen (active indicators, breadcrumbs, URL, title).
- (b) How they **navigate back** or switch context (back button, breadcrumb, tab, menu).
- (c) How they **modify/undo/remove** what they created (edit, delete, revert controls).
**Suggested fix format:** "Story US-XX introduces <screen/flow>. Missing user journey coverage: <(a)/(b)/(c) specifically>. Add done-when criterion: '<specific criterion>'."

## Handling project-local learnings

The 10 dimensions above are built into the skill. The project's local `docs/plan/LEARNINGS.md` may grow over time as `phase-retro` records new failure patterns. After applying the 10 built-in dimensions:

1. If a project-local LEARNINGS.md was loaded, scan all **in-scope** learning entries (after scope filtering) for failure classes not covered by the dimensions above.
2. For each uncovered failure class, check whether the draft contains patterns that match the learning's description.
3. If a match is found, report it as a gap with the learning number and a suggested fix, under a heading **"Additional findings (project learnings)"**.

If no project-local LEARNINGS.md exists, skip this pass.

## Output format

Produce the review in this exact structure:

```
## Phase Goal Review — <phase-name>

Reviewed against the 10 built-in dimensions plus <N> project-local learnings (filtered to scope: universal + <project-type>).

### Gaps found

- **[<dimension name>]** <specific finding>.
  -> Suggested addition: `<done-when criterion or spec change>`

- **[<dimension name>]** <specific finding>.
  -> Suggested addition: `<done-when criterion or spec change>`

### Borderline items

- **[<dimension name>]** <what's present> — but could be tighter: <suggestion>.

### Clean

- Subjective criteria: all criteria are mechanically verifiable.
- Phase size: <N> stories (within limit).
- ...
```

For findings produced by the "Additional findings (project learnings)" pass, cite the project-local learning number (e.g., `[Project learning #3]`).

**Rules:**
- Every finding in "Gaps found" and "Borderline items" must cite either a built-in dimension name or a project learning number.
- "Gaps found" items must include a concrete suggested done-when criterion or spec addition — not vague advice.
- "Clean" items are one line each — dimension name and brief confirmation.
- If there are no gaps, say "No gaps found." under that heading.
- If there are no borderline items, say "No borderline items." under that heading.

## Constraints

- **Read-only.** This skill reviews and reports. It does not edit the draft or any project files.
- **No invented criteria.** Findings must be grounded in either a built-in dimension or a project-local LEARNINGS.md entry. Do not invent new review criteria.
- **Fresh read.** Read the project-local LEARNINGS.md (if present) from disk each time — do not rely on cached or memorised content.
- **Cite sources.** Every finding must reference either a built-in dimension name or a specific project learning number so the operator can look up full context.
