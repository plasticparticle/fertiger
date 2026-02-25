#!/usr/bin/env bash
# QA Test: EU Compliance Agent — Pipeline Flow Integration
# Covers: AC-004 (BLOCKED → no branch), AC-007 (DPIA → DPO escalation)
# Expected to FAIL until .claude/rules/eu-compliance.md is implemented

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

echo ""
echo "=== pipeline-flow.test.sh: EU Compliance Agent Pipeline Integration ==="
echo ""

RULES_FILE=".claude/rules/eu-compliance.md"

echo "--- AC-004: BLOCKED verdict prevents branch creation ---"
assert_contains \
  "Rules file contains BLOCKED → no branch creation logic" \
  "$RULES_FILE" \
  "BLOCKED.*branch\|branch.*BLOCKED\|no branch.*BLOCKED\|pipeline:blocked"

assert_contains \
  "Rules file sets pipeline:blocked label on BLOCKED verdict" \
  "$RULES_FILE" \
  "pipeline:blocked"

echo ""
echo "--- AC-007: DPIA REQUIRED → pipeline:blocked + DPO escalation ---"
assert_contains \
  "Rules file contains DPO escalation step" \
  "$RULES_FILE" \
  "[Dd][Pp][Oo]\|DPO escalation"

assert_contains \
  "Rules file tags TECH_LEAD on DPO escalation" \
  "$RULES_FILE" \
  'TECH_LEAD\|\$TECH_LEAD\|@.*TECH_LEAD'

assert_contains \
  "Rules file sets pipeline:blocked on DPIA REQUIRED" \
  "$RULES_FILE" \
  "DPIA.*pipeline:blocked\|pipeline:blocked.*DPIA"

echo ""
echo "--- REQ-010: Runs after Intake, before Architect (pipeline position) ---"
# Verify CLAUDE.md shows eu-compliance positioned between Intake and Architect
assert_contains \
  "CLAUDE.md shows EU Compliance Agent in pipeline sequence" \
  "CLAUDE.md" \
  "[Ee][Uu][ -][Cc]ompliance"

echo ""
echo "--- REQ-011: Passes structured summary to Architect Agent ---"
assert_contains \
  "Rules file produces structured compliance summary for downstream agents" \
  "$RULES_FILE" \
  "Compliance Constraints for Architecture\|compliance.*constraints\|constraints.*architect"

echo ""
echo "--- architect.md reads eu-compliance output ---"
assert_contains \
  "architect.md reads eu-compliance comment" \
  ".claude/rules/architect.md" \
  "eu-compliance\|EU Compliance\|Compliance Constraints"

echo ""
echo "--- Pipeline status transitions are defined ---"
assert_contains \
  "Rules file contains status transition to Architecture (on COMPLIANT/CONDITIONAL)" \
  "$RULES_FILE" \
  "ARCHITECTURE_OPTION_ID\|Architecture"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
