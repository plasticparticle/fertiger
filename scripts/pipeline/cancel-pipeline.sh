#!/usr/bin/env bash
# cancel-pipeline.sh — reset issue project status to Backlog
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

# Reset project status to Backlog
scripts/pipeline/set-status.sh BACKLOG

echo "Pipeline cancelled for issue #$ISSUE_NUMBER — status reset to Backlog"
