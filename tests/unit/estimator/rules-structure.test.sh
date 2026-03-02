#!/usr/bin/env bash
# QA Unit Test: Estimator Agent — Rules File Structure
# Covers: AC-001, AC-002, AC-003, AC-004, AC-005, AC-006, AC-008, AC-009
# Expected to FAIL until .claude/rules/estimator.md is implemented

set -euo pipefail

PASS=0
FAIL=0
RULES_FILE=".claude/rules/estimator.md"

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
echo "=== rules-structure.test.sh: Estimator Agent Rules File ==="
echo ""

echo "--- Prerequisite: estimator.md exists ---"
assert_file_exists "estimator.md exists at .claude/rules/estimator.md" "$RULES_FILE"

if [ ! -f "$RULES_FILE" ]; then
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-001: Comment output includes pipeline-agent:estimator marker ---"
assert_contains \
  "Rules file contains pipeline-agent:estimator comment marker" \
  "$RULES_FILE" \
  "pipeline-agent:estimator"

echo ""
echo "--- AC-002: Business value scores — revenue, strategic, user ---"
assert_contains \
  "Rules file includes revenue impact scoring dimension" \
  "$RULES_FILE" \
  "[Rr]evenue"

assert_contains \
  "Rules file includes strategic value scoring dimension" \
  "$RULES_FILE" \
  "[Ss]trategic"

assert_contains \
  "Rules file includes user value scoring dimension" \
  "$RULES_FILE" \
  "[Uu]ser value\|user_value\|User Value"

assert_contains \
  "Rules file requires justification for each value score" \
  "$RULES_FILE" \
  "[Jj]ustification\|justif"

echo ""
echo "--- AC-003: Customer impact profile fields ---"
assert_contains \
  "Rules file includes persona field in customer impact" \
  "$RULES_FILE" \
  "[Pp]ersona"

assert_contains \
  "Rules file includes reach classification (ALL/MAJORITY/MINORITY/EDGE CASE)" \
  "$RULES_FILE" \
  "MAJORITY\|MINORITY\|EDGE CASE\|ALL"

assert_contains \
  "Rules file includes immediate vs latent impact distinction" \
  "$RULES_FILE" \
  "[Ii]mmediate\|[Ll]atent"

assert_contains \
  "Rules file includes pain field (YES/NO/UNKNOWN)" \
  "$RULES_FILE" \
  "UNKNOWN\|[Pp]ain"

echo ""
echo "--- AC-004: Complexity — T-shirt size and risk level ---"
assert_contains \
  "Rules file includes T-shirt size options (XS/S/M/L/XL)" \
  "$RULES_FILE" \
  "XS\|T-shirt\|t-shirt\|tshirt"

assert_contains \
  "Rules file includes risk level options" \
  "$RULES_FILE" \
  "CRITICAL\|LOW.*MEDIUM.*HIGH\|risk level\|Risk Level"

echo ""
echo "--- AC-005: Enterprise comparison block with 4 sub-sections ---"
assert_contains \
  "Rules file includes enterprise comparison block" \
  "$RULES_FILE" \
  "[Ee]nterprise\|Traditional Enterprise"

assert_contains \
  "Rules file includes timeline by phase in enterprise block" \
  "$RULES_FILE" \
  "[Tt]imeline\|[Pp]hase"

assert_contains \
  "Rules file includes cast list of roles" \
  "$RULES_FILE" \
  "[Cc]ast\|[Rr]oles"

assert_contains \
  "Rules file includes meeting inventory with person-hours" \
  "$RULES_FILE" \
  "[Mm]eeting\|person-hours\|person_hours"

assert_contains \
  "Rules file includes documentation list in enterprise block" \
  "$RULES_FILE" \
  "[Dd]ocumentation\|[Dd]ocs"

echo ""
echo "--- AC-006: Enterprise timeline brackets tied to T-shirt size ---"
assert_contains \
  "Rules file references XS timeline bracket (≤ 4 weeks)" \
  "$RULES_FILE" \
  "XS.*4\|4.*week\|four.*week\|≤ 4"

assert_contains \
  "Rules file references XL timeline bracket (> 24 weeks)" \
  "$RULES_FILE" \
  "XL.*24\|24.*week\|twenty.*four\|> 24"

echo ""
echo "--- AC-008: Status updated to Legal Review after posting ---"
assert_contains \
  "Rules file calls set-status.sh LEGAL_REVIEW after posting" \
  "$RULES_FILE" \
  "set-status.sh.*LEGAL_REVIEW\|LEGAL_REVIEW"

echo ""
echo "--- AC-009: estimator-started heartbeat marker ---"
assert_contains \
  "Rules file contains estimator-started heartbeat comment marker" \
  "$RULES_FILE" \
  "pipeline-agent:estimator-started"

echo ""
echo "--- Structure: Rules file follows standard agent step numbering ---"
assert_contains \
  "Rules file contains Step 0 (heartbeat)" \
  "$RULES_FILE" \
  "Step 0\|## Step 0"

assert_contains \
  "Rules file contains Step 1 (context reading)" \
  "$RULES_FILE" \
  "Step 1\|## Step 1"

assert_contains \
  "Rules file sources config.sh" \
  "$RULES_FILE" \
  "source .claude/config.sh\|source \$\|config.sh"

assert_contains \
  "Rules file uses log.sh for progress tracking" \
  "$RULES_FILE" \
  "log.sh\|scripts/pipeline/log"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
