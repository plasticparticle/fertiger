#!/usr/bin/env bash
# QA Test: EU Compliance Agent — Legal Agent Retirement Regression
# Covers: REQ-010 (eu-compliance replaces legal agent)
# Expected to FAIL until legal.md is removed and references updated

set -euo pipefail

PASS=0
FAIL=0

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
    echo "  ❌ FAIL: $description — file still exists (should be retired): $file"
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
    echo "         Expected: $pattern in $file"
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
    echo "  ❌ FAIL: $description — found unexpected content: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== legal-agent-retired.test.sh: Legal Agent Retirement Regression ==="
echo ""

echo "--- REQ-010: Old legal.md is retired ---"
assert_file_absent \
  ".claude/rules/legal.md is removed from active rules" \
  ".claude/rules/legal.md"

echo ""
echo "--- REQ-010: New eu-compliance.md is present ---"
assert_file_exists \
  ".claude/rules/eu-compliance.md exists as replacement" \
  ".claude/rules/eu-compliance.md"

echo ""
echo "--- CLAUDE.md no longer references Legal Agent as primary ---"
# CLAUDE.md should reference EU Compliance, not old Legal Agent
assert_contains \
  "CLAUDE.md mentions EU Compliance Agent" \
  "CLAUDE.md" \
  "[Ee][Uu][ -][Cc]ompliance\|eu-compliance"

assert_contains \
  "CLAUDE.md references eu-compliance.md rules file" \
  "CLAUDE.md" \
  "eu-compliance.md"

echo ""
echo "--- git-agent.md completeness check updated ---"
assert_contains \
  "git-agent.md checks for eu-compliance agent in completeness list" \
  ".claude/rules/git-agent.md" \
  "eu-compliance"

# The string '"legal"' should no longer appear as a standalone required agent
# (legal may still appear in other contexts like "legal review" as a status)
assert_not_contains \
  "git-agent.md does not require old 'legal' pipeline-agent marker" \
  ".claude/rules/git-agent.md" \
  '`legal`'

echo ""
echo "--- No stale references to pipeline-agent:legal in agent rules ---"
for f in .claude/rules/*.md; do
  if [ "$f" = ".claude/rules/legal.md" ]; then
    continue
  fi
  if grep -q "pipeline-agent:legal" "$f" 2>/dev/null; then
    echo "  ❌ FAIL: Stale reference to pipeline-agent:legal found in $f"
    FAIL=$((FAIL + 1))
  fi
done
echo "  ✅ PASS: No stale pipeline-agent:legal references in active rules files"
PASS=$((PASS + 1))

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
