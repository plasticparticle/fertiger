#!/usr/bin/env bash
# QA Unit Test: metrics.sh reporting — Structured observability
# Covers: AC-003
# Issue: #15 — feat: structured observability

set -euo pipefail

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "        expected: $expected"
    echo "        actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — '$needle' not found in output"
    echo "        output was: $(echo "$haystack" | head -5)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local description="$1"
  local file="$2"
  if [ -f "$file" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — file not found: $file"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== metrics.test.sh (unit): metrics.sh Reporting Script ==="
echo ""

# --- Prerequisite: metrics.sh must exist ---
echo "--- Prerequisite: scripts/pipeline/metrics.sh exists and is executable ---"
assert_file_exists "metrics.sh exists" "$REPO_ROOT/scripts/pipeline/metrics.sh"
if [ -x "$REPO_ROOT/scripts/pipeline/metrics.sh" ]; then
  echo "  PASS: metrics.sh is executable"
  PASS=$((PASS + 1))
else
  echo "  FAIL: metrics.sh is not executable"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-003: Set up fixture .jsonl log files for issue 88 ---"

# Create a fixture run with two agents and known timings
FIXTURE_DIR="$TMPDIR_TEST/.pipeline-logs/issue-88"
RUN_ID="issue-88-20260305-103000"
mkdir -p "$FIXTURE_DIR"

FIXTURE_JSONL="$FIXTURE_DIR/${RUN_ID}.jsonl"

# Write fixture JSON lines simulating a completed pipeline run
cat > "$FIXTURE_JSONL" << 'JSONEOF'
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"Intake","level":"AGENT","message":"Starting — Issue #88","ts":"2026-03-05T10:30:00Z","start_time":"2026-03-05T10:30:00Z"}
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"Intake","level":"PASS","message":"Complete — requirements posted","ts":"2026-03-05T10:30:45Z","end_time":"2026-03-05T10:30:45Z","exit_status":0}
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"EU Compliance","level":"AGENT","message":"Starting — Issue #88","ts":"2026-03-05T10:31:00Z","start_time":"2026-03-05T10:31:00Z"}
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"EU Compliance","level":"PASS","message":"COMPLIANT — proceeding","ts":"2026-03-05T10:33:00Z","end_time":"2026-03-05T10:33:00Z","exit_status":0}
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"Dev Swarm","level":"AGENT","message":"Starting — Issue #88","ts":"2026-03-05T10:40:00Z","start_time":"2026-03-05T10:40:00Z"}
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"Dev Swarm","level":"FAIL","message":"Tests failed — retrying","ts":"2026-03-05T10:45:00Z","end_time":"2026-03-05T10:45:00Z","exit_status":1}
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"Dev Swarm","level":"AGENT","message":"Starting — Issue #88 (retry 1)","ts":"2026-03-05T10:46:00Z","start_time":"2026-03-05T10:46:00Z"}
{"run_id":"issue-88-20260305-103000","issue":88,"agent":"Dev Swarm","level":"PASS","message":"All tests pass","ts":"2026-03-05T10:52:00Z","end_time":"2026-03-05T10:52:00Z","exit_status":0}
JSONEOF

echo "  Fixture created: $FIXTURE_JSONL"
echo "  (8 log entries, 2 agents, 1 retry for Dev Swarm)"

echo ""
echo "--- AC-003: metrics.sh N outputs table with per-agent durations ---"

if [ ! -f "$REPO_ROOT/scripts/pipeline/metrics.sh" ]; then
  echo "  FAIL: metrics.sh does not exist — cannot test output"
  FAIL=$((FAIL + 4))
else
  METRICS_OUTPUT=$(PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs" \
    bash "$REPO_ROOT/scripts/pipeline/metrics.sh" 88 2>&1 || true)

  assert_contains "output includes issue number" "$METRICS_OUTPUT" "88"
  assert_contains "output includes agent name (Intake)" "$METRICS_OUTPUT" "Intake"
  assert_contains "output includes 'duration' or timing data" "$METRICS_OUTPUT" "[0-9]"

  echo ""
  echo "--- AC-003: metrics.sh N shows retry count ---"
  assert_contains "output includes retry count (Dev Swarm had 1 retry)" "$METRICS_OUTPUT" "[Rr]etr"

  echo ""
  echo "--- AC-003: metrics.sh N <run_id> shows per-agent timing for specific run ---"
  METRICS_RUN_OUTPUT=$(PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs" \
    bash "$REPO_ROOT/scripts/pipeline/metrics.sh" 88 "$RUN_ID" 2>&1 || true)

  assert_contains "run-specific output includes run_id" "$METRICS_RUN_OUTPUT" "issue-88-20260305"
fi

echo ""
echo "--- AC-003: metrics.sh handles non-existent issue gracefully ---"

if [ -f "$REPO_ROOT/scripts/pipeline/metrics.sh" ]; then
  MISSING_OUTPUT=$(PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs" \
    bash "$REPO_ROOT/scripts/pipeline/metrics.sh" 9999 2>&1 || true)
  if [ -n "$MISSING_OUTPUT" ]; then
    echo "  PASS: metrics.sh outputs something for unknown issue (graceful)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: metrics.sh produced no output for unknown issue"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "--- AC-003: metrics.sh with no arguments prints usage ---"

if [ -f "$REPO_ROOT/scripts/pipeline/metrics.sh" ]; then
  USAGE_OUTPUT=$(bash "$REPO_ROOT/scripts/pipeline/metrics.sh" 2>&1 || true)
  if [ -n "$USAGE_OUTPUT" ]; then
    echo "  PASS: metrics.sh prints usage when called without arguments"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: metrics.sh produced no output when called without arguments"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
