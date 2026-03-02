#!/usr/bin/env bash
# checkout-branch.sh — fetch and checkout the feature branch for an issue
#
# Usage:
#   BRANCH_NAME=$(scripts/pipeline/checkout-branch.sh [ISSUE_NUMBER])
#
# If BRANCH_NAME is already exported, uses it directly (skips issue comment lookup).
# If BRANCH_NAME is not set, extracts it from the "Branch created:" comment on the issue.
#
# Always runs: git fetch origin && git checkout $BRANCH_NAME && git pull origin $BRANCH_NAME
# Echoes the branch name to stdout so callers can capture it.
#
# Required env (sourced from .claude/config.sh):
#   GITHUB_REPO
#
# ISSUE_NUMBER can be passed as first argument or via env (required if BRANCH_NAME not set).

set -e

source .claude/config.sh

ISSUE="${1:-$ISSUE_NUMBER}"

if [ -z "$BRANCH_NAME" ]; then
  if [ -z "$ISSUE" ]; then
    echo "ERROR: BRANCH_NAME not set and ISSUE_NUMBER not available." >&2
    echo "Either export BRANCH_NAME or pass ISSUE_NUMBER as argument." >&2
    exit 1
  fi

  BRANCH_NAME=$(gh issue view "$ISSUE" \
    --repo "$GITHUB_REPO" \
    --comments \
    --json comments \
    | jq -r '[.comments[] | select(.body | test("Branch created:"))] | last | .body' \
    | grep -oP 'feature/[^`]+' \
    | head -1)

  if [ -z "$BRANCH_NAME" ]; then
    echo "ERROR: Could not extract branch name from issue #$ISSUE comments." >&2
    exit 1
  fi

  export BRANCH_NAME
fi

git fetch origin
git checkout "$BRANCH_NAME"
git pull origin "$BRANCH_NAME"

echo "$BRANCH_NAME"
