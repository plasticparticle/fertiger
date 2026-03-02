#!/usr/bin/env bash
# QA Integration Test: Estimator Agent — Pipeline Position & Integration
# Covers: AC-007, AC-008, and pipeline positioning requirements
# Expected to FAIL until CLAUDE.md is updated and estimator.md is created

set -euo pipefail

PASS=0
FAIL=0

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
echo "=== pipeline-position.test.sh: Estimator Pipeline Integration ==="
echo ""

echo "--- AC-007: CLAUDE.md shows Estimator between Intake and EU Compliance ---"

# Verify Estimator appears in CLAUDE.md pipeline diagram at all
assert_contains \
  "CLAUDE.md mentions Estimator agent" \
  "CLAUDE.md" \
  "[Ee]stimator"

# Verify the ordering: Intake before Estimator before EU Compliance
# Extract the relevant pipeline section lines and check order
INTAKE_LINE=$(grep -n "[Ii]ntake" CLAUDE.md | grep -i "pipeline\|agent\|→\|INTAKE" | head -1 | cut -d: -f1 || echo "0")
ESTIMATOR_LINE=$(grep -n "[Ee]stimator" CLAUDE.md | head -1 | cut -d: -f1 || echo "0")
EU_LINE=$(grep -n "[Ee][Uu].*[Cc]ompliance\|EU_COMPLIANCE\|eu-compliance" CLAUDE.md | head -1 | cut -d: -f1 || echo "0")

if [ "$INTAKE_LINE" -gt 0 ] && [ "$ESTIMATOR_LINE" -gt 0 ] && [ "$EU_LINE" -gt 0 ]; then
  if [ "$INTAKE_LINE" -lt "$ESTIMATOR_LINE" ] && [ "$ESTIMATOR_LINE" -lt "$EU_LINE" ]; then
    echo "  ✅ PASS: CLAUDE.md pipeline order: Intake (line $INTAKE_LINE) → Estimator (line $ESTIMATOR_LINE) → EU Compliance (line $EU_LINE)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: CLAUDE.md pipeline order incorrect"
    echo "         Intake at line $INTAKE_LINE, Estimator at $ESTIMATOR_LINE, EU Compliance at $EU_LINE"
    echo "         Expected: Intake < Estimator < EU Compliance"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  ❌ FAIL: Could not find all three agents in CLAUDE.md"
  echo "         Intake line: $INTAKE_LINE, Estimator line: $ESTIMATOR_LINE, EU Compliance line: $EU_LINE"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-007: CLAUDE.md Agent Rules list includes estimator.md ---"
assert_contains \
  "CLAUDE.md agent rules list references estimator.md" \
  "CLAUDE.md" \
  "estimator.md\|estimator"

echo ""
echo "--- AC-008: estimator.md updates project status to Legal Review ---"
assert_contains \
  "estimator.md calls set-status.sh with LEGAL_REVIEW" \
  ".claude/rules/estimator.md" \
  "LEGAL_REVIEW"

echo ""
echo "--- Pipeline trigger: estimator.md trigger is intake comment ---"
assert_contains \
  "estimator.md trigger references pipeline-agent:intake" \
  ".claude/rules/estimator.md" \
  "pipeline-agent:intake"

echo ""
echo "--- eu-compliance.md trigger still reads intake comment (not broken) ---"
assert_contains \
  "eu-compliance.md still references intake as its trigger/input" \
  ".claude/rules/eu-compliance.md" \
  "pipeline-agent:intake\|intake"

echo ""
echo "--- Rules file exists ---"
assert_file_exists \
  "estimator.md rules file exists" \
  ".claude/rules/estimator.md"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
