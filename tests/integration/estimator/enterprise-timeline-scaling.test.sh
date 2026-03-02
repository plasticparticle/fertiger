#!/usr/bin/env bash
# QA Integration Test: Estimator Agent — Enterprise Timeline Scaling Rules
# Covers: AC-006 — timeline must scale with T-shirt size
# Verifies the rules file enforces timeline brackets from ADR-011
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

echo ""
echo "=== enterprise-timeline-scaling.test.sh: AC-006 Timeline Bracket Rules ==="
echo ""

if [ ! -f "$RULES_FILE" ]; then
  echo "  ❌ FAIL: $RULES_FILE does not exist"
  FAIL=$((FAIL + 1))
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo "--- AC-006: Timeline bracket anchors are defined (ADR-011) ---"

assert_contains \
  "Rules file defines XS bracket (≤ 4 weeks)" \
  "$RULES_FILE" \
  "XS.*4\|XS.*four\|4.*week.*XS\|≤ 4"

assert_contains \
  "Rules file defines S bracket (≤ 8 weeks)" \
  "$RULES_FILE" \
  "S.*8\| S.*eight\|8.*week.*[^X][SML]\|≤ 8"

assert_contains \
  "Rules file defines M bracket (≤ 16 weeks)" \
  "$RULES_FILE" \
  "M.*16\|16.*week\|≤ 16"

assert_contains \
  "Rules file defines L bracket (≤ 24 weeks)" \
  "$RULES_FILE" \
  "L.*24\|24.*week.*L\|≤ 24"

assert_contains \
  "Rules file defines XL bracket (> 24 weeks)" \
  "$RULES_FILE" \
  "XL.*24\|> 24\|more.*24\|longer.*24"

echo ""
echo "--- AC-006: T-shirt size must be evaluated BEFORE enterprise block ---"
# The rules must require evaluating size before generating enterprise comparison
# Check that the size determination logically precedes the enterprise block
TSHIRT_LINE=$(grep -n "T-shirt\|t-shirt\|tshirt\|XS/S/M/L/XL\|XS.*S.*M.*L.*XL" "$RULES_FILE" | head -1 | cut -d: -f1 || echo "0")
ENTERPRISE_LINE=$(grep -n "[Ee]nterprise\|Traditional.*Enterprise\|If This Were" "$RULES_FILE" | head -1 | cut -d: -f1 || echo "0")

if [ "$TSHIRT_LINE" -gt 0 ] && [ "$ENTERPRISE_LINE" -gt 0 ]; then
  if [ "$TSHIRT_LINE" -lt "$ENTERPRISE_LINE" ]; then
    echo "  ✅ PASS: T-shirt size evaluation (line $TSHIRT_LINE) appears before enterprise block (line $ENTERPRISE_LINE)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: Enterprise block (line $ENTERPRISE_LINE) appears before T-shirt sizing (line $TSHIRT_LINE)"
    echo "         AC-006 requires size evaluation BEFORE generating enterprise timelines"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  ❌ FAIL: Could not locate both T-shirt sizing and enterprise block in $RULES_FILE"
  echo "         T-shirt line: $TSHIRT_LINE, Enterprise line: $ENTERPRISE_LINE"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-006: Timeline output is described as illustrative / advisory ---"
assert_contains \
  "Rules file marks enterprise timeline as advisory/illustrative" \
  "$RULES_FILE" \
  "[Aa]dvisory\|[Ii]llustrative\|not.*binding\|illustrate\|advisory"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
