# SABS — Semi-Autonomous Build System

A Claude Code plugin that packages a phased engineering workflow for taking features from specification through shipped, reviewed, and compounded code.

## Why

SABS is an experiment in autonomous software construction. The goal is to map — concretely, through real builds — where AI agents handle software development reliably, where they fail, and which phases of the SDLC can be safely automated next. Compound engineering is how that map gets drawn: every retrospective is a data point, and every prevention fix at the earliest possible point is a step toward more of the lifecycle being delegable.

## What is SABS?

SABS implements a four-stage build cycle:

```
  You drive          Agent drives         Agent + you              Agent drives
+-----------+    +----------------+    +----------------+    +----------------+
|   SPEC    |--->|     BUILD      |--->|    REVIEW      |--->|   COMPOUND     |--+
|           |    |                |    |                |    |                |  |
| Define    |    | Implement tasks|    | Create PR      |    | Phase retro    |  |
| stories,  |    | Investigate-   |    | Self-review    |    | Failure class  |  |
| done-when |    |   first        |    | Fix findings   |    | Twice-seen     |  |
| criteria  |    | Quality gates  |    |                |    |   rule         |  |
|           |    |                |    | YOU: approve +  |    | Compound fixes |  |
|           |    |                |    |      merge     |    |                |  |
+-----------+    +----------------+    +----------------+    +----------------+  |
     ^                                                                          |
     +--------------------------------------------------------------------------+
```

**Your touchpoints:**

1. **Spec** -- define what to build (stories, done-when criteria)
2. **Approve + merge** -- review a PR that has already been self-reviewed and self-fixed
3. **Retro** -- run the phase retrospective before merge (enforced by PR check)

Everything else is agent-driven.

## Philosophy

SABS is built on the principle of **compound engineering**: every phase retrospective identifies failure patterns, and when the same failure class appears twice, a prevention fix is proposed at the earliest possible point in the pipeline. Quality compounds over time -- each phase leaves the system better than it found it.

Key tenets:

- **Investigate-first discipline** -- understand before implementing
- **Observable done-when criteria** -- every criterion must be mechanically verifiable
- **Phase size limits** -- max 5 stories per phase to control rework rates
- **Twice-seen rule** -- compound on pattern confirmation, not isolated incidents (exception: data-loss and security compound immediately)
- **Learnings accumulate** -- each project keeps its own append-only `docs/plan/LEARNINGS.md`, never pruned

## Installation

### Development (local testing)

```bash
claude --plugin-dir /path/to/sabs/
```

This loads the plugin directly from your local directory without installation. Changes take effect immediately.

### Production (installed)

```
/plugin install sabs@<marketplace>
```

Once published to a marketplace, install at user scope for global availability across all projects.

## Prerequisites

- **Claude Code** -- the plugin host environment
- **Git** -- standard git CLI
- **GitHub CLI (`gh`)** -- required for repo creation, branch protection, PR operations (`brew install gh && gh auth login`)

## Current Status

**Version: 0.4.0 -- Portability**

All 13 skills are portable: no hardcoded workspace paths anywhere. The plugin ships a single read-only reference doc — `docs/MANUAL.md` — and nothing else that the runtime writes to. Each project accumulates its own `docs/plan/LEARNINGS.md` from scratch via `phase-retro`; the plugin no longer carries a baseline learnings file.

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Plugin scaffolding and documentation | Complete |
| 2 | Migrate core skills (build-loop, init, iterate) | Complete |
| 3 | Migrate supporting skills (verify-gate, spec-author, etc.) | Complete |
| 4 | Migrate hooks and scripts (gh-identity-guard) | Complete |
| 5 | Integration testing and cutover | Planned |
| 6 | Personal skills migration (non-build commands) | Planned |
| 7 | Distribution and documentation | Planned |

## Skills Index

Skills will be populated as they are migrated from the legacy command system.

