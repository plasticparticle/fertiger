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

# 1. Project board: items with status "Ready"
READY_PROJECT=$(gh project item-list "$GITHUB_PROJECT_NUMBER" \
  --owner "$GITHUB_PROJECT_OWNER" \
  --format json \
  --limit 50 2>/dev/null \
  | jq '[.items[] | select(.status == "Ready" and .content.number != null) | {
      id: .id,
      number: .content.number,
      title: .title,
      url: (.content.url // "")
    }]' 2>/dev/null || echo '[]')

# 2. Label fallback: pipeline:ready
READY_LABELED=$(gh issue list \
  --repo "$GITHUB_REPO" \
  --label "pipeline:ready" \
  --json number,title,url \
  --state open 2>/dev/null \
  | jq '[.[] | {id: null, number: .number, title: .title, url: .url}]' \
  || echo '[]')

# Merge and deduplicate by issue number
READY_ISSUES=$(jq -s '(.[0] + .[1]) | unique_by(.number)' \
  <(echo "$READY_PROJECT") <(echo "$READY_LABELED"))

# 3. pipeline:approved label (resume after human approval)
APPROVED_ISSUES=$(gh issue list \
  --repo "$GITHUB_REPO" \
  --label "pipeline:approved" \
  --json number,title,labels \
  --state open 2>/dev/null || echo '[]')

# 4. Intake-resumed: blocked issues where a human replied to intake-questions
# For each pipeline:blocked issue that has an intake-questions comment, check
# whether a non-pipeline comment exists after that questions comment.
INTAKE_RESUMED='[]'
BLOCKED_ISSUES=$(gh issue list \
  --repo "$GITHUB_REPO" \
  --label "pipeline:blocked" \
  --json number,title,url \
  --state open 2>/dev/null || echo '[]')
BLOCKED_N=$(echo "$BLOCKED_ISSUES" | jq 'length')
b=0
while [ "$b" -lt "$BLOCKED_N" ]; do
  B_NUM=$(echo "$BLOCKED_ISSUES"   | jq -r ".[$b].number")
  B_TITLE=$(echo "$BLOCKED_ISSUES" | jq -r ".[$b].title")
  B_URL=$(echo "$BLOCKED_ISSUES"   | jq -r ".[$b].url // \"\"")

  COMMENTS=$(gh api "repos/$GITHUB_REPO/issues/$B_NUM/comments" 2>/dev/null || echo '[]')

  # Only process issues that have an intake-questions comment
  HAS_Q=$(echo "$COMMENTS" | \
    jq '[.[] | .body | test("pipeline-agent:intake-questions")] | any')

  if [ "$HAS_Q" = "true" ]; then
    Q_TS=$(echo "$COMMENTS" | jq -r \
      '[.[] | select(.body | test("pipeline-agent:intake-questions"))] | last | .created_at // ""')

    # Human reply = any comment after the questions comment whose body does
    # NOT start with a pipeline-agent marker.
    HAS_REPLY=$(echo "$COMMENTS" | jq \
      --arg ts "$Q_TS" \
      '[.[] | select(.created_at > $ts and (.body | test("pipeline-agent:") | not))] | any')

    if [ "$HAS_REPLY" = "true" ]; then
      INTAKE_RESUMED=$(echo "$INTAKE_RESUMED" | jq \
        --argjson n "$B_NUM" \
        --arg title "$B_TITLE" \
        --arg url   "$B_URL" \
        '. + [{id:null, number:$n, title:$title, url:$url}]')
    fi
  fi

  b=$((b + 1))
done

READY_COUNT=$(echo "$READY_ISSUES"   | jq 'length')
APPROVED_COUNT=$(echo "$APPROVED_ISSUES" | jq 'length')
INTAKE_RESUMED_COUNT=$(echo "$INTAKE_RESUMED" | jq 'length')

# Emit structured JSON
jq -n \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson ready          "$READY_ISSUES" \
  --argjson approved       "$APPROVED_ISSUES" \
  --argjson intake_resumed "$INTAKE_RESUMED" \
  '{
    timestamp:             $ts,
    ready_count:           ($ready          | length),
    approved_count:        ($approved        | length),
    intake_resumed_count:  ($intake_resumed  | length),
    ready:          $ready,
    approved:       $approved,
    intake_resumed: $intake_resumed
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
