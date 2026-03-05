#!/usr/bin/env bash
# QA Unit Test: log.sh JSON emission — Structured observability
# Covers: AC-001, AC-002, AC-004, AC-005
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

assert_true() {
  local description="$1"
  local result="$2"
  if [ "$result" = "true" ] || [ "$result" = "0" ] || [ -n "$result" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    FAIL=$((FAIL + 1))
  fi
}

assert_false() {
  local description="$1"
  local result="$2"
  if [ -z "$result" ] || [ "$result" = "false" ] || [ "$result" = "1" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — expected falsy, got: $result"
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

assert_json_valid() {
  local description="$1"
  local line="$2"
  if echo "$line" | jq . >/dev/null 2>&1; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — not valid JSON: $line"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local description="$1"
  local json="$2"
  local field="$3"
  local value
  value=$(echo "$json" | jq -r ".$field // empty" 2>/dev/null || true)
  if [ -n "$value" ] && [ "$value" != "null" ]; then
    echo "  PASS: $description (value: $value)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — field '$field' missing or null in: $json"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== log-json.test.sh (unit): log.sh JSON Emission ==="
echo ""

# --- AC-005: log file created at .pipeline-logs/issue-N/<run_id>.jsonl ---
echo "--- AC-005: Log file is created at .pipeline-logs/issue-N/<run_id>.jsonl ---"

PIPELINE_LOGS_DIR="$TMPDIR_TEST/.pipeline-logs"
ISSUE_NUMBER=99

PIPELINE_LOG_FILE="$TMPDIR_TEST/pipeline.log" \
  ISSUE_NUMBER=99 \
  PIPELINE_LOGS_DIR="$PIPELINE_LOGS_DIR" \
  bash "$REPO_ROOT/scripts/pipeline/log.sh" "TestAgent" "hello world" "STEP" 2>/dev/null || true

# Check that at least one .jsonl file was created under .pipeline-logs/issue-99/
JSONL_FILES=$(find "$PIPELINE_LOGS_DIR/issue-99" -name "*.jsonl" 2>/dev/null || true)
if [ -n "$JSONL_FILES" ]; then
  echo "  PASS: .jsonl file created at .pipeline-logs/issue-99/"
  PASS=$((PASS + 1))
else
  echo "  FAIL: no .jsonl file found under .pipeline-logs/issue-99/ — log.sh does not write JSON yet"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-002: Each JSON line parses as valid JSON with required fields ---"

# If file was created, validate its contents
if [ -n "$JSONL_FILES" ]; then
  JSONL_FILE=$(echo "$JSONL_FILES" | head -1)
  FIRST_LINE=$(head -1 "$JSONL_FILE")
  assert_json_valid "JSON line is valid JSON" "$FIRST_LINE"
  assert_json_field "field 'run_id' present" "$FIRST_LINE" "run_id"
  assert_json_field "field 'issue' present" "$FIRST_LINE" "issue"
  assert_json_field "field 'agent' present" "$FIRST_LINE" "agent"
  assert_json_field "field 'level' present" "$FIRST_LINE" "level"
  assert_json_field "field 'message' present" "$FIRST_LINE" "message"
  assert_json_field "field 'ts' present" "$FIRST_LINE" "ts"
else
  echo "  SKIP: Cannot validate JSON fields — no .jsonl file was created (log.sh not yet extended)"
  FAIL=$((FAIL + 6))
fi

echo ""
echo "--- AC-001: Two different issues produce two distinct run_id values ---"

PIPELINE_LOGS_DIR_A="$TMPDIR_TEST/.pipeline-logs-a"
PIPELINE_LOGS_DIR_B="$TMPDIR_TEST/.pipeline-logs-b"

PIPELINE_LOG_FILE="$TMPDIR_TEST/pipeline-a.log" \
  ISSUE_NUMBER=101 \
  PIPELINE_LOGS_DIR="$PIPELINE_LOGS_DIR_A" \
  bash "$REPO_ROOT/scripts/pipeline/log.sh" "AgentA" "run for issue 101" "STEP" 2>/dev/null || true

PIPELINE_LOG_FILE="$TMPDIR_TEST/pipeline-b.log" \
  ISSUE_NUMBER=102 \
  PIPELINE_LOGS_DIR="$PIPELINE_LOGS_DIR_B" \
  bash "$REPO_ROOT/scripts/pipeline/log.sh" "AgentB" "run for issue 102" "STEP" 2>/dev/null || true

JSONL_A=$(find "$PIPELINE_LOGS_DIR_A/issue-101" -name "*.jsonl" 2>/dev/null | head -1 || true)
JSONL_B=$(find "$PIPELINE_LOGS_DIR_B/issue-102" -name "*.jsonl" 2>/dev/null | head -1 || true)

if [ -n "$JSONL_A" ] && [ -n "$JSONL_B" ]; then
  RUN_ID_A=$(jq -r '.run_id' "$JSONL_A" 2>/dev/null | head -1)
  RUN_ID_B=$(jq -r '.run_id' "$JSONL_B" 2>/dev/null | head -1)
  if [ "$RUN_ID_A" != "$RUN_ID_B" ]; then
    echo "  PASS: run_id values are distinct ($RUN_ID_A vs $RUN_ID_B)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: run_id values are identical ($RUN_ID_A) — should differ between issues"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: could not produce two .jsonl files to compare run_ids — log.sh not yet extended"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-001: run_id format matches issue-N-YYYYMMDD-HHMMSS ---"

if [ -n "$JSONL_A" ]; then
  RUN_ID=$(jq -r '.run_id' "$JSONL_A" 2>/dev/null | head -1)
  if echo "$RUN_ID" | grep -qE '^issue-[0-9]+-[0-9]{8}-[0-9]{6}$'; then
    echo "  PASS: run_id format matches issue-N-YYYYMMDD-HHMMSS: $RUN_ID"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: run_id format invalid: $RUN_ID (expected: issue-N-YYYYMMDD-HHMMSS)"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  FAIL: no .jsonl file to check run_id format"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-004: Non-zero agent exit → level:FAIL in JSON ---"

PIPELINE_LOGS_DIR_FAIL="$TMPDIR_TEST/.pipeline-logs-fail"

# Call log.sh with level FAIL (simulating a failing agent)
PIPELINE_LOG_FILE="$TMPDIR_TEST/pipeline-fail.log" \
  ISSUE_NUMBER=103 \
  PIPELINE_LOGS_DIR="$PIPELINE_LOGS_DIR_FAIL" \
  bash "$REPO_ROOT/scripts/pipeline/log.sh" "FailAgent" "something went wrong" "FAIL" 2>/dev/null || true

JSONL_FAIL=$(find "$PIPELINE_LOGS_DIR_FAIL/issue-103" -name "*.jsonl" 2>/dev/null | head -1 || true)

if [ -n "$JSONL_FAIL" ]; then
  FAIL_LEVEL=$(jq -r '.level' "$JSONL_FAIL" 2>/dev/null | head -1)
  assert_eq "level field is FAIL when FAIL level passed" "FAIL" "$FAIL_LEVEL"
else
  echo "  FAIL: no .jsonl file for FAIL level test"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Backward-compat: log.sh still writes human-readable stdout ---"

STDOUT_OUTPUT=$(PIPELINE_LOG_FILE="$TMPDIR_TEST/pipeline-compat.log" \
  ISSUE_NUMBER=104 \
  PIPELINE_LOGS_DIR="$TMPDIR_TEST/.compat" \
  bash "$REPO_ROOT/scripts/pipeline/log.sh" "CompatAgent" "hello" "PASS" 2>/dev/null || true)

if echo "$STDOUT_OUTPUT" | grep -q "CompatAgent"; then
  echo "  PASS: human-readable stdout still emitted (backward compatible)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: human-readable stdout missing — log.sh broke backward compat"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- No JSON emitted when ISSUE_NUMBER unset ---"

UNSET_LOGS="$TMPDIR_TEST/.pipeline-logs-unset"
PIPELINE_LOG_FILE="$TMPDIR_TEST/pipeline-unset.log" \
  PIPELINE_LOGS_DIR="$UNSET_LOGS" \
  bash "$REPO_ROOT/scripts/pipeline/log.sh" "UnsetAgent" "no issue" "INFO" 2>/dev/null || true

UNSET_FILES=$(find "$UNSET_LOGS" -name "*.jsonl" 2>/dev/null || true)
if [ -z "$UNSET_FILES" ]; then
  echo "  PASS: no .jsonl file created when ISSUE_NUMBER is unset"
  PASS=$((PASS + 1))
else
  echo "  FAIL: .jsonl file created even when ISSUE_NUMBER is unset"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
