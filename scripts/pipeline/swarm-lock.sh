#!/usr/bin/env bash
# swarm-lock.sh — Dev Swarm File Ownership Coordination
#
# Usage:
#   scripts/pipeline/swarm-lock.sh claim   <agent-name> "<file1> <file2> ..."
#   scripts/pipeline/swarm-lock.sh check   "<file>"
#   scripts/pipeline/swarm-lock.sh verify  <agent-name> "<file1> <file2> ..."
#   scripts/pipeline/swarm-lock.sh release <agent-name>
#   scripts/pipeline/swarm-lock.sh list
#
# CONCURRENCY MODEL
# -----------------
# Each agent has its own GitHub Issue comment, identified by the per-agent
# marker <!-- swarm-lock:AGENT_NAME -->. Agents only write to their own
# comment, so write-write conflicts between parallel agents are impossible
# at the API level.
#
# File ownership disputes (two agents claiming the same file simultaneously)
# are resolved by the TIMESTAMP embedded in each agent's comment: the most
# recent claim wins. Comment ID is used as a tiebreaker.
#
# After claiming, always call `verify` to confirm ownership before
# starting implementation. `verify` waits SWARM_VERIFY_WAIT seconds
# (default 3) so any concurrent claims have time to arrive, then re-fetches
# all claims and confirms this agent is the winner for every file.
#
# Requires: ISSUE_NUMBER and GITHUB_REPO (source .claude/config.sh first).
# Must be POSIX-compatible (bash 3.2+).

set -eu

COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  echo "Usage: swarm-lock.sh <claim|check|verify|release|list> [args...]" >&2
  echo "  claim   <agent> \"<file1> <file2> ...\"" >&2
  echo "  check   \"<file>\"" >&2
  echo "  verify  <agent> \"<file1> <file2> ...\"" >&2
  echo "  release <agent>" >&2
  echo "  list" >&2
  exit 1
fi

if [ -z "${ISSUE_NUMBER:-}" ]; then
  echo "ERROR: swarm-lock.sh requires ISSUE_NUMBER (source .claude/config.sh)" >&2
  exit 1
fi
if [ -z "${GITHUB_REPO:-}" ]; then
  echo "ERROR: swarm-lock.sh requires GITHUB_REPO (source .claude/config.sh)" >&2
  exit 1
fi

# Seconds verify() waits before re-fetching to detect concurrent claims.
SWARM_VERIFY_WAIT="${SWARM_VERIFY_WAIT:-3}"

# Comment body prefix: <!-- swarm-lock:AGENT_NAME -->
LOCK_PREFIX='<!-- swarm-lock:'

# ── Helpers ───────────────────────────────────────────────────────────────────

# Fetch all swarm-lock claim comments for this issue, sorted by comment ID.
# Returns a JSON array. Each element has .id and .body.
_get_all_claims() {
  local raw
  raw=$(gh api "repos/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments" 2>/dev/null) || {
    echo "ERROR: failed to fetch issue comments from GitHub" >&2
    return 1
  }
  # Use test() not startswith() to avoid any bash ! expansion edge cases
  printf '%s' "$raw" | jq -c \
    '[.[] | select(.body | test("^<!-- swarm-lock:[^>]+ -->"))] | sort_by(.id)' \
    2>/dev/null
}

# Get this agent's own claim comment object. Returns empty JSON if none found.
_get_own_comment() {
  local agent="$1"
  local all
  all=$(_get_all_claims) || return 1
  # The first line of the body is exactly: <!-- swarm-lock:AGENT_NAME -->
  printf '%s' "$all" | jq -c \
    --arg prefix "${LOCK_PREFIX}${agent} -->" \
    '[.[] | select(.body | startswith($prefix))] | last // empty' \
    2>/dev/null
}

# Extract the TIMESTAMP value from a comment body. Returns "0" if absent.
_parse_ts() {
  printf '%s' "$1" | grep '^TIMESTAMP:' | head -1 | \
    sed 's/TIMESTAMP:[[:space:]]*//' | tr -d '\r\n' | \
    grep -E '^[0-9]+$' || printf '0'
}