| Skill | Invocation | Description | Phase |
|-------|------------|-------------|-------|
| build-loop | `/sabs:build-loop` | Router/dispatcher for the build cycle | 2 |
| build-loop-init | `/sabs:build-loop-init` | Project initialization (7 gates) | 2 |
| build-loop-iterate | `/sabs:build-loop-iterate` | Core iteration loop (Branch A/B) | 2 |
| verify-gate | `/sabs:verify-gate` | Quality gate (static analysis, security, consistency) | 3 |
| test-gate | `/sabs:test-gate` | Full verification stack | 3 |
| regression-detect | `/sabs:regression-detect` | Before/after test regression detection | 3 |
| phase-retro | `/sabs:phase-retro` | Phase retrospective and compounding | 3 |
| review-pr | `/sabs:review-pr` | PR review for correctness, security, design | 3 |
| handle-pr-review | `/sabs:handle-pr-review` | PR review comment triage and fixes | 3 |
| spec-author | `/sabs:spec-author` | Phase specification authoring | 3 |
| phase-goal-review | `/sabs:phase-goal-review` | Phase goal review against learnings | 3 |
| frontend-design | `/sabs:frontend-design` | UI design guidance | 3 |

## Identity Guard

SABS includes a Git identity guard hook that warns you when your local `git user.name` or `git user.email` doesn't match the expected identity for the current repository. This prevents accidental commits under the wrong identity when switching between work, personal, and open-source projects.

### How it Works

The identity guard runs as a **PreToolUse** hook on every Bash tool invocation. It:

1. Reads the current repository's `git remote origin` URL
2. Matches it against patterns in your identity config
3. If your local git identity doesn't match the expected one, outputs a warning with the correct values

### Configuration

Create an identity config file at `${CLAUDE_PLUGIN_DATA}/identities.json` (persistent, user-specific). An example config is provided at `config/identities.example.json`.

```json
{
  "identities": [
    {
      "remote_pattern": "github.com/WorkOrg",
      "user_name": "Your Name",
      "user_email": "you@work.com"
    },
    {
      "remote_pattern": "github.com/PersonalUser",
      "user_name": "Your Name",
      "user_email": "you@personal.com"
    }
  ]
}
```

**Fields:**

- `remote_pattern` -- Substring matched against the git remote origin URL
- `user_name` -- Expected `git config user.name` for matching repositories
- `user_email` -- Expected `git config user.email` for matching repositories

### Safe Defaults

- **No config file:** silent no-op (plugin works without any configuration)
- **No git remote:** silent no-op
- **No matching pattern:** silent no-op
- **Identity matches:** silent pass
- **Identity mismatch:** outputs a warning with expected vs actual values and a fix command

### Config Lookup Order

1. `${CLAUDE_PLUGIN_DATA}/identities.json` -- user-configured, persistent across plugin updates
2. `${CLAUDE_PLUGIN_ROOT}/config/identities.json` -- plugin-bundled fallback

## Documentation

- [MANUAL.md](docs/MANUAL.md) -- Full user manual for the build system workflow
- [CHANGELOG.md](CHANGELOG.md) -- Version history

Each project that uses SABS accumulates its own `docs/plan/LEARNINGS.md` over time, written by `phase-retro` when failure patterns confirm twice-seen.

## Directory Structure

```
sabs/
+-- .claude-plugin/
|   +-- plugin.json              # Plugin manifest
+-- skills/                      # Skill definitions (SKILL.md per skill)
+-- hooks/
|   +-- hooks.json               # Plugin hook configuration
+-- scripts/
|   +-- gh-identity-guard.sh     # Git identity guard (PreToolUse hook)
+-- config/
|   +-- identities.example.json  # Example identity config (copy & customize)
+-- docs/
|   +-- MANUAL.md                # Build system user manual
+-- README.md                    # This file
+-- CHANGELOG.md                 # Version history
```

## License

MIT
