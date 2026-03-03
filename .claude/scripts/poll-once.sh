#!/usr/bin/env bash
# .claude/scripts/poll-once.sh
#
# Single poll: scans GitHub Project board and labels for actionable issues.
# Prints a JSON object to stdout.
#
# Exit codes (bitmask — any combination is valid):
#   0 — nothing actionable found
#   1 — ready issues found          (start pipeline)
#   2 — approved issues found       (resume pipeline after human approval)
#   4 — intake-resumed issues found (human replied to clarifying questions)
#   (e.g. 3 = ready + approved, 5 = ready + intake-resumed, etc.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/.claude/config.sh"

# --- Helper: ensure a variable holds valid JSON, default to fallback if not ---
ensure_json() {
  local val="$1" fallback="$2"
  # Empty string or whitespace-only → use fallback
  if [ -z "${val// /}" ]; then
    printf '%s' "$fallback"
    return
  fi
  # Check it parses as valid JSON
  if printf '%s' "$val" | jq 'empty' 2>/dev/null; then
    printf '%s' "$val"
  else
    printf '%s' "$fallback"
  fi
}

# --- Fetch project board once (avoids 3× rate-limit cost) ---
BOARD_ERR_FILE=$(mktemp)
BOARD_JSON=$(gh project item-list "$GITHUB_PROJECT_NUMBER" \
  --owner "$GITHUB_PROJECT_OWNER" \
  --format json \
  --limit 50 2>"$BOARD_ERR_FILE")
BOARD_ERR=$(cat "$BOARD_ERR_FILE"); rm -f "$BOARD_ERR_FILE"