# Extract the space-separated CLAIMED file list from a comment body.
_parse_files() {
  printf '%s' "$1" | grep '^CLAIMED:' | head -1 | \
    sed 's/CLAIMED:[[:space:]]*//' | tr -d '\r'
}

# Extract the agent name from the first line of a comment body.
_parse_agent() {
  printf '%s' "$1" | head -1 | \
    sed 's/^<!-- swarm-lock://' | sed 's/ -->.*//' | tr -d '\r\n'
}

# ── CLAIM ────────────────────────────────────────────────────────────────────
# Write this agent's claim comment. Each agent has exactly one claim comment;
# re-claiming updates it in place (fresh timestamp, updated file list).
# There are NO write conflicts between agents since each writes only its own.

_cmd_claim() {
  local agent="${1:-}"
  local files="${2:-}"

  if [ -z "$agent" ] || [ -z "$files" ]; then
    echo "ERROR: usage: swarm-lock.sh claim <agent> \"<file1> <file2>...\"" >&2
    exit 1
  fi

  local ts
  ts=$(date +%s)

  local body
  body="${LOCK_PREFIX}${agent} -->
TIMESTAMP: ${ts}
CLAIMED: ${files}"

  # Upsert: update existing comment if found, otherwise create.
  local existing
  existing=$(_get_own_comment "$agent") || existing=""
  local comment_id
  comment_id=$(printf '%s' "$existing" | jq -r '.id // empty' 2>/dev/null || printf '')

  if [ -n "$comment_id" ]; then
    gh api -X PATCH "repos/$GITHUB_REPO/issues/comments/$comment_id" \
      -f body="$body" --jq '.id' >/dev/null
  else
    gh api -X POST "repos/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments" \
      -f body="$body" --jq '.id' >/dev/null
  fi

  echo "CLAIMED: $agent → $files"
  echo "(call verify to confirm ownership before starting work)"
}

# ── CHECK ────────────────────────────────────────────────────────────────────
# Return the current owner of a file. Reads ALL per-agent claim comments and
# picks the agent with the highest TIMESTAMP (comment ID as tiebreaker).
# This gives a consistent, deterministic winner when two agents have claimed
# the same file.

_cmd_check() {
  local file="${1:-}"
  if [ -z "$file" ]; then
    echo "ERROR: usage: swarm-lock.sh check \"<file>\"" >&2
    exit 1
  fi

  local all
  all=$(_get_all_claims) || { printf 'FREE\n'; return 0; }

  if [ -z "$all" ] || [ "$all" = '[]' ] || [ "$all" = 'null' ]; then
    printf 'FREE\n'
    return 0
  fi

  local winner=""
  local winner_ts=0
  local winner_cid=0

  local count
  count=$(printf '%s' "$all" | jq 'length')
  local i=0
  while [ "$i" -lt "$count" ]; do
    local entry body claimed_files ts agent cid
    entry=$(printf '%s' "$all" | jq -c ".[$i]")
    body=$(printf '%s' "$entry" | jq -r '.body' 2>/dev/null || true)
    cid=$(printf '%s' "$entry" | jq -r '.id' 2>/dev/null || printf '0')
    claimed_files=$(_parse_files "$body")
    ts=$(_parse_ts "$body")
    agent=$(_parse_agent "$body")

    for f in $claimed_files; do
      if [ "$f" = "$file" ]; then
        # Higher timestamp wins; use comment ID as tiebreaker for exact ties.
        if [ "${ts:-0}" -gt "$winner_ts" ] || \
           { [ "${ts:-0}" -eq "$winner_ts" ] && [ "${cid:-0}" -gt "$winner_cid" ]; }; then
          winner="$agent"
          winner_ts="${ts:-0}"
          winner_cid="${cid:-0}"
        fi
        break
      fi
    done

    i=$((i + 1))
  done

  if [ -n "$winner" ]; then
    printf 'CLAIMED by %s\n' "$winner"
  else
    printf 'FREE\n'
  fi
}

