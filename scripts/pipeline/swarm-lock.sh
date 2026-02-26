#!/usr/bin/env bash
# swarm-lock.sh — Dev Swarm File Ownership Coordination
#
# Usage:
#   scripts/pipeline/swarm-lock.sh claim <agent-name> "<file1> <file2> ..."
#   scripts/pipeline/swarm-lock.sh check "<file>"
#   scripts/pipeline/swarm-lock.sh release <agent-name>
#
# Lock state is stored as a "<!-- swarm-lock -->" comment on the GitHub Issue.
# Requires: ISSUE_NUMBER and GITHUB_REPO environment variables (source config.sh first).
#
# Must be POSIX-compatible (bash 3.2+)

set -eu

COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  echo "Usage: swarm-lock.sh <claim|check|release> [args...]" >&2
  echo "  claim  <agent-name> \"<file1> <file2> ...\"" >&2
  echo "  check  \"<file>\"" >&2
  echo "  release <agent-name>" >&2
  exit 1
fi

# Validate required environment variables
if [ -z "${ISSUE_NUMBER:-}" ]; then
  echo "ERROR: swarm-lock.sh requires ISSUE_NUMBER to be set (source .claude/config.sh)" >&2
  exit 1
fi

if [ -z "${GITHUB_REPO:-}" ]; then
  echo "ERROR: swarm-lock.sh requires GITHUB_REPO to be set (source .claude/config.sh)" >&2
  exit 1
fi

LOCK_MARKER="swarm-lock"

# --- Helper: fetch current lock comment from GitHub Issue ---
# Returns: JSON of the comment or empty string if none found
_get_lock_comment() {
  local comments_json
  comments_json=$(gh api "repos/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments" 2>/dev/null) || {
    echo "ERROR: swarm-lock.sh — failed to fetch comments from GitHub" >&2
    return 1
  }

  # Find the comment containing the swarm-lock marker
  echo "$comments_json" | jq -c "[.[] | select(.body | test(\"$LOCK_MARKER\"))] | last // empty" 2>/dev/null
}

# --- Helper: get comment ID from lock comment JSON ---
_get_comment_id() {
  echo "$1" | jq -r '.id // empty' 2>/dev/null
}

# --- Helper: get comment body from lock comment JSON ---
_get_comment_body() {
  echo "$1" | jq -r '.body // empty' 2>/dev/null
}

# --- Helper: create new lock comment ---
_create_lock_comment() {
  local body="$1"
  gh api -X POST "repos/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments" \
    -f body="$body" \
    --jq '.id' 2>/dev/null
}

# --- Helper: update existing lock comment ---
_update_lock_comment() {
  local comment_id="$1"
  local body="$2"
  gh api -X PATCH "repos/$GITHUB_REPO/issues/comments/$comment_id" \
    -f body="$body" \
    --jq '.id' 2>/dev/null
}

# --- CLAIM command ---
# Usage: swarm-lock.sh claim <agent-name> "<files>"
_cmd_claim() {
  local agent_name="${1:-}"
  local files="${2:-}"

  if [ -z "$agent_name" ] || [ -z "$files" ]; then
    echo "ERROR: claim requires: swarm-lock.sh claim <agent-name> \"<file1> <file2>...\"" >&2
    exit 1
  fi

  local lock_comment
  lock_comment=$(_get_lock_comment) || exit 1

  local comment_id
  local current_body

  if [ -n "$lock_comment" ]; then
    comment_id=$(_get_comment_id "$lock_comment")
    current_body=$(_get_comment_body "$lock_comment")
  else
    comment_id=""
    current_body="<!-- $LOCK_MARKER -->
## Swarm Lock State

"
  fi

  # Add entry for this agent
  local entry
  entry="CLAIMED by $agent_name: $files"

  # Remove any existing claim by this agent (idempotent)
  local new_body
  new_body=$(echo "$current_body" | grep -v "CLAIMED by $agent_name:" || true)
  new_body="$new_body
$entry"

  if [ -n "$comment_id" ]; then
    _update_lock_comment "$comment_id" "$new_body" >/dev/null
  else
    _create_lock_comment "$new_body" >/dev/null
  fi

  echo "CLAIMED: $agent_name has claimed: $files"
}

# --- CHECK command ---
# Usage: swarm-lock.sh check "<file>"
_cmd_check() {
  local file="${1:-}"

  if [ -z "$file" ]; then
    echo "ERROR: check requires: swarm-lock.sh check \"<file>\"" >&2
    exit 1
  fi

  local lock_comment
  lock_comment=$(_get_lock_comment) || exit 1

  if [ -z "$lock_comment" ]; then
    echo "FREE"
    return 0
  fi

  local body
  body=$(_get_comment_body "$lock_comment")

  # Look for a claim line that contains this file
  local claim_line
  claim_line=$(echo "$body" | grep "CLAIMED by" | grep "$file" | head -1 || true)

  if [ -n "$claim_line" ]; then
    # Extract agent name from "CLAIMED by <agent>: <files>"
    local agent
    agent=$(echo "$claim_line" | sed 's/CLAIMED by \([^:]*\):.*/\1/' | xargs)
    echo "CLAIMED by $agent"
  else
    echo "FREE"
  fi
}

# --- RELEASE command ---
# Usage: swarm-lock.sh release <agent-name>
_cmd_release() {
  local agent_name="${1:-}"

  if [ -z "$agent_name" ]; then
    echo "ERROR: release requires: swarm-lock.sh release <agent-name>" >&2
    exit 1
  fi

  local lock_comment
  lock_comment=$(_get_lock_comment) || exit 1

  if [ -z "$lock_comment" ]; then
    echo "RELEASED: no lock comment found (nothing to release)"
    return 0
  fi

  local comment_id
  local current_body
  comment_id=$(_get_comment_id "$lock_comment")
  current_body=$(_get_comment_body "$lock_comment")

  # Remove all claim lines for this agent
  local new_body
  new_body=$(echo "$current_body" | grep -v "CLAIMED by $agent_name:" || true)

  _update_lock_comment "$comment_id" "$new_body" >/dev/null

  echo "RELEASED: $agent_name's claims have been removed"
}

# --- Dispatch command ---
case "$COMMAND" in
  claim)
    _cmd_claim "${2:-}" "${3:-}"
    ;;
  check)
    _cmd_check "${2:-}"
    ;;
  release)
    _cmd_release "${2:-}"
    ;;
  *)
    echo "ERROR: unknown command '$COMMAND'. Use: claim, check, or release" >&2
    exit 1
    ;;
esac
