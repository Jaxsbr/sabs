# SABS — Semi-Autonomous Build System

## Project type
claude-plugin

## Purpose
A Claude Code plugin that packages a phased engineering workflow for taking features from specification through shipped, reviewed, and compounded code. Agents and humans collaborate: agent drives build and review; human drives spec and approves merge.

## Stack
- Bash skill files (Claude Code plugin format)
- No package.json or build step — skill files are read directly by the Claude Code plugin host
- Tests: Bash scripts in `tests/`

## Directory layout

```
sabs/
├── .claude-plugin/       — Plugin manifest (plugin.json)
├── skills/               — One directory per skill (13 skills)
│   ├── build-loop/       — Main build loop orchestrator
│   ├── build-loop-init/  — Project initialisation
│   ├── build-loop-iterate/ — Phase iteration loop
│   ├── spec-author/      — Writes user stories + done-when criteria
│   ├── phase-goal-review/ — Reviews phase goal before build
│   ├── phase-retro/      — Phase retrospective (failure classification)
│   ├── verify-gate/      — Quality checks runner
│   ├── test-gate/        — Test gate enforcer
│   ├── review-pr/        — PR self-review
│   ├── handle-pr-review/ — PR review response handler
│   ├── regression-detect/ — Regression detection
│   ├── orchestrate/      — Orchestration skill
│   └── frontend-design/  — Frontend design skill
├── config/               — identities.example.json and config templates
├── docs/                 — Reference documentation (portable, project-specific copies live in target project)
│   ├── MANUAL.md         — User manual: workflow overview, idea pipeline, project resolution
│   └── INTEGRATION-TEST-PLAN.md — Integration test scenarios
├── hooks/                — Git hooks (gh-identity-guard)
├── scripts/              — Utility scripts
└── tests/                — Integration tests for the plugin itself
```

## Key Behaviours

- **Project root detection:** `build-loop` (and other skills) detect the target project root by looking for `AGENTS.md` at the cwd. If cwd has no `AGENTS.md`, skills error with "specify project=". This means every sabs-managed project MUST have an `AGENTS.md` at its root — and sabs itself now has this file to document that contract.
- **Portability constraint:** No hardcoded workspace paths anywhere in skills or docs. All paths must resolve relative to the project directory or the plugin directory. The MANUAL.md ships with the plugin as a read-only baseline; new learnings write to the *target project's* `docs/plan/LEARNINGS.md`, not the plugin source.
- **LEARNINGS.md scope filtering:** Each entry in a project's `docs/plan/LEARNINGS.md` carries a `Scope` field — `universal` (all project types) or a domain tag (e.g. `phaser-game`). Skills that consume LEARNINGS.md filter to `universal` + the project's declared type from its `AGENTS.md`. This is why `## Project type` is mandatory in every project's AGENTS.md.
- **Twice-seen rule:** The compound-engineering cycle fixes a failure pattern only after it appears twice across retrospectives, unless it involves data loss or security (those compound immediately). Do not propose compound fixes on first occurrence.
- **No external dependencies:** The plugin must work without npm install or any build step. Skills are plain text consumed directly by Claude Code.
- **Commit policy:** Never push to remote. The operator reviews locally first, then pushes.

## Docs

- [MANUAL.md](docs/MANUAL.md) — User manual: workflow overview, idea pipeline, project resolution
- [INTEGRATION-TEST-PLAN.md](docs/INTEGRATION-TEST-PLAN.md) — Integration test scenarios
