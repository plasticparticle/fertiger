#!/usr/bin/env bash
# QA Unit Test: Agent Heartbeat — Progress Updates
# Covers: AC-003, AC-004
# Tests FAIL until .claude/rules/ files are updated with Step 0 started comments

set -euo pipefail

PASS=0
FAIL=0

assert_contains() {
  local description="$1"
  local file="$2"
  local pattern="$3"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
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
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — still contains pattern: $pattern"
    echo "         In file: $file"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== progress-updates.test.sh (unit): Progress Updates ==="
echo ""

echo "--- AC-003: developer.md uses phase-level progress updates, not per-file ---"

DEVELOPER_MD=".claude/rules/developer.md"

# Developer agent must reference solution design phases in progress updates
assert_contains \
  "developer.md references phase-level progress (data layer or service layer or API layer)" \
  "$DEVELOPER_MD" \
  "[Dd]ata [Ll]ayer\|[Ss]ervice.*[Ll]ayer\|[Aa][Pp][Ii].*[Ll]ayer\|[Pp]hase"

# Developer agent marker must be -started (not -start, the old non-standard marker)
assert_contains \
  "developer.md uses -started suffix (not legacy -start)" \
  "$DEVELOPER_MD" \
  "pipeline-agent:dev-.*-started"

assert_not_contains \
  "developer.md no longer uses legacy -start suffix alone" \
  "$DEVELOPER_MD" \
  "pipeline-agent:dev-.*-start -->"

echo ""
echo "--- AC-004: Long-running agents post at least one mid-run progress update ---"

# EU Compliance agent: covers regulation groups
assert_contains \
  "eu-compliance.md has progress update mechanism (gh api PATCH or comment edit)" \
  ".claude/rules/eu-compliance.md" \
  "progress\|[Pp]rogress\|PATCH\|updating.*started\|started.*comment"

# Architect agent: updates after codebase read and after ADRs
assert_contains \
  "architect.md has progress update mechanism" \
  ".claude/rules/architect.md" \
  "progress\|[Pp]rogress\|PATCH\|updating.*started\|started.*comment"

# QA agent: updates after each test suite
assert_contains \
  "qa.md has progress update mechanism" \
  ".claude/rules/qa.md" \
  "progress\|[Pp]rogress\|PATCH\|updating.*started\|started.*comment"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
