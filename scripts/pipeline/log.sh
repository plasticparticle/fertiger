#!/bin/bash
# Pipeline progress logger
# Prints a formatted line to stdout (visible in the watch terminal) and
# appends it to $PIPELINE_LOG_FILE (default: /tmp/pipeline.log).
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
