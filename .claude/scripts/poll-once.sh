#!/usr/bin/env bash
# .claude/scripts/poll-once.sh
#
# Single poll: scans GitHub Project board and labels for actionable issues.
# Prints a JSON object to stdout.
#
# Exit codes:
#   0 — nothing actionable found
#   1 — ready issues found    (start pipeline)
#   2 — approved issues found (resume pipeline after human approval)
#   3 — both ready and approved found

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

READY_COUNT=$(echo "$READY_ISSUES" | jq 'length')
APPROVED_COUNT=$(echo "$APPROVED_ISSUES" | jq 'length')

# Emit structured JSON
jq -n \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson ready "$READY_ISSUES" \
  --argjson approved "$APPROVED_ISSUES" \
  '{
    timestamp: $ts,
    ready_count:    ($ready    | length),
    approved_count: ($approved | length),
    ready:    $ready,
    approved: $approved
  }'

# Exit code reflects what was found
if   [ "$READY_COUNT" -gt 0 ] && [ "$APPROVED_COUNT" -gt 0 ]; then exit 3
elif [ "$APPROVED_COUNT" -gt 0 ]; then exit 2
elif [ "$READY_COUNT"   -gt 0 ]; then exit 1
else exit 0
fi
