---
name: spec-author
description: "Defines product specifications and build phases — takes ideas through the pipeline to produce phase specs the build-loop can execute and verify"
allowed-tools: "Read(*) Write(*) Edit(*) Grep(*) Glob(*)"
disable-model-invocation: true
---

<!-- version: 6 -->
Defines product specifications and build phases for AI-first projects. Takes an idea or requirement through the pipeline — user stories, observable done-when criteria, architecture intent — producing a phase specification that the build-loop can execute and verify against.

## Parameters

- `project` — path to the project root (absolute, or relative to cwd). If omitted, inferred from cwd — cwd must contain a project-level `AGENTS.md`, not the workspace root; error with "specify project=" if not.

---

Takes an idea, requirement, or feature description through the product-to-build-ready pipeline. Produces phase specifications that conform to the **Phase Specification Format** — the shared contract with the build-loop.

## Companion tool: build-loop

This skill is one half of a delivery pair. The other half is the **build-loop** (`/sabs:build-loop`), which executes phases and verifies done-when criteria.

The spec-author produces specifications. The build-loop consumes them. The contract between them is the **Phase Specification Format** (see `${CLAUDE_PLUGIN_ROOT}/skills/spec-author/templates/phase-spec.md`). Every phase this skill produces must conform to that format, or the build-loop cannot verify completion.

## Before starting

1. Determine the **target project root**. Ask if ambiguous.
2. Read these files from the project root:
   - `AGENTS.md` — layer rules, invariants, golden principles
   - `docs/product/PRD.md` — product vision, phase index table, and any legacy inline stories (if exists)
   - `docs/product/phases/` — list existing per-phase spec files to understand shipped/planned phases and find the latest story IDs
   - `docs/architecture/ARCHITECTURE.md` — current topology (if exists)
   - `docs/plan/progress.yaml` — current build-loop phase to avoid conflicts (if exists)
3. Note existing story ID conventions, phase naming patterns, and any golden principles.

## Pipeline steps

Three gates, not five. Operator attention is scarce — use it on scope and substance, not mechanical file writes.

| Gate | What the operator reviews | Format |
|---|---|---|
| **Gate 1 — Scope** | Intent, constraints, operation type | 1-paragraph summary |
| **Gate 2 — Spec** | Stories + done-when combined | Summary table in chat + full detail written to draft file |
| **Auto** | File writes, PRD index, architecture, readiness | No approval — proceeds automatically after Gate 2 |

**Progressive disclosure rule:** At Gate 2, present a **compact summary table** in chat (story IDs, titles, criteria count per story, safety criteria count). Write the full detail to `docs/plan/phase-goal-draft.md`. Tell the operator: "Full detail is in `docs/plan/phase-goal-draft.md` — review there or ask me to expand any story." Only expand inline if the operator asks.

### Gate 1 — Clarify intent and scope

Parse the user's input into:
- **What**: the capability or change
- **Why**: the user need or problem
- **Where**: which modules, packages, or paths are affected
- **Constraints**: layer rules, dependencies, budget, timeline

If any of these are unclear, ask focused questions (max 3). Do not proceed with ambiguity in "what" or "where".

**Frontend phases — design direction:** If the phase introduces or changes user-facing UI, ask the operator for an aesthetic direction (e.g., "playful and colorful for kids", "minimal and clean", "retro-futuristic"). Include this in the phase spec under a `### Design direction` section. The build-loop reads this section and applies the frontend-design skill (`${CLAUDE_PLUGIN_ROOT}/skills/frontend-design/SKILL.md`) during UI implementation. If the operator declines to specify, note "Design direction: agent's choice — bold, context-appropriate" so the build-loop still applies the frontend-design skill rather than defaulting to generic styling.

Determine the operation type:
- **New stories** added to an existing PRD section
- **New PRD section** (new capability area)
- **Amendment** to existing stories
- **New phase** defined for existing stories

Present a one-paragraph scope summary and confirm before proceeding.

### Gate 2 — Draft stories and done-when criteria (combined)

Draft stories AND their done-when criteria together. Present them as a single review. This eliminates the separate stories-review and done-when-review gates that cause operator fatigue.

#### 2a. Write user stories

Write stories following the project's established PRD format. See `${CLAUDE_PLUGIN_ROOT}/skills/spec-author/templates/phase-spec.md` for the full story template.

