#!/bin/bash
# Pipeline cost reporter
# Reads <!-- pipeline-agent:cost-summary --> comments across issues and produces
# an aggregated cost report. Used by /pipeline:cost-report.
#
# Usage:
#   scripts/pipeline/cost-report.sh              # all issues with cost summaries
#   scripts/pipeline/cost-report.sh N            # single issue N
#   scripts/pipeline/cost-report.sh --json       # output raw JSON array
#
# Env required: GITHUB_REPO (from .claude/config.sh)

source .claude/config.sh 2>/dev/null || true

MODE="table"
SINGLE_ISSUE=""

for arg in "$@"; do
  case "$arg" in
    --json) MODE="json" ;;
    [0-9]*) SINGLE_ISSUE="$arg" ;;
  esac
done

# Fetch issues that have cost-summary comments
# Use gh to search issue comments for the marker
fetch_cost_data() {
  local issue="$1"
  gh issue view "$issue" \
    --repo "$GITHUB_REPO" \
    --json comments \
    --jq '[.comments[] | select(.body | test("pipeline-agent:cost-summary"))] | last | .body' \
    2>/dev/null
}

extract_json() {
  local body="$1"
  # Extract the JSON block from inside the <details> section
  printf '%s\n' "$body" | awk '/^```json$/,/^```$/' | grep -v '```'
}

# Collect issue numbers to report on
if [ -n "$SINGLE_ISSUE" ]; then
  ISSUES="$SINGLE_ISSUE"
else
  # Find all issues with a cost-summary comment by checking recent closed/open issues
  ISSUES=$(gh issue list \
    --repo "$GITHUB_REPO" \
    --state all \
    --limit 50 \
    --json number \
    --jq '.[].number' 2>/dev/null)
fi

RESULTS="[]"
for issue in $ISSUES; do
  BODY=$(fetch_cost_data "$issue")
  [ -z "$BODY" ] && continue

  JSON=$(extract_json "$BODY")
  [ -z "$JSON" ] && continue

  # Validate JSON
  PARSED=$(printf '%s\n' "$JSON" | jq '.' 2>/dev/null) || continue
  RESULTS=$(printf '%s\n' "$RESULTS" | jq --argjson entry "$PARSED" '. + [$entry]')
done

if [ "$MODE" = "json" ]; then
  printf '%s\n' "$RESULTS" | jq '.'
  exit 0
fi

# Table output
COUNT=$(printf '%s\n' "$RESULTS" | jq 'length')
if [ "$COUNT" -eq 0 ]; then
  echo "No cost summaries found. Cost summaries are posted by the Git Agent at pipeline completion."
  exit 0
fi

TOTAL_TOKENS=$(printf '%s\n' "$RESULTS" | jq '[.[].total_tokens] | add // 0')
TOTAL_COST=$(printf '%s\n' "$RESULTS" | jq '[.[].cost_usd] | add // 0')

printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf '💰  Pipeline Cost Report — %s\n' "$GITHUB_REPO"
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'
printf '  %-6s  %-12s  %-14s  %-14s  %-10s\n' "Issue" "Model" "Input Tokens" "Output Tokens" "Cost (USD)"
printf '  %-6s  %-12s  %-14s  %-14s  %-10s\n' "------" "------------" "--------------" "--------------" "----------"

printf '%s\n' "$RESULTS" | jq -r '.[] | [
  ("#" + (.issue | tostring)),
  .model,
  (.input_tokens | tostring),
  (.output_tokens | tostring),
  ("$" + (.cost_usd | tostring))
] | @tsv' | while IFS=$'\t' read -r issue model input output cost; do
  printf '  %-6s  %-12s  %-14s  %-14s  %-10s\n' "$issue" "$model" "$input" "$output" "$cost"
done

printf '\n'
printf '  %-6s  %-12s  %-14s  %-14s  %-10s\n' "TOTAL" "" "$TOTAL_TOKENS tokens" "" "\$$TOTAL_COST"
printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
printf '  Features reported: %s\n' "$COUNT"
printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n'