# Detect and classify errors — embed in JSON so callers can surface them
POLL_ERROR_JSON='null'
if [ -n "$BOARD_ERR" ] || ! printf '%s' "$BOARD_JSON" | jq 'empty' 2>/dev/null; then
  if printf '%s' "$BOARD_ERR" | grep -qi "rate limit"; then
    # GraphQL quota exhausted — fetch reset time from REST (doesn't consume GraphQL quota)
    RATE_RESET=$(curl -s -H "Authorization: token $(gh auth token 2>/dev/null)" \
      https://api.github.com/rate_limit 2>/dev/null \
      | jq -r '.resources.graphql.reset // empty' 2>/dev/null || true)
    RESET_AT=""
    RESET_IN=0
    if [ -n "$RATE_RESET" ]; then
      RESET_AT=$(date -u -d "@$RATE_RESET" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
             || date -u -r  "$RATE_RESET" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
      RESET_IN=$(( RATE_RESET - $(date +%s) ))
      [ "$RESET_IN" -lt 0 ] && RESET_IN=0
    fi
    POLL_ERROR_JSON=$(jq -n \
      --arg  type     "rate_limit" \
      --arg  message  "GitHub GraphQL API rate limit exceeded — board status unavailable" \
      --arg  reset_at "$RESET_AT" \
      --argjson reset_in "$RESET_IN" \
      '{type:$type, message:$message, reset_at:$reset_at, reset_in_seconds:$reset_in}')
  elif [ -n "$BOARD_ERR" ]; then
    POLL_ERROR_JSON=$(jq -n \
      --arg type    "api_error" \
      --arg message "$BOARD_ERR" \
      '{type:$type, message:$message}')
  fi
fi

# If gh failed (rate limit, network, auth), treat board as empty
BOARD_JSON=$(ensure_json "$BOARD_JSON" '{"items":[]}')

# 1. Items with status "Ready"
READY_ISSUES=$(printf '%s' "$BOARD_JSON" \
  | jq '[.items[] | select(.status == "Ready" and .content.number != null) | {
      id: .id,
      number: .content.number,
      title: .title,
      url: (.content.url // "")
    }]' 2>/dev/null)
READY_ISSUES=$(ensure_json "$READY_ISSUES" '[]')

# 2. Items with status "Approved" (human moved from Awaiting Approval)
APPROVED_ISSUES=$(printf '%s' "$BOARD_JSON" \
  | jq '[.items[] | select(.status == "Approved" and .content.number != null) | {
      id: .id,
      number: .content.number,
      title: .title,
      url: (.content.url // "")
    }]' 2>/dev/null)
APPROVED_ISSUES=$(ensure_json "$APPROVED_ISSUES" '[]')

# 3. Intake-resumed: Blocked issues where a human replied to intake-questions
INTAKE_RESUMED='[]'
BLOCKED_ISSUES=$(printf '%s' "$BOARD_JSON" \
  | jq '[.items[] | select(.status == "Blocked" and .content.number != null) | {
      number: .content.number,
      title: .title,
      url: (.content.url // "")
    }]' 2>/dev/null)
BLOCKED_ISSUES=$(ensure_json "$BLOCKED_ISSUES" '[]')

BLOCKED_N=$(printf '%s' "$BLOCKED_ISSUES" | jq 'length' 2>/dev/null)
BLOCKED_N="${BLOCKED_N:-0}"

b=0
while [ "$b" -lt "$BLOCKED_N" ]; do
  B_NUM=$(printf '%s' "$BLOCKED_ISSUES"   | jq -r ".[$b].number")
  B_TITLE=$(printf '%s' "$BLOCKED_ISSUES" | jq -r ".[$b].title // \"\"")
  B_URL=$(printf '%s' "$BLOCKED_ISSUES"   | jq -r ".[$b].url // \"\"")

  COMMENTS_RAW=$(gh api "repos/$GITHUB_REPO/issues/$B_NUM/comments" 2>/dev/null)
  COMMENTS=$(ensure_json "$COMMENTS_RAW" '[]')

  # Only process issues that have an intake-questions comment
  HAS_Q=$(printf '%s' "$COMMENTS" | \
    jq '[.[] | .body | test("pipeline-agent:intake-questions")] | any' 2>/dev/null)

  if [ "$HAS_Q" = "true" ]; then
    Q_TS=$(printf '%s' "$COMMENTS" | jq -r \
      '[.[] | select(.body | test("pipeline-agent:intake-questions"))] | last | .created_at // ""')

    # Human reply = any comment after the questions comment whose body does
    # NOT start with a pipeline-agent marker.
    HAS_REPLY=$(printf '%s' "$COMMENTS" | jq \
      --arg ts "$Q_TS" \
      '[.[] | select(.created_at > $ts and (.body | test("pipeline-agent:") | not))] | any' \
      2>/dev/null)

    if [ "$HAS_REPLY" = "true" ]; then
      INTAKE_RESUMED=$(printf '%s' "$INTAKE_RESUMED" | jq \
        --argjson n "$B_NUM" \
        --arg title "$B_TITLE" \
        --arg url   "$B_URL" \
        '. + [{id:null, number:$n, title:$title, url:$url}]' 2>/dev/null)
      INTAKE_RESUMED=$(ensure_json "$INTAKE_RESUMED" '[]')
    fi
  fi

  b=$((b + 1))
done

READY_COUNT=$(printf '%s' "$READY_ISSUES"       | jq 'length' 2>/dev/null); READY_COUNT="${READY_COUNT:-0}"
APPROVED_COUNT=$(printf '%s' "$APPROVED_ISSUES" | jq 'length' 2>/dev/null); APPROVED_COUNT="${APPROVED_COUNT:-0}"
INTAKE_RESUMED_COUNT=$(printf '%s' "$INTAKE_RESUMED" | jq 'length' 2>/dev/null); INTAKE_RESUMED_COUNT="${INTAKE_RESUMED_COUNT:-0}"

# Emit structured JSON
jq -n \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson ready          "$READY_ISSUES" \
  --argjson approved       "$APPROVED_ISSUES" \
  --argjson intake_resumed "$INTAKE_RESUMED" \
  --argjson error          "$POLL_ERROR_JSON" \
  '{
    timestamp:             $ts,
    ready_count:           ($ready          | length),
    approved_count:        ($approved        | length),
    intake_resumed_count:  ($intake_resumed  | length),
    ready:          $ready,
    approved:       $approved,
    intake_resumed: $intake_resumed,
    error:          $error
  }'

# Bitmask exit code — callers use bitwise AND to check each case:
#   [ $((EXIT_CODE & 1)) -ne 0 ] → ready
#   [ $((EXIT_CODE & 2)) -ne 0 ] → approved
#   [ $((EXIT_CODE & 4)) -ne 0 ] → intake-resumed
EXIT_CODE=0
[ "$READY_COUNT"          -gt 0 ] && EXIT_CODE=$((EXIT_CODE | 1))
[ "$APPROVED_COUNT"       -gt 0 ] && EXIT_CODE=$((EXIT_CODE | 2))
[ "$INTAKE_RESUMED_COUNT" -gt 0 ] && EXIT_CODE=$((EXIT_CODE | 4))
exit $EXIT_CODE