Rules:
- Minimum 2 acceptance criteria per story.
- Acceptance criteria must be testable — state what can be checked, not what should feel right.
- Follow the project's existing ID convention (e.g. `US-C5`, `US-B9`). Check the PRD for the next available ID.
- Note dependencies between stories explicitly.
- Deferred stories go to `docs/product/backlog.md` with a reason, not the active PRD.
- Reject stories where User guidance fields contain "TBD", "TODO", or placeholder text. Discovery and key steps must be concrete.
- Every story with a User guidance block (non-N/A) must have at least 2 key steps in the walkthrough.
- **Interaction model (compounded):** When a story introduces user interaction that differs from the project's existing patterns (e.g., a new input mechanism, a visual exercise instead of a form, drag-and-drop instead of text entry), the story MUST include a description of how the user provides input and receives feedback — either inline in the acceptance criteria or in a separate "Interaction model" note. If the interaction matches an existing pattern already in the codebase, state that explicitly ("same input flow as X"). Without this, the build agent defaults to the nearest existing pattern and the result feels generic. If reference material exists (worksheets, mockups, competitor screenshots), mention it in the design rationale.
- **Consumer adaptation (compounded):** When a story extracts code into a shared library, module, or package consumed by multiple consumers (e.g., MCP server, TUI, CLI, API), the story MUST include a "Consumer adaptation" note listing hardcoded values that become parameters for consumer-specific behavior (e.g., `source_origin`, default paths, formatting choices, transport-specific defaults). Each parameterized value gets a done-when criterion: "consumer X passes its own value for Y" or "default is consumer-neutral".
- **Processing model (compounded):** When a story introduces a handler, adapter, or bridge that connects two systems (e.g., webhook -> queue, sync daemon -> data store, relay -> downstream service), the story MUST include a "Processing model" note that states: (1) what the handler does on receipt (validate, transform, queue, or ingest), (2) where the data goes next (queue file, API call, direct database write), (3) which system is responsible for final record creation. Without this, the build agent defaults to doing everything in the handler.

**Phase size gate:** If the stories drafted for a single phase exceed 5, stop and ask the user to split. Phases with 6+ stories have 3-6x higher rework rates. The split should produce phases where each is self-contained (no cross-phase story dependencies within the split).

**Do NOT present stories for separate review.** Continue directly to done-when criteria below. The operator reviews stories and done-when together at the end of Gate 2.

#### 2b. Draft done-when criteria

This is the critical step that connects the spec to the build-loop.

For each phase being defined, produce a **done-when checklist** by:

1. Reading each story's acceptance criteria.
2. Translating each criterion into a mechanically verifiable check, **tagged with the source story ID**. The `[US-XX]` tag is how the build-loop tracks per-story completion and produces a story commit when all criteria for a story are met. Examples:
   - Acceptance (US-C1): "User can create a capture record" -> Done-when: `POST /api/capture returns 201 with { id } on valid input [US-C1]`
   - Acceptance (US-C1): "Invalid input is rejected" -> Done-when: `POST /api/capture returns 400 when log_type is missing [US-C1]`
   - Acceptance (US-C2): "Schema validates record types" -> Done-when: `schema/record_contract.yaml rejects unknown log_type values (test: test_schema_rejects_unknown_type) [US-C2]`
