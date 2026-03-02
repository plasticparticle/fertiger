#!/usr/bin/env bash
# .claude/scripts/webhook-watch.sh
#
# Event-driven Git Watcher. Uses `gh webhook forward` to receive GitHub issue
# events in real-time — the pipeline fires within seconds of a label being added.
#
# Output interface is identical to watch.sh, so git-watcher.md rules work
# unchanged. The agent always runs this script; mode selection is internal.
#
# Requirements:
#   - GitHub CLI with `gh webhook forward` support
#   - python3
#
# Falls back to watch.sh (polling mode) if either is unavailable.
#
# Environment:
#   WEBHOOK_PORT       local port for HTTP listener (default: 9867)
#   MAX_IDLE_SECONDS   stop after N idle secs      (default: 28800 = 8 h)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

WEBHOOK_PORT="${WEBHOOK_PORT:-9867}"
MAX_IDLE_SECONDS="${MAX_IDLE_SECONDS:-28800}"
HEARTBEAT_INTERVAL=60

source "$ROOT_DIR/.claude/config.sh"

# ── Prerequisite check ────────────────────────────────────────────────────────
if ! gh webhook forward --help >/dev/null 2>&1; then
  echo "[watcher] gh webhook forward not available — falling back to polling"
  exec "$SCRIPT_DIR/watch.sh"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[watcher] python3 not found — falling back to polling"
  exec "$SCRIPT_DIR/watch.sh"
fi

echo "[watcher] Webhook mode started at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "[watcher] Repo: $GITHUB_REPO | Port: $WEBHOOK_PORT | Idle timeout: ${MAX_IDLE_SECONDS}s"

# ── Temp files ────────────────────────────────────────────────────────────────
EVENT_LOG="/tmp/pipeline-webhook-events-$$.log"
PYTHON_SCRIPT="/tmp/pipeline-webhook-server-$$.py"
GH_LOG="/tmp/pipeline-gh-webhook-$$.log"
touch "$EVENT_LOG"

PYTHON_PID=""
GH_FWD_PID=""

cleanup() {
  [ -n "$PYTHON_PID" ] && kill "$PYTHON_PID" 2>/dev/null || true
  [ -n "$GH_FWD_PID" ] && kill "$GH_FWD_PID" 2>/dev/null || true
  rm -f "$EVENT_LOG" "$PYTHON_SCRIPT" "$GH_LOG"
}
trap cleanup EXIT INT TERM

# ── Python HTTP listener ──────────────────────────────────────────────────────
# Receives webhook POSTs from gh webhook forward. Appends one JSON payload
# per line to EVENT_LOG. Internal newlines stripped so each event = one line.
cat > "$PYTHON_SCRIPT" << 'PYEOF'
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

port = int(sys.argv[1])
log  = sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        n    = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n).decode(errors='replace').replace('\n', ' ')
        with open(log, 'a') as f:
            f.write(body + '\n')
        self.send_response(200)
        self.end_headers()
    def log_message(self, *a):
        pass

HTTPServer(('localhost', port), Handler).serve_forever()
PYEOF

python3 "$PYTHON_SCRIPT" "$WEBHOOK_PORT" "$EVENT_LOG" &
PYTHON_PID=$!
sleep 1  # allow Python to bind the port before gh connects

# ── gh webhook forward ────────────────────────────────────────────────────────
start_gh_forwarder() {
  gh webhook forward \
    --repo "$GITHUB_REPO" \
    --events="issues" \
    --url="http://localhost:$WEBHOOK_PORT" \
    >"$GH_LOG" 2>&1 &
  GH_FWD_PID=$!
}
start_gh_forwarder

echo "[watcher] Listening for GitHub issue events — no polling"
echo ""

# ── Initial poll — catch any issues already waiting ──────────────────────────
# Webhooks only fire for future events. Poll once on startup to pick up
# anything that was labelled before the watcher started.
echo "[watcher] Initial poll — checking for pre-existing ready/approved issues..."
INITIAL_RESULT=$("$SCRIPT_DIR/poll-once.sh" 2>&1)
INITIAL_EXIT=$?
echo "$INITIAL_RESULT"
if [ "$INITIAL_EXIT" -eq 1 ] || [ "$INITIAL_EXIT" -eq 3 ]; then
  READY_COUNT=$(echo "$INITIAL_RESULT" | jq -r '.ready_count // 0')
  echo "[watcher] ACTION: $READY_COUNT ready issue(s) — hand off to intake pipeline"
