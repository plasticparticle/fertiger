#!/usr/bin/env bash
# .claude/scripts/watch.sh
#
# Long-running Git Watcher loop. Calls poll-once.sh on a timer and prints
# actionable issues for the agent to process.
#
# The agent (git-watcher.md) runs this script and acts on its output.
# It does NOT need to construct polling logic inline.
#
# Environment overrides:
#   POLL_INTERVAL      seconds between polls   (default: 300 = 5 min)
#   MAX_IDLE_SECONDS   stop after N idle secs  (default: 28800 = 8 h)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

POLL_INTERVAL="${POLL_INTERVAL:-300}"
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

  if [ "$EXIT_CODE" -eq 0 ]; then
    IDLE_SECONDS=$((IDLE_SECONDS + POLL_INTERVAL))
    echo "[watcher] Nothing actionable. Next check in ${POLL_INTERVAL}s."
  else
    IDLE_SECONDS=0  # reset idle counter whenever work is found
    if [ "$EXIT_CODE" -eq 1 ] || [ "$EXIT_CODE" -eq 3 ]; then
      READY_COUNT=$(echo "$RESULT" | jq -r '.ready_count // 0')
      echo "[watcher] ACTION: $READY_COUNT ready issue(s) — hand off to intake pipeline"
    fi
    if [ "$EXIT_CODE" -eq 2 ] || [ "$EXIT_CODE" -eq 3 ]; then
      APPROVED_COUNT=$(echo "$RESULT" | jq -r '.approved_count // 0')
      echo "[watcher] ACTION: $APPROVED_COUNT approved issue(s) — resume pipeline from QA"
    fi
  fi

  sleep "$POLL_INTERVAL"
done

echo ""
echo "[watcher] Idle timeout reached after ${MAX_IDLE_SECONDS}s. Stopping."
echo "[watcher] Total polls: $POLL_COUNT"
exit 0
