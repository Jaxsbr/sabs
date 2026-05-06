---
name: verify-gate
description: "Quality gate — runs configurable checks against a project's codebase for anti-patterns that functional tests cannot catch"
allowed-tools: "Bash(*) Grep(*) Read(*)"
---

<!-- version: 3 -->
Run configurable quality checks against a project's codebase. Each check scans for anti-patterns that functional tests cannot catch — security holes, silent failures, schema drift, and test quality issues.

**Relationship to standard linters:** These checks are supplementary to AST-based static analysis tools (ruff, eslint, semgrep). The project's `verify` command should already run real linters. Verify-gate checks catch patterns that standard linters miss: AGENTS.md consistency, contract drift, silent test passes, and project-specific invariants. They are heuristic (text-pattern based, not AST-parsed) and may produce false positives — when in doubt, flag and let the operator decide.

## Parameters

- `project` — path to the project root (absolute, or relative to cwd). If omitted, inferred from cwd — cwd must contain a project-level `AGENTS.md`, not the workspace root; error with "specify project=" if not.
- `dry-run` — path to a fixture directory (optional). When provided, run all configured checks against the fixture directory instead of the project root. Useful for testing new checks against known-bad code. Report results but never modify files.

## How it works

1. Resolve the project root (same logic as build-loop).
2. **Always run `root-agents-immutable` first.** This check is non-optional — it runs for every project regardless of the project's `## Quality checks` configuration. If it fails, stop and report the failure immediately.
3. Read the project's `AGENTS.md` and look for a `## Quality checks` section.
4. If the section exists, it lists which checks to run (by check name). Run only those checks.
5. If no `## Quality checks` section exists, report "No quality checks configured for this project. Add a `## Quality checks` section to AGENTS.md to enable them." and stop.
6. If `dry-run` is provided, run checks against the fixture directory instead of the project root. Report results but never modify files.
7. Run each configured check against the target directory.
8. Report results: pass/fail per check, with specific findings (file path, line number, description) for failures.

## AGENTS.md configuration format

Projects opt in to checks by adding a section to their `AGENTS.md`:

```markdown
## Quality checks

- no-silent-pass
- no-bare-except
- no-innerhtml-user-data
- contract-validation
- function-length(50)
```

## Built-in check library

### no-silent-pass

Scans test files for patterns where a test can pass without executing any assertion.

**What to look for:**
- `if condition: return` or `if not condition: return` before any assertion in a test function
- Test functions with zero `assert` statements
- Conditional blocks that skip all assertions

**How to scan:** Read all files matching `test_*.py`, `*_test.py`, `tests/**/*.py`, `**/*.test.ts`, `**/*.spec.ts`. For each test function, check whether every code path contains at least one unconditional assertion.

**Pass criteria:** Every test function contains at least one assertion that executes unconditionally.

### no-bare-except

Scans server/application code for exception swallowing without logging.

**What to look for:**
- `except Exception:` followed by `continue`, `pass`, or `return` without any logging call
- `except:` (bare except) without logging
- `catch (e) { }` or `catch (e) { /* empty */ }` in JS/TS

**How to scan:** Read application source files (exclude test files and vendor directories). Search for except/catch blocks. Verify each block contains a logging call or a re-raise.

**Pass criteria:** Every except/catch block either logs the error or re-raises with context.

### no-innerhtml-user-data

Scans templates and JavaScript for XSS patterns where user-controlled data flows into innerHTML.

**What to look for:**
- `innerHTML =` or `.innerHTML +=` where the right-hand side contains user-controlled data
- Jinja/template variables inside JS string literals without `|tojson` filter
- `document.write()` with user-controlled data
- `.insertAdjacentHTML()` with user-controlled data

**How to scan:** Read all `.html`, `.jinja`, `.js`, `.ts`, `.jsx`, `.tsx` files. Flag any `innerHTML` assignment where the source could be user-controlled.

