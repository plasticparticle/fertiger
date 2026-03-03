#!/usr/bin/env bash
# cancel-pipeline.sh — remove pipeline labels and reset issue status to Backlog
#
# Usage:
#   scripts/pipeline/cancel-pipeline.sh
#
# Env required:
#   ISSUE_NUMBER — must be set by the caller
#   GITHUB_REPO, BACKLOG_OPTION_ID, STATUS_FIELD_ID, PROJECT_NODE_ID — from .claude/config.sh

set -e

source .claude/config.sh

if [ -z "$ISSUE_NUMBER" ]; then
  echo "ERROR: ISSUE_NUMBER is not set. Export it before calling cancel-pipeline.sh." >&2
  exit 1
fi

# Remove pipeline labels — ignore errors if the label is not present on the issue
for LABEL in "pipeline:ready" "pipeline:blocked" "pipeline:approved"; do
  gh issue edit "$ISSUE_NUMBER" \
    --repo "$GITHUB_REPO" \
    --remove-label "$LABEL" 2>/dev/null || true
done

echo "Labels removed: pipeline:ready, pipeline:blocked, pipeline:approved"

# Reset project status to Backlog
scripts/pipeline/set-status.sh BACKLOG

echo "Pipeline cancelled for issue #$ISSUE_NUMBER — status reset to Backlog"
