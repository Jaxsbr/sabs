# Changelog

All notable changes to the SABS plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Automated regression test runner** (`tests/run-integration-tests.sh`) -- self-contained bash script that validates the entire SABS plugin end-to-end. Three tiers: structural (free), skill invocation (`claude -p`), and full build-loop cycle. Designed as a pre-release gate, not CI.
- **Test fixtures** (`tests/fixtures/`) -- regression-detect baselines, identity guard test configs, minimal AGENTS.md for test projects.
- **Test suite documentation** (`tests/README.md`) -- usage, cost expectations, tier descriptions, maintenance notes.

### Removed

- **Plugin-shipped LEARNINGS.md baseline** -- the plugin no longer ships any pre-populated learnings. Each project now accumulates its own `docs/plan/LEARNINGS.md` from scratch via `phase-retro`. The 10 built-in failure-pattern dimensions in `phase-goal-review` continue to apply to every project; project-local learnings layer on top.

### Changed

- `phase-goal-review` reads only the project-local LEARNINGS.md (skips gracefully when absent). Citations in built-in dimensions reference the failure class name rather than a learning number.
- `spec-author`, `phase-retro`, and `build-loop` updated to drop references to a plugin-shipped baseline learnings file.

## [0.4.0] - 2026-04-10

### Changed

- **LEARNINGS.md portability** -- new learnings are now written to project-local `docs/plan/LEARNINGS.md` instead of the plugin-shipped file. The plugin's `docs/LEARNINGS.md` is now read-only baseline reference. Skills that read learnings (phase-goal-review, spec-author) merge both sources. Skills that write learnings (phase-retro) write only to the project-local file, creating it on first run if it doesn't exist.
- **Compounding fix allowlist narrowed** -- removed `${CLAUDE_PLUGIN_ROOT}/docs/LEARNINGS.md` and `${CLAUDE_PLUGIN_ROOT}/docs/MANUAL.md` from the allowlist in build-loop router and phase-retro. Only `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` remains on the allowlist.
- **MANUAL.md portability** -- removed all `~/dev/` hardcoded paths, Cursor-specific references, and `.claude/commands/` references. Project resolution now uses generic absolute/relative path resolution. Skill reference table updated to use `/sabs:<name>` invocations. Command examples use generic paths instead of `~/dev/`.
- **phase-goal-review reads both learnings sources** -- reads plugin baseline first, then project-local file (graceful skip if missing on first run). Merges both into a single list for review.
- **build-loop reference.md updated** -- distinguishes plugin-shipped (read-only) from project-generated (created at runtime) files.

### Design Decisions

- LEARNINGS.md split into two tiers: plugin-shipped baseline (read-only, contains historical learnings) and project-local (created on first write, specific to each project). This makes the plugin portable -- a fresh install works without any pre-existing files.
- Plugin-shipped LEARNINGS.md is NOT modified by the plugin -- it is a snapshot of learnings accumulated during development. New learnings always go to the project directory.
- MANUAL.md and LEARNINGS.md in `docs/` remain as plugin-shipped reference material but are never written to at runtime.
- The `.cursor/skills/` and `.claude/commands/` references in MANUAL.md are replaced with `/sabs:<name>` plugin invocations since SABS is now a standalone Claude Code plugin.
- Historical entries in LEARNINGS.md that reference `~/dev/` paths are preserved as-is (append-only log, historical accuracy matters).

## [0.3.0] - 2026-04-10

### Added

- Output directory awareness for project initialization -- `init` now presents the resolved path and asks the operator to confirm or provide an alternative before creating the project directory
- Operator can override the default directory at init time without needing to restart

### Changed

- Updated "Resolve project root" in build-loop router (v12 -> v13) to include confirmation step for `init` action
- Updated build-loop-init to remove "do not ask" language and align with the confirmation flow
- Updated orchestrate skill to clarify that directory confirmation only applies to `init`

### Design Decisions

- Directory confirmation is limited to the `init` action only -- all other actions operate on existing directories and do not need confirmation
- The default path remains `<cwd>/<project-name>` (resolved from the `project` parameter) -- the confirmation step adds safety without changing the default behavior for users who confirm immediately
- Skills that say "same logic as build-loop" (phase-retro, verify-gate, test-gate, phase-goal-review) inherit the change automatically since they reference the router's resolution logic and none of them create directories

## [0.2.0] - 2026-04-10

### Added

- Identity guard hook script (`scripts/gh-identity-guard.sh`) -- generic, config-driven Git identity verification
- Hook configuration (`hooks/hooks.json`) -- PreToolUse hook wiring for identity guard on Bash tool
- Example identity config (`config/identities.example.json`) -- documented template for user customization
- Identity Guard section in README with configuration guide and safe default behavior

### Changed

- Updated plugin status to reflect Phases 1-4 complete
- Updated README directory structure to include hooks, scripts, and config

### Design Decisions

- Identity guard is config-driven via JSON -- no hardcoded identities
- Config lookup: `${CLAUDE_PLUGIN_DATA}/identities.json` first, then `${CLAUDE_PLUGIN_ROOT}/config/identities.json` as fallback
- All failure modes default to silent no-op (no config, no remote, no match)
- Mismatch produces a warning with fix command but does not block execution

## [0.1.0] - 2026-04-10

### Added

- Plugin directory structure (`.claude-plugin/`, `skills/`, `hooks/`, `scripts/`, `docs/`)
- Plugin manifest (`plugin.json`) with name, version, author, and metadata
- Documentation: copied MANUAL.md (build system user manual) from legacy location
- Documentation: copied LEARNINGS.md (compound engineering learnings log) from legacy location
- README.md with plugin overview, installation instructions, philosophy, status, and skills index
- This changelog

### Notes

- This is a scaffolding-only release. No skills, hooks, or scripts have been migrated yet.
- The build system continues to operate from `~/dev/.claude/commands/` until skills are migrated in Phase 2.
- Cursor skills/rules are excluded per owner decision.
- LEARNINGS.md location will be user-configurable in a future phase.