**Pass criteria:** No innerHTML assignments with user-controlled data. All user content rendered via textContent, programmatic DOM construction, or a sanitization library.

### no-raw-sql

Scans for SQL injection patterns where user input is string-interpolated into queries.

**What to look for:**
- f-strings, `.format()`, or `%` formatting inside SQL query strings
- String concatenation with variables in SQL contexts

**How to scan:** Read application source files. Search for SQL keywords near string interpolation. Parameterized queries are safe.

**Pass criteria:** All SQL queries use parameterized queries or an ORM.

### contract-validation

Verifies that schema/contract files are programmatically loaded and enforced by validation code.

**How to scan:**
1. Find schema files: glob for `schema/*`, `contracts/*`, `*.schema.json`, `*.schema.yaml`.
2. Find validation functions: search for `validate`, `check_schema`, or similar.
3. Verify the validation function imports/loads the schema file.
4. Check that all schema file references in `AGENTS.md` point to files that exist.

**Pass criteria:** Every schema file is loaded by at least one validation function. No phantom references.

### agents-consistency

Checks that rules stated in `AGENTS.md` are actually enforced in code.

**How to scan:**
1. Read `AGENTS.md` and extract all rules from "invariants", "non-negotiable", "edit policy", "layer rules" sections.
2. For each rule, determine what code it describes.
3. Verify the code matches the description.

**Pass criteria:** Every non-negotiable rule has corresponding enforcement that matches the documented behavior.

### function-length(N)

Flags functions exceeding N lines (default 50). Excludes blank lines and comments from the count.

**Pass criteria:** No function exceeds the configured line limit.

### error-path-coverage

Verifies that API endpoints have error-path tests.

**How to scan:**
1. Find all route definitions in the application.
2. For each route, search test files for tests asserting error status codes.
3. Flag routes with zero error-path test coverage.

**Pass criteria:** Every route has at least one test asserting an error status code.

### fetch-status-check

Scans JS/TS for fetch calls that skip status checking.

**What to look for:** `fetch().then(r => r.json())` without checking `r.ok` first.

**Pass criteria:** Every fetch call checks `response.ok` or `response.status` before parsing the body.

### no-secrets-in-commit

Scans all tracked files for accidentally committed secrets or credentials. **This check is a hard blocker** — if secrets are detected, the build-loop must pause and require operator intervention before proceeding. Secrets findings cannot be suppressed without explicit operator override.

**What to look for:**
- Files named `.env*`, `credentials*`, `*.key`, `*.pem`
- File content containing patterns: `API_KEY=`, `SECRET=`, `-----BEGIN.*PRIVATE KEY-----`, `sk-`, `ghp_`, `aws_secret_access_key`
- Base64-encoded secret patterns: long base64 strings (40+ characters) adjacent to key/secret/token assignment patterns

**How to scan:**
1. List all tracked files: `git ls-files`.
2. Check file names against secret file patterns (`.env*`, `credentials*`, `*.key`, `*.pem`).
3. Verify `.gitignore` includes standard secret file patterns (`.env*`, `*.key`, `*.pem`, `credentials*`). Flag if these patterns are missing from `.gitignore`.
4. Search file contents for secret value patterns using grep/ripgrep.
5. Exclude false positives in documentation, test fixtures with dummy values, and `.gitignore` itself.

**Pass criteria:** No tracked files match secret file name patterns, no tracked file contents contain secret value patterns, and `.gitignore` covers standard secret file patterns.

**Limitations:** Base64-encoded secrets and secrets split across multiple lines may evade text-pattern detection. For higher assurance, consider a dedicated secrets scanner (e.g., truffleHog, detect-secrets).

### token-consumer-check

Verifies that all CSS token references (`var(--lense-*`) point to tokens that actually exist in `tokens.css`.

**What to look for:**
- CSS files referencing `var(--lense-<name>)` where `--lense-<name>` is not defined in any `:root` block in `tokens.css`
- Token renames that leave stale references in consumer CSS files

