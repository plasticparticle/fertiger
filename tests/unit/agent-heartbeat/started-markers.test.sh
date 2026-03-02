#!/usr/bin/env bash
# QA Unit Test: Agent Heartbeat — Started Comment Markers
# Covers: AC-001, AC-002
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
echo "=== started-markers.test.sh (unit): Agent Heartbeat — Started Comment Markers ==="
echo ""

echo "--- AC-001 + AC-002: Every agent rules file has pipeline-agent:[name]-started marker ---"

# Phase 1 — Simple agents
assert_contains \
  "intake.md has pipeline-agent:intake-started marker" \
  ".claude/rules/intake.md" \
  "pipeline-agent:intake-started"

assert_contains \
  "git-agent.md has pipeline-agent:git-started marker" \
  ".claude/rules/git-agent.md" \
  "pipeline-agent:git-started"

assert_contains \
  "git-watcher.md has pipeline-agent:watcher-started marker" \
  ".claude/rules/git-watcher.md" \
  "pipeline-agent:watcher-started"

# Phase 2 — Agents with triage step
assert_contains \
  "eu-compliance.md has pipeline-agent:eu-compliance-started marker" \
  ".claude/rules/eu-compliance.md" \
  "pipeline-agent:eu-compliance-started"

assert_contains \
  "architect.md has pipeline-agent:architect-started marker" \
  ".claude/rules/architect.md" \
  "pipeline-agent:architect-started"

assert_contains \
  "solution-design.md has pipeline-agent:solution-design-started marker" \
  ".claude/rules/solution-design.md" \
  "pipeline-agent:solution-design-started"

assert_contains \
  "qa.md has pipeline-agent:qa-started marker" \
  ".claude/rules/qa.md" \
  "pipeline-agent:qa-started"

# Phase 3 — Developer agent
assert_contains \
  "developer.md has pipeline-agent:dev-[name]-started marker" \
  ".claude/rules/developer.md" \
  "pipeline-agent:dev-.*-started\|pipeline-agent:dev-\$AGENT_NAME-started"

# Phase 4 — Dual-agent file
assert_contains \
  "code-quality.md has pipeline-agent:code-quality-started marker" \
  ".claude/rules/code-quality.md" \
  "pipeline-agent:code-quality-started"

assert_contains \
  "code-quality.md has pipeline-agent:security-started marker" \
  ".claude/rules/code-quality.md" \
  "pipeline-agent:security-started"

echo ""
echo "--- AC-002: Markers use correct HTML comment format ---"

for file in \
  ".claude/rules/intake.md" \
  ".claude/rules/git-agent.md" \
  ".claude/rules/eu-compliance.md" \
  ".claude/rules/architect.md" \
  ".claude/rules/solution-design.md" \
  ".claude/rules/qa.md" \
  ".claude/rules/developer.md" \
  ".claude/rules/code-quality.md"; do
  assert_contains \
    "$file uses HTML comment format for started marker" \
    "$file" \
    "<!-- pipeline-agent:.*-started"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
