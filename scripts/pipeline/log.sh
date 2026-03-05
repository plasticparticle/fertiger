#!/bin/bash
# Pipeline progress logger
# Prints a formatted line to stdout (visible in the watch terminal) and
# appends it to $PIPELINE_LOG_FILE (default: /tmp/pipeline.log).
#
# When ISSUE_NUMBER is set, also appends a JSON line to:
#   ${PIPELINE_LOGS_DIR:-.pipeline-logs}/issue-N/<run_id>.jsonl
# run_id is persisted in .pipeline-logs/issue-N/.current-run-id sentinel file.
#
# Usage:
#   scripts/pipeline/log.sh AGENT MESSAGE [LEVEL]
#
# LEVEL values:
#   AGENT  — new agent starting        🤖
#   STEP   — sub-step in progress       ▸
#   PASS   — successful result         ✅
#   FAIL   — failure or block          ❌
#   BLOCK  — pipeline blocked          🚫
#   INFO   — general note (default)    ·
#
# Examples:
#   scripts/pipeline/log.sh "Intake" "Starting — Issue #$ISSUE_NUMBER" AGENT
#   scripts/pipeline/log.sh "EU Compliance" "Triage: STANDARD" STEP
#   scripts/pipeline/log.sh "QA Validation" "All tests passed" PASS

AGENT_NAME="${1:-pipeline}"
MSG="${2:-}"
LEVEL="${3:-INFO}"

LOG_FILE="${PIPELINE_LOG_FILE:-/tmp/pipeline.log}"
TIMESTAMP=$(date -u +"%H:%M:%SZ")
TS_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$LEVEL" in
  AGENT) ICON="🤖" ;;
  STEP)  ICON=" ▸ " ;;
  PASS)  ICON=" ✅" ;;
  FAIL)  ICON=" ❌" ;;
  BLOCK) ICON=" 🚫" ;;
  *)     ICON=" · " ;;
esac

LINE="[$TIMESTAMP] $ICON [$AGENT_NAME] $MSG"

# Print to terminal (stdout) — always visible in watch terminal
printf '%s\n' "$LINE"

# Append to log file — survives agent restarts, tailable from another terminal
mkdir -p "$(dirname "$LOG_FILE")"
printf '%s\n' "$LINE" >> "$LOG_FILE"

# JSON emission — only when ISSUE_NUMBER is set (REQ-002, REQ-005)
if [ -n "${ISSUE_NUMBER:-}" ]; then
  LOGS_BASE="${PIPELINE_LOGS_DIR:-.pipeline-logs}"
  ISSUE_LOG_DIR="$LOGS_BASE/issue-${ISSUE_NUMBER}"
  mkdir -p "$ISSUE_LOG_DIR"

  # Stable run_id for this pipeline run — persisted in sentinel file (REQ-001)
  SENTINEL="$ISSUE_LOG_DIR/.current-run-id"
  if [ -f "$SENTINEL" ]; then
    RUN_ID=$(cat "$SENTINEL")
  else
    RUN_ID="issue-${ISSUE_NUMBER}-$(date -u +%Y%m%d-%H%M%S)"
    printf '%s' "$RUN_ID" > "$SENTINEL"
  fi

  JSONL_FILE="$ISSUE_LOG_DIR/${RUN_ID}.jsonl"

  # Escape string fields for JSON embedding
  ESCAPED_MSG=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
  ESCAPED_AGENT=$(printf '%s' "$AGENT_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')

  printf '{"run_id":"%s","issue":%s,"agent":"%s","level":"%s","message":"%s","ts":"%s"}\n' \
    "$RUN_ID" "$ISSUE_NUMBER" "$ESCAPED_AGENT" "$LEVEL" "$ESCAPED_MSG" "$TS_ISO" \
    >> "$JSONL_FILE"

  # 30-day background rotation (REQ-007, fire-and-forget)
  if [ -d "$LOGS_BASE" ]; then
    find "$LOGS_BASE" -name "*.jsonl" -mtime +30 -delete 2>/dev/null &
  fi
fi