**How to scan:**
1. Find the token definition file (glob for `**/tokens.css`).
2. Extract all `--lense-*` variable names from `:root` blocks.
3. Scan all `.css` files under `src/` for `var(--lense-` references.
4. For each reference, verify the token name exists in the extracted definitions.

**Pass criteria:** Every `var(--lense-*)` reference in CSS files points to a token defined in `tokens.css` `:root`.

**When to run:** Only when the project has a `tokens.css` file. Skip silently otherwise.

### e2e-route-coverage

Verifies that Playwright `page.route()` glob patterns cover sub-path routes (`:id` parameters), not just query-parameter variants.

**What to look for:**
- `page.route('**/api/<resource>*', ...)` patterns where the trailing `*` (single star) cannot match sub-paths like `/<resource>/:id` because glob `*` does not cross `/` boundaries
- The fix is `**` (double star) suffix: `**/api/<resource>**`

**How to scan:**
1. Find all E2E test files (glob for `e2e/**/*.spec.ts`, `e2e/**/*.test.ts`).
2. Search for `page.route(` calls with glob string arguments.
3. For each glob, check if it ends with a single `*` after a resource path segment (e.g., `/api/records*`). If so, check whether the test file also exercises requests to sub-paths of that resource (e.g., PUT, DELETE, or GET with `/:id`).
4. If sub-path requests exist but the glob only uses single `*`, flag: the mock silently fails to intercept individual-resource operations.

**Pass criteria:** Every `page.route()` glob that mocks a REST resource also covers sub-path routes (`:id`), either via `**` suffix or a separate route registration.

**When to run:** Only when the project has E2E test files with `page.route()` calls. Skip silently otherwise.

### root-agents-immutable

Verifies the root workspace AGENTS.md has not been modified. **This check is non-optional** — it always runs for every project regardless of the project's `## Quality checks` configuration (see "How it works" step 2).

**How to scan:**
1. Read the project's root `AGENTS.md` (the workspace root charter, resolved relative to the project's workspace).
2. Compute its SHA-256 hash: `shasum -a 256 <path-to-root-AGENTS.md>`.
3. Compare against the known-good hash stored in the project's build-system hash file.
4. If the hashes don't match, flag as FAIL with the expected and actual hash values.

**Pass criteria:** Root AGENTS.md SHA-256 hash matches the stored reference hash.

**Hash file maintenance:** To create or update the reference hash (requires operator approval since it reflects a new AGENTS.md version):
```bash
shasum -a 256 <path-to-root-AGENTS.md> | awk '{print $1}' > <path-to-hash-file>
```

## Output format

```
## Verify Gate Results — <project>

Checks run: N
Passed: N
Failed: N

### PASS: <check-name>
### FAIL: <check-name>
- `file:line` — description of finding
```

## Integration with build-loop

The build-loop's quality checks step (Branch A, step 5) calls this gate. If any check fails, the build-loop treats it as a verify failure — does not commit and queues a fix task.

When run standalone (`/sabs:verify-gate project=<path>`), the gate reports results but does not modify any files.

## GitHub permission requirements

Verify-gate itself is read-only (uses `git ls-files` for `no-secrets-in-commit`). However, the build-loop init should validate that the GitHub token has the scopes needed for the full build cycle:

| Scope | Required by |
|---|---|
| `repo` | verify-gate (`git ls-files`), build-loop (commit, push), review-pr (create PR, post comments) |
| `workflow` | CI management (workflow dispatch, status checks) |
| `actions:read` | phase-retro CI check (read workflow status) |

The build-loop init Gate 3 should inspect token scopes and report missing permissions with actionable suggestions before starting a phase.

## Version requirements

This skill uses an HTML comment version tag (`<!-- version: N -->`). The build-loop init should read each skill's version field and compare against the minimum versions listed in the MANUAL. If a skill version is below the required minimum, init should fail with a message identifying which skill needs updating.
