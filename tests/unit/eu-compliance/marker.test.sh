#!/usr/bin/env bash
# QA Test: EU Compliance Agent — Pipeline Marker Detection
# Covers: AC-010
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

assert_not_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  ✅ PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: $description — unexpected pattern found: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== marker.test.sh: Pipeline Marker Detection ==="
echo ""

echo "--- AC-010: eu-compliance marker in rules file ---"
assert_contains \
  "eu-compliance.md contains <!-- pipeline-agent:eu-compliance --> marker" \
  ".claude/rules/eu-compliance.md" \
  "pipeline-agent:eu-compliance"

echo ""
echo "--- git-agent.md checks for eu-compliance, not legal ---"
assert_contains \
  "git-agent.md checks for eu-compliance marker" \
  ".claude/rules/git-agent.md" \
  "eu-compliance"

assert_not_contains \
  "git-agent.md no longer checks for old 'legal' marker in completeness list" \
  ".claude/rules/git-agent.md" \
  '"legal"'

echo ""
echo "--- CLAUDE.md references EU Compliance Agent ---"
assert_contains \
  "CLAUDE.md references eu-compliance in pipeline overview" \
  "CLAUDE.md" \
  "[Ee][Uu][ -][Cc]ompliance\|eu-compliance"

assert_contains \
  "CLAUDE.md references .claude/rules/eu-compliance.md" \
  "CLAUDE.md" \
  "eu-compliance.md"

echo ""
echo "--- AC-011: File at expected path ---"
if [ -f ".claude/rules/eu-compliance.md" ]; then
  echo "  ✅ PASS: .claude/rules/eu-compliance.md exists at correct path"
  PASS=$((PASS + 1))
else
  echo "  ❌ FAIL: .claude/rules/eu-compliance.md not found at expected path"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
