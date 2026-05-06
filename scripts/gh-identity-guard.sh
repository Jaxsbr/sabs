#!/bin/bash
# gh-identity-guard.sh
# Claude Code PreToolUse hook — warns when git identity doesn't match expected
# config for the current repository's remote.
#
# Config-driven: reads identity mappings from a JSON config file.
# Safe defaults: no config = no-op, no matching remote = no-op.
#
# Config locations (checked in order):
#   1. ${CLAUDE_PLUGIN_DATA}/identities.json  (user-configured, persistent)
#   2. ${CLAUDE_PLUGIN_ROOT}/config/identities.json  (plugin default)

# Ensure common tools are on PATH (hooks run in a bare shell without user profile)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# --- Read hook input from stdin ---
INPUT=$(cat)

# --- Locate config file ---
CONFIG_FILE=""
if [ -n "$CLAUDE_PLUGIN_DATA" ] && [ -f "${CLAUDE_PLUGIN_DATA}/identities.json" ]; then
  CONFIG_FILE="${CLAUDE_PLUGIN_DATA}/identities.json"
elif [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/config/identities.json" ]; then
  CONFIG_FILE="${CLAUDE_PLUGIN_ROOT}/config/identities.json"
fi

# No config file: silent no-op
[ -z "$CONFIG_FILE" ] && exit 0

# Validate that jq is available (needed to parse config and hook input)
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- Determine working directory ---
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"

# --- Get git remote origin URL ---
REMOTE_URL=$(git -C "$CWD" remote get-url origin 2>/dev/null)

# No git remote: silent no-op
[ -z "$REMOTE_URL" ] && exit 0

# --- Load identities from config ---
IDENTITIES=$(jq -r '.identities' "$CONFIG_FILE" 2>/dev/null)

# No identities array or invalid config: silent no-op
[ -z "$IDENTITIES" ] || [ "$IDENTITIES" = "null" ] && exit 0

# --- Find matching identity ---
MATCH_INDEX=-1
IDENTITY_COUNT=$(echo "$IDENTITIES" | jq -r 'length' 2>/dev/null)
[ -z "$IDENTITY_COUNT" ] || [ "$IDENTITY_COUNT" = "0" ] && exit 0

for (( i=0; i<IDENTITY_COUNT; i++ )); do
  PATTERN=$(echo "$IDENTITIES" | jq -r ".[$i].remote_pattern // empty" 2>/dev/null)
  if [ -n "$PATTERN" ] && [[ "$REMOTE_URL" == *"$PATTERN"* ]]; then
    MATCH_INDEX=$i
    break
  fi
done

# No matching pattern: silent no-op
[ "$MATCH_INDEX" -eq -1 ] && exit 0

# --- Extract expected identity ---
EXPECTED_NAME=$(echo "$IDENTITIES" | jq -r ".[$MATCH_INDEX].user_name // empty" 2>/dev/null)
EXPECTED_EMAIL=$(echo "$IDENTITIES" | jq -r ".[$MATCH_INDEX].user_email // empty" 2>/dev/null)

# Nothing to check if neither name nor email configured
[ -z "$EXPECTED_NAME" ] && [ -z "$EXPECTED_EMAIL" ] && exit 0

# --- Get current git identity ---
ACTUAL_NAME=$(git -C "$CWD" config user.name 2>/dev/null)
ACTUAL_EMAIL=$(git -C "$CWD" config user.email 2>/dev/null)

# --- Compare ---
MISMATCH=""

if [ -n "$EXPECTED_NAME" ] && [ "$ACTUAL_NAME" != "$EXPECTED_NAME" ]; then
  MISMATCH="user.name: expected '${EXPECTED_NAME}', got '${ACTUAL_NAME:-<not set>}'"
fi

if [ -n "$EXPECTED_EMAIL" ] && [ "$ACTUAL_EMAIL" != "$EXPECTED_EMAIL" ]; then
  if [ -n "$MISMATCH" ]; then
    MISMATCH="${MISMATCH}; user.email: expected '${EXPECTED_EMAIL}', got '${ACTUAL_EMAIL:-<not set>}'"
  else
    MISMATCH="user.email: expected '${EXPECTED_EMAIL}', got '${ACTUAL_EMAIL:-<not set>}'"
  fi
fi

# Identity matches: silent pass
[ -z "$MISMATCH" ] && exit 0

# --- Identity mismatch: output warning ---
MATCHED_PATTERN=$(echo "$IDENTITIES" | jq -r ".[$MATCH_INDEX].remote_pattern // empty" 2>/dev/null)

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "gh-identity-guard: Git identity mismatch for remote matching '${MATCHED_PATTERN}'. ${MISMATCH}. Fix with: git config user.name '${EXPECTED_NAME}' && git config user.email '${EXPECTED_EMAIL}'"
  }
}
EOF

exit 0
