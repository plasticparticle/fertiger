#!/usr/bin/env bash
# QA Unit Test: Agent Heartbeat — Stdout-Only Agents (setup.md, pipeline-update.md)
# Covers: AC-001, AC-002 (stdout variant per ADR-013)
# Tests FAIL until .claude/rules/ files are updated

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
    echo "  FAIL: $description — should not contain: $pattern"
    echo "         In file: $file"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== stdout-only-agents.test.sh (unit): Stdout-Only Agents (setup + pipeline-update) ==="
echo ""

echo "--- AC-001: setup.md and pipeline-update.md print a started message ---"

assert_contains \
  "setup.md has a started/starting echo or print statement" \
  ".claude/rules/setup.md" \
  "[Ss]tarted\|[Ss]tarting\|echo.*[Ss]etup\|echo.*[Ss]tart"

assert_contains \
  "pipeline-update.md has a started/starting echo or print statement" \
  ".claude/rules/pipeline-update.md" \
  "[Ss]tarted\|[Ss]tarting\|echo.*[Uu]pdate\|echo.*[Ss]tart"

echo ""
echo "--- AC-002: setup.md and pipeline-update.md do NOT use GitHub comment for started ---"
echo "    (no ISSUE_NUMBER context available — stdout only per ADR-013)"

assert_not_contains \
  "setup.md does not post a GitHub issue comment for started heartbeat" \
  ".claude/rules/setup.md" \
  "pipeline-agent:setup-started"

assert_not_contains \
  "pipeline-update.md does not post a GitHub issue comment for started heartbeat" \
  ".claude/rules/pipeline-update.md" \
  "pipeline-agent:pipeline-update-started"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
