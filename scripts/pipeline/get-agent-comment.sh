#!/usr/bin/env bash
# get-agent-comment.sh — fetch the last comment body from a named pipeline agent
#
# Usage:
#   scripts/pipeline/get-agent-comment.sh AGENT_NAME [ISSUE_NUMBER]
#
# AGENT_NAME must match the pipeline-agent: marker used in the comment, e.g.:
#   intake, eu-compliance, architect, solution-design, qa-tests, qa-validation,
#   dev-complete, code-quality, security, git-complete
#
# Returns the full body of the last matching comment on stdout.
# Exits 1 with an error message if no matching comment is found.
#
# Required env (sourced from .claude/config.sh):
#   GITHUB_REPO
#
# ISSUE_NUMBER can be passed as second argument or via env.

set -e

source .claude/config.sh

AGENT_NAME="${1:?Usage: get-agent-comment.sh AGENT_NAME [ISSUE_NUMBER]}"
ISSUE="${2:-$ISSUE_NUMBER}"

if [ -z "$ISSUE" ]; then
  echo "ERROR: ISSUE_NUMBER not set. Pass it as the second argument or export ISSUE_NUMBER." >&2
  exit 1
fi

RESULT=$(gh issue view "$ISSUE" \
  --repo "$GITHUB_REPO" \
  --comments \
  --json comments \
  | jq -r --arg agent "$AGENT_NAME" \
    '[.comments[] | select(.body | test("pipeline-agent:" + $agent))] | last | .body // empty')

if [ -z "$RESULT" ]; then
  echo "ERROR: No comment from agent '$AGENT_NAME' found on issue #$ISSUE." >&2
  exit 1
fi

echo "$RESULT"
