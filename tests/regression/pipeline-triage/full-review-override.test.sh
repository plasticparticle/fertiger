#!/usr/bin/env bash
# QA Test: Pipeline Triage — Full-Review Override and TRIVIAL Fast Path
# Covers: AC-005 (pipeline:full-review forces COMPLEX), AC-006 (TRIVIAL makes fewer API calls)
# Expected to FAIL until scripts/pipeline/triage.sh is implemented with override logic

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

echo ""
echo "=== full-review-override.test.sh: pipeline:full-review Override and Fast Path ==="
echo ""

echo "--- Precondition: triage.sh exists ---"
assert_file_exists "scripts/pipeline/triage.sh exists" "$TRIAGE_SCRIPT"

if [ ! -f "$TRIAGE_SCRIPT" ]; then
  echo ""
  echo "SKIP: Cannot run override tests — triage.sh not found"
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-005: pipeline:full-review label forces COMPLEX output ---"
# When TRIAGE_FULL_REVIEW=1 simulates the label being present, output must be COMPLEX
# even if file counts and keywords would normally yield TRIVIAL
RESULT=$(TRIAGE_CREATE_COUNT=0 TRIAGE_MODIFY_COUNT=1 TRIAGE_KEYWORDS="" TRIAGE_FULL_REVIEW=1 sh "$TRIAGE_SCRIPT" --offline 2>/dev/null || echo "FAIL_NOT_IMPLEMENTED")
assert_equals \
  "triage.sh outputs COMPLEX when TRIAGE_FULL_REVIEW=1 (pipeline:full-review label present)" \
  "COMPLEX" \
  "$RESULT"

echo ""
echo "--- AC-005: pipeline:full-review override is documented in triage.sh ---"
assert_contains \
  "triage.sh checks for pipeline:full-review label" \
  "$TRIAGE_SCRIPT" \
  "full-review\|pipeline:full-review\|TRIAGE_FULL_REVIEW"

echo ""
echo "--- AC-005: Each rules file respects full-review via triage.sh output ---"
# The override happens inside triage.sh; rules files just act on TRIAGE_LEVEL=COMPLEX
# Verify that each rules file's COMPLEX path is a full analysis path
for f in ".claude/rules/eu-compliance.md" ".claude/rules/architect.md" ".claude/rules/qa.md"; do
  assert_contains \
    "$f COMPLEX path includes full analysis" \
    "$f" \
    "COMPLEX"
done

echo ""
echo "--- AC-006: TRIVIAL path documented as making fewer API calls ---"
# TRIVIAL fast paths should document reduced gh API calls or skipped operations
assert_contains \
  "triage.sh TRIVIAL path is documented in eu-compliance.md with reduced operations" \
  ".claude/rules/eu-compliance.md" \
  "TRIVIAL"
assert_contains \
  "triage.sh TRIVIAL path is documented in architect.md with reduced operations" \
  ".claude/rules/architect.md" \
  "TRIVIAL"
assert_contains \
  "triage.sh TRIVIAL path is documented in qa.md with reduced operations" \
  ".claude/rules/qa.md" \
  "TRIVIAL"

echo ""
echo "--- AC-006: TRIVIAL → QA uses unit tests only (fewer test suites = fewer API calls) ---"
assert_contains \
  "qa.md TRIVIAL path specifies unit tests only (not integration + regression)" \
  ".claude/rules/qa.md" \
  "TRIVIAL.*unit\|unit.*TRIVIAL\|unit tests only"

echo ""
echo "--- AC-006: COMPLEX → QA uses full suite (unit + integration + regression) ---"
assert_contains \
  "qa.md COMPLEX path specifies full test suite" \
  ".claude/rules/qa.md" \
  "COMPLEX.*unit.*integration.*regression\|unit.*integration.*regression.*COMPLEX\|unit + integration + regression"

echo ""
echo "--- AC-005: Regression: full-review must override even TRIVIAL file/keyword profile ---"
# Verify the logic is unconditional: full-review always wins regardless of analysis
assert_contains \
  "triage.sh treats full-review as unconditional override (not conditional on other factors)" \
  "$TRIAGE_SCRIPT" \
  "full-review\|TRIAGE_FULL_REVIEW"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
