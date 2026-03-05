#!/usr/bin/env bash
# QA Integration Test: /pipeline:report historical summaries — Structured observability
# Covers: AC-006
# Issue: #15 — feat: structured observability

set -euo pipefail

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -qE "$needle"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — pattern '$needle' not found"
    echo "        output (first 10 lines):"
    echo "$haystack" | head -10 | sed 's/^/          /'
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -qE "$needle"; then
    echo "  FAIL: $description — pattern '$needle' was found but should not be"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $description"
    PASS=$((PASS + 1))
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

create_fixture_run() {
  local issue_num="$1"
  local run_date="$2"
  local outcome="$3"   # PASS or FAIL
  local run_id="issue-${issue_num}-${run_date}"
  local dir="$TMPDIR_TEST/.pipeline-logs/issue-${issue_num}"
  mkdir -p "$dir"
  local jsonl="$dir/${run_id}.jsonl"

  local end_level="PASS"
  [ "$outcome" = "FAIL" ] && end_level="FAIL"

  cat > "$jsonl" << JSONEOF
{"run_id":"$run_id","issue":$issue_num,"agent":"Watcher","level":"AGENT","message":"Starting","ts":"${run_date:0:4}-${run_date:4:2}-${run_date:6:2}T10:00:00Z","start_time":"${run_date:0:4}-${run_date:4:2}-${run_date:6:2}T10:00:00Z"}
{"run_id":"$run_id","issue":$issue_num,"agent":"Git Agent","level":"$end_level","message":"Pipeline complete","ts":"${run_date:0:4}-${run_date:4:2}-${run_date:6:2}T10:30:00Z","end_time":"${run_date:0:4}-${run_date:4:2}-${run_date:6:2}T10:30:00Z","exit_status":0}
JSONEOF
  echo "$run_id"
}

echo ""
echo "=== report-history.test.sh (integration): /pipeline:report Historical Summaries ==="
echo ""

# --- Prerequisite: report command file exists ---
echo "--- Prerequisite: .claude/commands/pipeline/report.md exists ---"
assert_file_exists "report.md command exists" "$REPO_ROOT/.claude/commands/pipeline/report.md"

echo ""
echo "--- Prerequisite: metrics.sh exists (used by report history) ---"
assert_file_exists "metrics.sh exists" "$REPO_ROOT/scripts/pipeline/metrics.sh"

echo ""
echo "--- AC-006: Set up 7 fixture pipeline runs across 3 issues ---"

# Create 7 runs (more than the minimum 5) so we can verify "last 5+ runs" requirement
create_fixture_run 20 "20260301" "PASS"
create_fixture_run 20 "20260302" "FAIL"
create_fixture_run 21 "20260303" "PASS"
create_fixture_run 21 "20260304" "PASS"
create_fixture_run 22 "20260305" "PASS"
create_fixture_run 20 "20260306" "PASS"
create_fixture_run 22 "20260307" "FAIL"

echo "  7 fixture runs created across issues 20, 21, 22"

echo ""
echo "--- AC-006: metrics.sh --history (or equivalent) lists completed runs ---"

if [ ! -f "$REPO_ROOT/scripts/pipeline/metrics.sh" ]; then
  echo "  FAIL: metrics.sh does not exist — skipping history tests"
  FAIL=$((FAIL + 3))
else
  # Try calling metrics.sh with --history flag (or just without an issue number)
  HISTORY_OUTPUT=$(PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs" \
    bash "$REPO_ROOT/scripts/pipeline/metrics.sh" --history 2>&1 \
    || PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs" \
    bash "$REPO_ROOT/scripts/pipeline/metrics.sh" 2>&1 || true)

  assert_contains "history output lists at least one run" "$HISTORY_OUTPUT" "issue-"
  assert_contains "history output includes outcome (PASS or FAIL)" "$HISTORY_OUTPUT" "PASS|FAIL"

  echo ""
  echo "--- AC-006: history shows at least 5 entries ---"
  RUN_COUNT=$(echo "$HISTORY_OUTPUT" | grep -cE "issue-[0-9]+-[0-9]+" || true)
  if [ "$RUN_COUNT" -ge 5 ]; then
    echo "  PASS: at least 5 runs shown in history ($RUN_COUNT found)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: fewer than 5 runs shown in history (got: $RUN_COUNT)"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "--- AC-006: report.md references history section or metrics.sh ---"

if [ -f "$REPO_ROOT/.claude/commands/pipeline/report.md" ]; then
  REPORT_CONTENT=$(cat "$REPO_ROOT/.claude/commands/pipeline/report.md")
  if echo "$REPORT_CONTENT" | grep -qiE "history|last [0-9]+ run|metrics"; then
    echo "  PASS: report.md references history or metrics"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: report.md does not reference history or metrics — not yet updated for AC-006"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "--- AC-006: each history row includes duration ---"

if [ -f "$REPO_ROOT/scripts/pipeline/metrics.sh" ]; then
  HISTORY_WITH_DURATION=$(PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs" \
    bash "$REPO_ROOT/scripts/pipeline/metrics.sh" --history 2>&1 \
    || PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs" \
    bash "$REPO_ROOT/scripts/pipeline/metrics.sh" 2>&1 || true)

  assert_contains "history includes duration data (minutes or seconds)" \
    "$HISTORY_WITH_DURATION" "[0-9]+m|[0-9]+s|duration|Duration"
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