3. Adding structural criteria that stories imply but don't state (tag with the story that implies them):
   - If a story (US-C1) requires a new module, add: `src/capture/index.ts exists and exports createCapture [US-C1]`
   - If a story (US-C1) requires tests, add: `test suite for capture module passes with >= N test cases [US-C1]`
   - If the phase introduces new files, directories, behavior rules, or changes the data model, add: `AGENTS.md reflects new <modules/directories/behavior/etc.> introduced in this phase [phase]` (the build-loop's Phase Reconciliation Gate handles the actual update at phase completion)
4. **Class baseline check (compounded):** When a story introduces new instances of an existing entity class (e.g., a new enemy type joining existing enemies, a new API endpoint joining existing endpoints), enumerate ALL shared behaviors that existing instances have and add a done-when criterion for each one on the new instance. Don't assume "same as existing" — make it explicit.
4a. **Variant baseline check (compounded, inverse of rule 4):** When a story introduces new behavior that mutates state consumed by multiple existing variants of a class (e.g., a new style panel writing `background` on rectangle / circle / diamond nodes; a new theme toggle applied across every existing screen; a new input field rendered in both a dev-app surface and an extension webview), enumerate EVERY existing variant and add one per-variant done-when criterion verifying the new behavior renders or applies correctly on that variant. Prefer an automated render-layer assertion per variant; when only manual verification is possible, the manual-verification doc must list each variant as a separate checkbox. Don't assume "it works on one, so it works on all" — per-variant CSS specificity, pre-existing `!important` rules, surface-specific bundles, and theme overrides routinely break this assumption silently. Rationale: a `silent-test-pass` recurrence — 55 passing tests, zero per-shape render checks, `!important` CSS silently swallowed style-panel picks on two of three shapes — and a follow-up `spec-subjective` recurrence where the build loop marked stories done from code inspection because the spec's manual-verification criteria did not enumerate the variants that needed checking.
5. Adding user documentation criteria for stories with user-facing behavior:
   - For every story that introduces or changes user-facing behavior, add a done-when criterion for user documentation. The criterion must reference the specific manual section or guide file.
   - Stories marked `User guidance: N/A` in the PRD do not need a documentation criterion.

**Validation**: review each criterion against two tests — (1) "Can an agent verify this by running a command, reading a file, or checking test output?" and (2) "Is this criterion tagged with a story ID (or `[phase]` with justification)?" If either fails, rewrite it.

**Observability gate:** Before presenting done-when criteria, apply this filter to every criterion:

1. Can this be verified by running a command, reading a file, or checking test output? Yes — keep. No — rewrite or flag.
2. Does this criterion involve subjective perception ("feels alive", "looks good", "is fast")? Yes — REJECT. Replace with a measurable proxy.
3. Is this a UI-only criterion with no server-side observable? If so, require at least one Playwright assertion.
4. Does this criterion specify a numeric threshold? Yes — verify the threshold falls on or between achievable values given the discrete parameters in scope. If unreachable, rewrite.
5. Does this criterion involve visual appearance in a broader viewport context? Yes — verify the criteria cover the full user-visible boundary, not just the component canvas.
6. Does the phase spec include a "Design direction" section with aesthetic claims? Yes — for each claim, verify at least one done-when criterion traces to it.

**Safety criteria (auto-added for stories with user input or API endpoints):**

Before presenting the done-when checklist, scan all stories in the phase and auto-add safety criteria:

1. **Scan for endpoints:** Identify stories that introduce new routes, API handlers, or form submission endpoints.
2. **Scan for user-text fields:** Identify stories with fields accepting user text (form inputs, text areas, config values, URL parameters).
3. **Auto-add error-path criteria:** For each new endpoint, add at least one error-path done-when criterion (400, 404, or 403).
4. **Auto-add input validation criteria:** For each field accepting user text, add a done-when criterion for input validation (minimum: type check, max length, required fields).
5. **Auto-add output encoding criteria:** For endpoints rendering user-provided content, add a done-when criterion for output encoding (textContent or equivalent, not innerHTML).
6. **Auto-add query-interpolation criteria:** For stories that build query filters or WHERE clauses from data-derived values, add a done-when criterion requiring parameterised or escaped value interpolation.
7. **Present for approval:** Safety criteria are presented under a separate "Auto-added safety criteria" heading. The user may adjust or remove them, but removal requires explicit justification.

**Compounded done-when rules (non-negotiable):**
- **LLM output safety:** Any story where LLM-generated output is received, parsed, or displayed must include done-when criteria for: (1) user input wrapped in explicit delimiters to resist prompt injection, and (2) raw LLM output never leaked to clients on error paths.
- **Async cleanup:** Any story involving async UI interactions must include done-when criteria for cancellation/cleanup on unmount or state change.
- **API input allowlisting:** Any story introducing API endpoints that accept user input must include done-when criteria requiring explicit field allowlisting.
- **API catch-all route scoping:** Any story introducing Express static file serving or catch-all routes must include a done-when criterion verifying API routes are excluded from the catch-all.
- **HUD/UI layout plan:** When a phase adds 2+ UI elements to an existing HUD, the spec must include a layout section with approximate coordinates.
- **Visual "reads as" test:** For any new visual element the player interacts with, at least one done-when criterion must state what the element should communicate to the user.
- **Atlas frame-pick verification (compounded):** Any story that introduces or modifies tile / sprite atlas frame indices (entries in `TILESETS` registries, decoration `FRAME` constants, prop `spriteFrame` values, or any literal frame-index strings consumed by a sprite renderer) must include a done-when criterion requiring a labeled-atlas preview be generated and each frame visually verified before the commit lands. The verification artefact (labeled atlas PNG) need not be committed — only the verification step is gated. If the project ships a `tools/atlas-preview.py` (or equivalent) the criterion should name the invocation, e.g. `python3 tools/atlas-preview.py assets/tilesets/<id>/tilemap.png /tmp/preview.png && open /tmp/preview.png`. Rationale: `visual-pick-without-verification` was confirmed twice across tile-based phases — frame indices were chosen from atlas thumbnails and turned out to be unrelated assets (e.g., a frame index expected to be a prop turned out to be a portrait). Picks made from atlas thumbnails without rendering a labeled grid produce 30-50% wrong-concept frames at first commit and force a full re-pick after merge.

- **Operator-walkthrough completion gate (compounded):** When a phase delivers an *author-facing surface* — any tool the operator drives directly (editor, dev tool, content composer, generation pipeline, story-scene authoring UI, asset preview tool, etc.) — the phase spec MUST include at least one operator-walkthrough done-when criterion. The criterion text MUST be a **plain-language step-by-step test guide**, not jargon-style abstract bullets. Specifically:

  1. Numbered steps a person can follow without re-reading the spec.
  2. Each step describes one concrete action ("click the Vertex button", "scroll your mouse wheel while holding Ctrl") and what should visibly happen ("a green dot appears at the corner you clicked", "the canvas grows larger").
  3. No abstract terms — phrases like "verify the rendering pipeline", "exercise the cell-paint mode", or "operator drives the new authoring surface for ≥ 10 minutes against a representative scenario" read like AI jargon and get skipped. They do not satisfy this rule.
  4. Steps end with: "If any step doesn't behave as described, record it in `docs/plan/<phase>-known-issues.md` (or equivalent). Phase cannot be marked complete until each gap is either fixed or explicitly deferred to a follow-up phase."

  Validation before locking the spec: re-read the criterion as if you were the operator opening it cold. If it reads like a checklist of features to verify rather than a script you can follow blind, rewrite it. The plain-language constraint is non-negotiable — abstract framings get skipped, and the gap re-surfaces as wasted operator time mid-content-authoring.

  Rationale: `platform-testing-gap` recurred across three phases of an authoring-tool project — touch input routing, viewport zoom + orientation, and editor-tooling gaps (missing zoom, multi-tileset rendering bug, no trigger/NPC/exit authoring). The build loop's compile-only verify cannot catch ergonomics; gaps surface only when the operator actually drives the new surface. Prior retros explicitly punted on compounding because the issues "weren't classified build-loop failures" — the third occurrence shifted that calculus. The operator subsequently noted that the original wording for this rule (an abstract "operator runs the surface for 10 minutes") was itself the kind of jargon-style framing that gets ignored, hence the plain-language step-by-step requirement is core to the fix, not optional.

#### 2c. Present combined review (Gate 2 checkpoint)

This is the **only approval gate** for spec substance. Use progressive disclosure.

1. **Write full detail to file** — Write the complete stories AND done-when checklist to `docs/plan/phase-goal-draft.md` using the Phase Specification Format.

2. **Run phase-goal-review** — After writing the draft, run the phase-goal-review check (read `${CLAUDE_PLUGIN_ROOT}/skills/phase-goal-review/SKILL.md` for the full review dimensions). This reads the draft and the project-local learnings (`docs/plan/LEARNINGS.md` if it exists), then checks against the built-in dimensions plus any project-local failure classes. For each **gap** found:
   - If the gap is a missing done-when criterion, add it to the draft file automatically.
   - If the gap requires a structural spec change, add it to the draft automatically.
   - If the gap requires operator judgment (e.g., phase split, design direction), note it for the summary.
   After auto-fixing, re-read the updated draft. Include the review summary in chat output.

3. **Present a compact summary table in chat** — NOT the full detail. See `${CLAUDE_PLUGIN_ROOT}/skills/spec-author/templates/phase-spec.md` for the table format.

4. **Wait for operator approval.** The operator may:
   - Say "approve" / "proceed" -> move to auto-complete steps
   - Say "expand US-XX" -> show that story's full detail inline
   - Give specific feedback -> incorporate and re-present summary
5. **On approval**, proceed automatically through Steps 3-4 (file writes, PRD index, architecture, readiness) without further approval gates.

### Step 3 — Write phase spec and update PRD index (auto-proceed)

**Per-phase spec file (primary output):**

Write the full phase specification to `docs/product/phases/<phase-name>.md`. Create the `docs/product/phases/` directory if it doesn't exist. See `${CLAUDE_PLUGIN_ROOT}/skills/spec-author/templates/phase-spec.md` for the file template.

Transfer the approved done-when criteria from `docs/plan/phase-goal-draft.md` into the per-phase spec file. Then delete the draft file. The build-loop's `start` action transposes the done-when criteria into `docs/plan/phase-goal.md`.

**PRD index update (secondary output):**

Update the Implementation Phases table in `docs/product/PRD.md` with a summary row. See `${CLAUDE_PLUGIN_ROOT}/skills/spec-author/templates/phase-spec.md` for the table format.

Do NOT write full stories or done-when criteria inline in the PRD. The PRD is an index only.

**Legacy PRD handling:** If the PRD already contains inline stories from previous phases, leave them in place — the build-loop's Phase Reconciliation Gate will archive them.

**Mark consumed brief:** If this phase was defined from an intent brief in `docs/briefs/`, update the brief's frontmatter `status` from `draft` to `specced`.

**Do not commit.** Leave all changes uncommitted. The build-loop `start` action owns branch management.

### Step 4 — Update architecture intent and confirm readiness (auto-proceed)

Read `docs/architecture/ARCHITECTURE.md` but **do NOT write forward-looking content** to it. Architecture docs describe shipped state only — the build-loop's Phase Reconciliation Gate updates ARCHITECTURE.md after a phase ships.

**Prohibited (compounded — edit-policy-drift):**
- "(planned for `<phase>` phase)" annotations
- "Structural intent" sections for unbuilt phases
- Speculative module names, data flows, or dependency changes

**Instead:** Add a `## AGENTS.md sections affected` heading to the per-phase spec file listing which architecture sections this phase will change when shipped.

Then extract golden principles from `AGENTS.md` that are relevant to this phase's work.

**Identify `AGENTS.md` impact**: Read the project-level `AGENTS.md` and determine which sections this phase will affect when shipped.

**Identify user documentation impact**: Check whether the project has user-facing documentation. If one exists, determine which pages or sections need to be created or updated.

Run the readiness checklist (see `${CLAUDE_PLUGIN_ROOT}/skills/spec-author/templates/phase-spec.md`).

If all checks pass, report:

```
Phase specification ready for build-loop.

Phase: <phase-name>
Stories: <list of US-XX IDs>
Done-when criteria: <count>
Golden principles: <count>

To start: /sabs:build-loop project=<project> action=start phase=<phase>
```

**Do not commit.** The build-loop `start` action will commit spec and architecture changes as part of its phase setup on the correct build branch.

## Amendment mode

When amending existing stories:

1. Locate the target story. Check `docs/product/phases/<phase-name>.md` first (the per-phase spec file). If the story is not in a per-phase file, check `docs/product/PRD.md` for legacy inline stories.
2. Present current acceptance criteria alongside the proposed change.
3. If a story is shipped (`[Shipped]` tag or phase status is `Shipped`), warn that changing shipped criteria may require implementation updates. Suggest a new story unless the change is a spec correction.
4. If done-when criteria for the phase have already been produced, update them to match the amended acceptance criteria. Flag any done-when changes to the user.
5. Write the update to the per-phase file (or PRD if legacy inline). If moving a legacy inline story to a per-phase file during amendment, create the per-phase file and update the PRD index row.
6. If the change affects architecture, update `ARCHITECTURE.md`.
7. **Do not commit.** Leave changes uncommitted for the build-loop to pick up.

## Safety rules

- **Never commit.** Spec-author writes files but does not `git add` or `git commit`. The build-loop `start` action owns all git operations.
- Never remove or overwrite shipped stories without explicit instruction.
- Never modify `AGENTS.md`.
- Never assign a story ID that already exists.
- If the request conflicts with layer rules in AGENTS.md, flag the conflict and propose an alternative.
- The PRD (`docs/product/PRD.md`) is the product index. Per-phase spec files (`docs/product/phases/<phase-name>.md`) hold the detail. Together they are the single source of product truth.
- Done-when criteria are a contract. Once approved and handed to the build-loop, changes require explicit user approval and a note in the phase spec explaining what changed and why.