fi
if [ "$INITIAL_EXIT" -eq 2 ] || [ "$INITIAL_EXIT" -eq 3 ]; then
  APPROVED_COUNT=$(echo "$INITIAL_RESULT" | jq -r '.approved_count // 0')
  echo "[watcher] ACTION: $APPROVED_COUNT approved issue(s) — resume pipeline from QA"
fi
echo ""

# ── Event loop ────────────────────────────────────────────────────────────────
LAST_LINE=0
LAST_ACTIVITY=$(date +%s)
LAST_HEARTBEAT=$(date +%s)

while true; do
  NOW=$(date +%s)
  IDLE=$((NOW - LAST_ACTIVITY))

  # Idle timeout
  if [ "$IDLE" -ge "$MAX_IDLE_SECONDS" ]; then
    echo ""
    echo "[watcher] Idle timeout reached after ${MAX_IDLE_SECONDS}s. Stopping."
    exit 0
  fi

  # Heartbeat every HEARTBEAT_INTERVAL seconds — confirms watcher is alive
  SINCE_HEARTBEAT=$((NOW - LAST_HEARTBEAT))
  if [ "$SINCE_HEARTBEAT" -ge "$HEARTBEAT_INTERVAL" ]; then
    echo "[watcher] Alive — $(date -u +"%Y-%m-%dT%H:%M:%SZ") — idle ${IDLE}s / ${MAX_IDLE_SECONDS}s"
    LAST_HEARTBEAT="$NOW"
  fi

  # Auto-restart gh webhook forward if it exited unexpectedly
  if ! kill -0 "$GH_FWD_PID" 2>/dev/null; then
    echo "[watcher] gh webhook forward exited — restarting..."
    sleep 2
    start_gh_forwarder
  fi

  # Check for new events in log file
  CURRENT_LINE=$(wc -l < "$EVENT_LOG" 2>/dev/null | tr -d ' ')
  CURRENT_LINE="${CURRENT_LINE:-0}"

  if [ "$CURRENT_LINE" -gt "$LAST_LINE" ]; then
    LAST_ACTIVITY=$(date +%s)
    LAST_HEARTBEAT=$(date +%s)

    while IFS= read -r PAYLOAD; do
      [ -z "$PAYLOAD" ] && continue

      ACTION=$(echo "$PAYLOAD" | jq -r '.action // empty' 2>/dev/null || true)
      LABEL=$(echo "$PAYLOAD"  | jq -r '.label.name // empty' 2>/dev/null || true)
      NUMBER=$(echo "$PAYLOAD" | jq -r '.issue.number // empty' 2>/dev/null || true)
      TITLE=$(echo "$PAYLOAD"  | jq -r '.issue.title // ""' 2>/dev/null || true)
      URL=$(echo "$PAYLOAD"    | jq -r '.issue.html_url // ""' 2>/dev/null || true)

      if [ "$ACTION" != "labeled" ] || [ -z "$NUMBER" ] || [ -z "$LABEL" ]; then
        continue
      fi

      if [ "$LABEL" = "pipeline:ready" ]; then
        echo ""
        echo "[watcher] Event: issue #$NUMBER labeled pipeline:ready — $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        jq -n \
          --arg  ts    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
          --argjson n  "$NUMBER" \
          --arg  title "$TITLE" \
          --arg  url   "$URL" \
          '{timestamp:$ts, ready_count:1, approved_count:0,
            ready:[{id:null, number:$n, title:$title, url:$url}],
            approved:[]}'
        echo "[watcher] ACTION: 1 ready issue(s) — hand off to intake pipeline"

      elif [ "$LABEL" = "pipeline:approved" ]; then
        echo ""
        echo "[watcher] Event: issue #$NUMBER labeled pipeline:approved — $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        jq -n \
          --arg  ts    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
          --argjson n  "$NUMBER" \
          --arg  title "$TITLE" \
          --arg  url   "$URL" \
          '{timestamp:$ts, ready_count:0, approved_count:1,
            ready:[],
            approved:[{id:null, number:$n, title:$title, url:$url}]}'
        echo "[watcher] ACTION: 1 approved issue(s) — resume pipeline from QA"
      fi

    done < <(tail -n +"$((LAST_LINE + 1))" "$EVENT_LOG")

    LAST_LINE="$CURRENT_LINE"
  fi

  sleep 1
done
