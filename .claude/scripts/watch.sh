#!/usr/bin/env bash
# .claude/scripts/watch.sh
#
# Long-running Git Watcher loop. Calls poll-once.sh on a timer and prints
# actionable issues for the agent to process.
#
# The agent (git-watcher.md) runs this script and acts on its output.
# It does NOT need to construct polling logic inline.
#
# poll-once.sh exit codes are a bitmask:
#   bit 0 (1) — ready issues found
#   bit 1 (2) — approved issues found
#   bit 2 (4) — intake-resumed issues found (human replied to questions)
#
# Environment overrides:
#   POLL_INTERVAL      seconds between polls   (default: 60 = 1 min)
#   MAX_IDLE_SECONDS   stop after N idle secs  (default: 28800 = 8 h)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

POLL_INTERVAL="${POLL_INTERVAL:-120}"
MAX_IDLE_SECONDS="${MAX_IDLE_SECONDS:-28800}"

source "$ROOT_DIR/.claude/config.sh"

echo "[watcher] Started at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "[watcher] Repo: $GITHUB_REPO | Project: #$GITHUB_PROJECT_NUMBER"
echo "[watcher] Poll interval: ${POLL_INTERVAL}s | Idle timeout: ${MAX_IDLE_SECONDS}s"

IDLE_SECONDS=0
POLL_COUNT=0

while [ "$IDLE_SECONDS" -lt "$MAX_IDLE_SECONDS" ]; do
  POLL_COUNT=$((POLL_COUNT + 1))
  echo ""
  echo "[watcher] Poll #$POLL_COUNT — $(date -u +"%Y-%m-%dT%H:%M:%SZ") — idle ${IDLE_SECONDS}s / ${MAX_IDLE_SECONDS}s"

  RESULT=$("$SCRIPT_DIR/poll-once.sh" 2>&1)
  EXIT_CODE=$?

  echo "$RESULT"

  # Surface API errors (rate limit, auth, network) so they're visible
  POLL_ERR_TYPE=$(printf '%s' "$RESULT" | jq -r '.error.type // empty' 2>/dev/null || true)
  if [ -n "$POLL_ERR_TYPE" ]; then
    POLL_ERR_MSG=$(printf '%s' "$RESULT" | jq -r '.error.message // "API error"' 2>/dev/null || true)
    RESET_IN=$(printf '%s' "$RESULT" | jq -r '.error.reset_in_seconds // 0' 2>/dev/null || echo 0)
    RESET_AT=$(printf '%s' "$RESULT" | jq -r '.error.reset_at // ""' 2>/dev/null || true)
    if [ "$RESET_IN" -gt 0 ] 2>/dev/null; then
      RESET_MINS=$(( (RESET_IN + 59) / 60 ))
      echo "[watcher] ⚠️  WARNING: $POLL_ERR_MSG"
      echo "[watcher] ⚠️  Rate limit resets in ~${RESET_MINS}m (at ${RESET_AT}). Board results may be incomplete."
    else
      echo "[watcher] ⚠️  WARNING: $POLL_ERR_MSG"
    fi
  fi

  if [ "$EXIT_CODE" -eq 0 ]; then
    IDLE_SECONDS=$((IDLE_SECONDS + POLL_INTERVAL))
    echo "[watcher] Nothing actionable. Next check in ${POLL_INTERVAL}s."
  else
    IDLE_SECONDS=0  # reset idle counter whenever work is found

    if [ $((EXIT_CODE & 1)) -ne 0 ]; then
      READY_COUNT=$(echo "$RESULT" | jq -r '.ready_count // 0')
      echo "[watcher] ACTION: $READY_COUNT ready issue(s) — hand off to intake pipeline"
    fi

    if [ $((EXIT_CODE & 2)) -ne 0 ]; then
      APPROVED_COUNT=$(echo "$RESULT" | jq -r '.approved_count // 0')
      echo "[watcher] ACTION: $APPROVED_COUNT approved issue(s) — resume pipeline from QA"
    fi

    if [ $((EXIT_CODE & 4)) -ne 0 ]; then
      RESUMED_COUNT=$(echo "$RESULT" | jq -r '.intake_resumed_count // 0')
      echo "[watcher] ACTION: $RESUMED_COUNT intake-resumed issue(s) — resume intake with clarifications"
    fi
  fi

  sleep "$POLL_INTERVAL"
done

echo ""
echo "[watcher] Idle timeout reached after ${MAX_IDLE_SECONDS}s. Stopping."
echo "[watcher] Total polls: $POLL_COUNT"
exit 0