# ── VERIFY ───────────────────────────────────────────────────────────────────
# Confirm this agent won the claim race for all its files.
# Waits SWARM_VERIFY_WAIT seconds so concurrent claims have time to arrive,
# then calls check() for each file. If another agent has a newer claim on
# any file, reports CONTESTED and exits 1 so the caller can handle it.
#
# Call this after `claim`, not instead of it:
#   swarm-lock.sh claim  "$AGENT" "file1 file2"
#   swarm-lock.sh verify "$AGENT" "file1 file2"  # confirms ownership

_cmd_verify() {
  local agent="${1:-}"
  local files="${2:-}"

  if [ -z "$agent" ] || [ -z "$files" ]; then
    echo "ERROR: usage: swarm-lock.sh verify <agent> \"<file1> <file2>...\"" >&2
    exit 1
  fi

  printf 'Waiting %ss for concurrent claims to arrive...\n' "$SWARM_VERIFY_WAIT"
  sleep "$SWARM_VERIFY_WAIT"

  local contested=0
  for file in $files; do
    local owner
    owner=$(_cmd_check "$file")
    if [ "$owner" = "CLAIMED by $agent" ]; then
      : # this agent is the winner
    else
      printf 'CONTESTED: %s — %s\n' "$file" "$owner"
      contested=$((contested + 1))
    fi
  done

  if [ "$contested" -eq 0 ]; then
    printf 'CONFIRMED: %s owns all claimed files\n' "$agent"
    return 0
  else
    printf 'CONTESTED: %d file(s) not owned by %s — see above\n' "$contested" "$agent"
    return 1
  fi
}

# ── RELEASE ─────────────────────────────────────────────────────────────────
# Delete this agent's claim comment. Called after the agent's files are
# committed and pushed so dependent agents can proceed.

_cmd_release() {
  local agent="${1:-}"
  if [ -z "$agent" ]; then
    echo "ERROR: usage: swarm-lock.sh release <agent>" >&2
    exit 1
  fi

  local existing
  existing=$(_get_own_comment "$agent") || existing=""
  local comment_id
  comment_id=$(printf '%s' "$existing" | jq -r '.id // empty' 2>/dev/null || printf '')

  if [ -z "$comment_id" ]; then
    printf 'RELEASED: no claim comment found for %s\n' "$agent"
    return 0
  fi

  gh api -X DELETE "repos/$GITHUB_REPO/issues/comments/$comment_id" 2>/dev/null || true
  printf 'RELEASED: %s claim comment deleted\n' "$agent"
}

# ── LIST ─────────────────────────────────────────────────────────────────────
# Print a human-readable summary of all current claims. Useful for debugging.

_cmd_list() {
  local all
  all=$(_get_all_claims) || { printf '(failed to fetch claims)\n'; return 1; }

  if [ -z "$all" ] || [ "$all" = '[]' ] || [ "$all" = 'null' ]; then
    printf '(no active claims)\n'
    return 0
  fi

  printf 'Current swarm lock state:\n'
  local count i=0
  count=$(printf '%s' "$all" | jq 'length')
  while [ "$i" -lt "$count" ]; do
    local body agent files ts
    body=$(printf '%s' "$all" | jq -r ".[$i].body" 2>/dev/null || true)
    agent=$(_parse_agent "$body")
    files=$(_parse_files "$body")
    ts=$(_parse_ts "$body")
    printf '  %-20s (ts=%s): %s\n' "$agent" "$ts" "$files"
    i=$((i + 1))
  done
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
case "$COMMAND" in
  claim)   _cmd_claim   "${2:-}" "${3:-}" ;;
  check)   _cmd_check   "${2:-}" ;;
  verify)  _cmd_verify  "${2:-}" "${3:-}" ;;
  release) _cmd_release "${2:-}" ;;
  list)    _cmd_list ;;
  *)
    echo "ERROR: unknown command '$COMMAND'. Use: claim, check, verify, release, list" >&2
    exit 1
    ;;
esac
