#!/usr/bin/env bash
# QA Test: EU Compliance Agent — Rules File Structure Validation
# Covers: AC-010, AC-011
# Expected to FAIL until .claude/rules/eu-compliance.md is implemented

set -euo pipefail

PASS=0
FAIL=0
RULES_FILE=".claude/rules/eu-compliance.md"

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

assert_file_absent() {
  local description="$1"
  local file="$2"
  if [ ! -f "$file" ]; then
    echo "  ✅ PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $description — file still exists: $file"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== rules-structure.test.sh: EU Compliance Agent Rules File Structure ==="
echo ""

echo "--- AC-011: File existence and location ---"
assert_file_exists "eu-compliance.md exists at .claude/rules/eu-compliance.md" "$RULES_FILE"

echo ""
echo "--- AC-010: Pipeline agent HTML comment marker ---"
assert_contains \
  "Rules file contains pipeline-agent:eu-compliance marker" \
  "$RULES_FILE" \
  "pipeline-agent:eu-compliance"

echo ""
echo "--- REQ-001: Full EU regulatory stack coverage ---"
assert_contains "Covers GDPR (Regulation 2016/679)" "$RULES_FILE" "2016/679"
assert_contains "Covers ePrivacy Directive (2002/58/EC)" "$RULES_FILE" "2002/58"
assert_contains "Covers EU AI Act (2024/1689)" "$RULES_FILE" "2024/1689"
assert_contains "Covers NIS2 (2022/2555)" "$RULES_FILE" "2022/2555"
assert_contains "Covers Cyber Resilience Act" "$RULES_FILE" "Cyber Resilience"
assert_contains "Covers Digital Services Act" "$RULES_FILE" "Digital Services Act\|DSA"
assert_contains "Covers Accessibility Act (EAA 2025)" "$RULES_FILE" "EAA 2025\|Accessibility Act"

echo ""
echo "--- REQ-003: Risk level classification language ---"
assert_contains "Contains BLOCKING risk level" "$RULES_FILE" "BLOCKING"
assert_contains "Contains CONDITIONAL risk level" "$RULES_FILE" "CONDITIONAL"
assert_contains "Contains ADVISORY risk level" "$RULES_FILE" "ADVISORY"

echo ""
echo "--- REQ-004: DPIA evaluation ---"
assert_contains "Contains DPIA section" "$RULES_FILE" "DPIA"
assert_contains "Contains WP29/EDPB reference" "$RULES_FILE" "WP29\|EDPB"
assert_contains "Contains DPIA REQUIRED outcome" "$RULES_FILE" "DPIA REQUIRED"
assert_contains "Contains DPIA NOT REQUIRED outcome" "$RULES_FILE" "NOT REQUIRED"
assert_contains "Contains DPIA BORDERLINE outcome" "$RULES_FILE" "BORDERLINE"

echo ""
echo "--- REQ-005: EU AI Act classification ---"
assert_contains "Contains EU AI Act risk tier classification" "$RULES_FILE" "AI Act\|EU AI"
assert_contains "Contains prohibited practices check (Article 5)" "$RULES_FILE" "Article 5\|Art. 5"

echo ""
echo "--- REQ-006: Mitigation plan structure ---"
assert_contains "Contains mitigation plan section" "$RULES_FILE" "[Mm]itigation"

echo ""
echo "--- REQ-007: Legal memo output format ---"
assert_contains "Contains legal memo step" "$RULES_FILE" "[Ll]egal [Mm]emo\|legal memo"

echo ""
echo "--- REQ-008: docs/COMPLIANCE.md update step ---"
assert_contains "References docs/COMPLIANCE.md" "$RULES_FILE" "docs/COMPLIANCE.md"

echo ""
echo "--- REQ-010: Replaces legal agent (old legal.md retired) ---"
assert_file_absent "Old .claude/rules/legal.md is removed" ".claude/rules/legal.md"

echo ""
echo "--- REQ-011: Compliance summary for Architect Agent ---"
assert_contains "Contains Compliance Constraints for Architecture section" \
  "$RULES_FILE" \
  "Compliance Constraints for Architecture\|compliance.*architect\|architect.*compliance"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
