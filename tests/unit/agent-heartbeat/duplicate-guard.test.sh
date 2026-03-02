#!/usr/bin/env bash
# QA Unit Test: Agent Heartbeat — Duplicate Guard & Fire-and-Forget
# Covers: AC-005, AC-006
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

echo ""
echo "=== duplicate-guard.test.sh (unit): Duplicate Guard & Fire-and-Forget ==="
echo ""

echo "--- AC-005: Each GitHub-posting agent has a duplicate guard using test() jq pattern ---"

GITHUB_POSTING_AGENTS=(
  ".claude/rules/intake.md"
  ".claude/rules/git-agent.md"
  ".claude/rules/git-watcher.md"
  ".claude/rules/eu-compliance.md"
  ".claude/rules/architect.md"
  ".claude/rules/solution-design.md"
  ".claude/rules/qa.md"
  ".claude/rules/developer.md"
  ".claude/rules/code-quality.md"
)

for file in "${GITHUB_POSTING_AGENTS[@]}"; do
  assert_contains \
    "$file has duplicate guard using test() jq pattern" \
    "$file" \
    'test(".*-started")\|test(\".*-started\")'
done

echo ""
echo "--- AC-006: Started comment posting uses fire-and-forget (|| true) ---"

for file in "${GITHUB_POSTING_AGENTS[@]}"; do
  assert_contains \
    "$file started comment uses || true fire-and-forget" \
    "$file" \
    "|| true"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
