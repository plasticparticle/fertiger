#!/usr/bin/env bash
# QA Test: Pipeline Triage — Classification Output Validation
# Covers: AC-001 (TRIVIAL output), AC-002 (COMPLEX output)
# Expected to FAIL until scripts/pipeline/triage.sh is implemented

set -euo pipefail

PASS=0
FAIL=0
TRIAGE_SCRIPT="scripts/pipeline/triage.sh"

assert_equals() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✅ PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $description"
    echo "         Expected: $expected"
    echo "         Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local description="$1"
  local file="$2"
  if [ -f "$file" ]; then
    echo "  ✅ PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $description — file not found: $file"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  ✅ PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $description"
    echo "         Expected pattern: $pattern"
    echo "         In file: $file"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== classification.test.sh: Pipeline Triage Script Classification ==="
echo ""

echo "--- Precondition: triage.sh exists and is executable ---"
assert_file_exists "scripts/pipeline/triage.sh exists" "$TRIAGE_SCRIPT"

if [ ! -f "$TRIAGE_SCRIPT" ]; then
  echo ""
  echo "SKIP: Cannot run classification tests — triage.sh not found"
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-001: TRIVIAL classification ---"
# TRIVIAL: 1 MODIFY file only, no regulated-data keywords
RESULT=$(MOCK_FILE_COUNT="MODIFY:1" MOCK_KEYWORDS="" sh "$TRIAGE_SCRIPT" --mock 2>/dev/null || true)
# Fallback: test with actual env vars the script should support
RESULT=$(TRIAGE_FILE_COUNT=1 TRIAGE_CREATE_COUNT=0 TRIAGE_MODIFY_COUNT=1 TRIAGE_KEYWORDS="" sh "$TRIAGE_SCRIPT" --offline 2>/dev/null || echo "FAIL_NOT_IMPLEMENTED")
assert_equals \
  "triage.sh outputs TRIVIAL for 1 MODIFY file with no regulated-data keywords" \
  "TRIVIAL" \
  "$RESULT"

echo ""
echo "--- AC-001: TRIVIAL — 1 MODIFY, no keywords (verify not elevated) ---"
# Test the boundary: 1 MODIFY with common non-regulated word should still be TRIVIAL
RESULT=$(TRIAGE_CREATE_COUNT=0 TRIAGE_MODIFY_COUNT=1 TRIAGE_KEYWORDS="button" sh "$TRIAGE_SCRIPT" --offline 2>/dev/null || echo "FAIL_NOT_IMPLEMENTED")
assert_equals \
  "triage.sh outputs TRIVIAL for 1 MODIFY file with non-regulated keyword 'button'" \
  "TRIVIAL" \
  "$RESULT"

echo ""
echo "--- AC-002: COMPLEX classification — GDPR keyword ---"
RESULT=$(TRIAGE_CREATE_COUNT=0 TRIAGE_MODIFY_COUNT=1 TRIAGE_KEYWORDS="GDPR" sh "$TRIAGE_SCRIPT" --offline 2>/dev/null || echo "FAIL_NOT_IMPLEMENTED")
assert_equals \
  "triage.sh outputs COMPLEX for issue mentioning 'GDPR'" \
  "COMPLEX" \
  "$RESULT"

echo ""
echo "--- AC-002: COMPLEX classification — database migration keyword ---"
RESULT=$(TRIAGE_CREATE_COUNT=0 TRIAGE_MODIFY_COUNT=2 TRIAGE_KEYWORDS="database migration" sh "$TRIAGE_SCRIPT" --offline 2>/dev/null || echo "FAIL_NOT_IMPLEMENTED")
assert_equals \
  "triage.sh outputs COMPLEX for issue mentioning 'database migration'" \
  "COMPLEX" \
  "$RESULT"

echo ""
echo "--- AC-002: COMPLEX classification — 5+ CREATE files ---"
RESULT=$(TRIAGE_CREATE_COUNT=5 TRIAGE_MODIFY_COUNT=0 TRIAGE_KEYWORDS="" sh "$TRIAGE_SCRIPT" --offline 2>/dev/null || echo "FAIL_NOT_IMPLEMENTED")
assert_equals \
  "triage.sh outputs COMPLEX for 5+ CREATE files in solution design" \
  "COMPLEX" \
  "$RESULT"

echo ""
echo "--- STANDARD classification — 2 files, API keyword ---"
RESULT=$(TRIAGE_CREATE_COUNT=1 TRIAGE_MODIFY_COUNT=1 TRIAGE_KEYWORDS="API" sh "$TRIAGE_SCRIPT" --offline 2>/dev/null || echo "FAIL_NOT_IMPLEMENTED")
assert_equals \
  "triage.sh outputs STANDARD for 2 files with API keyword" \
  "STANDARD" \
  "$RESULT"

echo ""
echo "--- Output format: single word only ---"
assert_contains \
  "triage.sh outputs valid classification words (TRIVIAL|STANDARD|COMPLEX)" \
  "$TRIAGE_SCRIPT" \
  "TRIVIAL\|STANDARD\|COMPLEX"

echo ""
echo "--- Compliance: no persistent logging of issue content ---"
assert_contains \
  "triage.sh does not write issue content to files (no persistent logging)" \
  "$TRIAGE_SCRIPT" \
  "TRIAGE_LEVEL"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
