#!/usr/bin/env bash
# set-status.sh — update the GitHub Project status for an issue
#
# Usage:
#   scripts/pipeline/set-status.sh STATUS_NAME
#
# STATUS_NAME must match one of the _OPTION_ID variables in .claude/config.sh,
# e.g. INTAKE, LEGAL_REVIEW, ARCHITECTURE, SOLUTION_DESIGN, AWAITING_APPROVAL,
#      APPROVED, IN_DEVELOPMENT, QA_REVIEW, CODE_REVIEW, SECURITY_REVIEW, READY_FOR_MERGE, DONE
#
# Required env (sourced from .claude/config.sh):
#   GITHUB_REPO, GITHUB_PROJECT_NUMBER, GITHUB_PROJECT_OWNER
#   PROJECT_NODE_ID, STATUS_FIELD_ID, <STATUS_NAME>_OPTION_ID
#
# Required env (set manually by agent):
#   ISSUE_NUMBER
#
# PROJECT_ITEM_ID is fetched automatically if not already exported.

set -e

source .claude/config.sh

STATUS_NAME="${1:?Usage: set-status.sh STATUS_NAME (e.g. LEGAL_REVIEW)}"

if [ -z "$ISSUE_NUMBER" ]; then
  echo "ERROR: ISSUE_NUMBER is not set. Export it before calling set-status.sh." >&2
  exit 1
fi

# Resolve the option ID from the status name
OPTION_VAR="${STATUS_NAME}_OPTION_ID"
OPTION_ID="${!OPTION_VAR}"
if [ -z "$OPTION_ID" ]; then
  echo "ERROR: Unknown status '$STATUS_NAME'. No variable '$OPTION_VAR' found in config.sh." >&2
  echo "Available statuses: BACKLOG INTAKE LEGAL_REVIEW ARCHITECTURE SOLUTION_DESIGN" >&2
  echo "                    AWAITING_APPROVAL APPROVED IN_DEVELOPMENT QA_REVIEW" >&2
  echo "                    CODE_REVIEW SECURITY_REVIEW READY_FOR_MERGE BLOCKED DONE" >&2
  exit 1
fi

# Auto-fetch PROJECT_ITEM_ID if not already set — cache to disk so subsequent
# set-status.sh calls within the same pipeline run skip the extra item-list query.
PITEM_CACHE="/tmp/fertiger-pitem-${GITHUB_PROJECT_NUMBER}-${ISSUE_NUMBER}"

if [ -z "$PROJECT_ITEM_ID" ] && [ -s "$PITEM_CACHE" ]; then
  PROJECT_ITEM_ID=$(cat "$PITEM_CACHE")
fi

if [ -z "$PROJECT_ITEM_ID" ]; then
  PROJECT_ITEM_ID=$(gh project item-list "$GITHUB_PROJECT_NUMBER" \
    --owner "$GITHUB_PROJECT_OWNER" \
    --format json \
    | jq -r ".items[] | select(.content.number == $ISSUE_NUMBER) | .id")
  if [ -z "$PROJECT_ITEM_ID" ]; then
    echo "ERROR: Could not find project item for issue #$ISSUE_NUMBER." >&2
    exit 1
  fi
  printf '%s' "$PROJECT_ITEM_ID" > "$PITEM_CACHE"
  export PROJECT_ITEM_ID
fi

gh project item-edit \
  --id "$PROJECT_ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --project-id "$PROJECT_NODE_ID" \
  --single-select-option-id "$OPTION_ID"

echo "Status → $STATUS_NAME (issue #$ISSUE_NUMBER)"
