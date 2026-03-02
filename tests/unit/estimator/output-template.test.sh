#!/usr/bin/env bash
# QA Unit Test: Estimator Agent — Output Template Completeness
# Covers: AC-001, AC-002, AC-003, AC-004, AC-005 (output template shape)
# Verifies the comment template in estimator.md contains all required fields
# Expected to FAIL until .claude/rules/estimator.md is implemented

set -euo pipefail

PASS=0
FAIL=0
RULES_FILE=".claude/rules/estimator.md"

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

assert_not_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  ✅ PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $description — should not contain: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== output-template.test.sh: Estimator Agent Comment Template ==="
echo ""

if [ ! -f "$RULES_FILE" ]; then
  echo "  ❌ FAIL: $RULES_FILE does not exist — cannot check template"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo "--- AC-001: gh issue comment call with estimator marker ---"
assert_contains \
  "Rules file uses gh issue comment to post output" \
  "$RULES_FILE" \
  "gh issue comment"

assert_contains \
  "Comment body includes pipeline-agent:estimator HTML marker" \
  "$RULES_FILE" \
  "pipeline-agent:estimator"

echo ""
echo "--- AC-002: Business Value section header present in template ---"
assert_contains \
  "Comment template contains Business Value section" \
  "$RULES_FILE" \
  "[Bb]usiness [Vv]alue\|Business Value"

assert_contains \
  "Comment template has revenue dimension label" \
  "$RULES_FILE" \
  "[Rr]evenue"

assert_contains \
  "Comment template has strategic dimension label" \
  "$RULES_FILE" \
  "[Ss]trategic"

echo ""
echo "--- AC-003: Customer Impact section header present in template ---"
assert_contains \
  "Comment template contains Customer Impact section" \
  "$RULES_FILE" \
  "[Cc]ustomer [Ii]mpact\|Customer Impact"

echo ""
echo "--- AC-004: Complexity section header present in template ---"
assert_contains \
  "Comment template contains Complexity section" \
  "$RULES_FILE" \
  "[Cc]omplexity"

echo ""
echo "--- AC-004: Pipeline ROI Statement required ---"
assert_contains \
  "Comment template contains ROI Statement section" \
  "$RULES_FILE" \
  "[Rr][Oo][Ii]\|ROI Statement\|roi"

echo ""
echo "--- AC-005: Enterprise comparison block header in template ---"
assert_contains \
  "Comment template contains 'If This Were a Traditional Enterprise Project' or similar" \
  "$RULES_FILE" \
  "[Ee]nterprise"

echo ""
echo "--- Negative: No hardcoded issue numbers in template ---"
assert_not_contains \
  "Template does not hardcode a specific issue number (use \$ISSUE_NUMBER)" \
  "$RULES_FILE" \
  "issue #5\|Issue #5"

echo ""
echo "--- Trigger condition: runs after intake comment ---"
assert_contains \
  "Rules file trigger references intake comment marker" \
  "$RULES_FILE" \
  "pipeline-agent:intake\|intake"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
