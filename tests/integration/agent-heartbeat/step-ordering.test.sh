#!/usr/bin/env bash
# QA Integration Test: Agent Heartbeat — Step Ordering
# Covers: AC-001 (started comment before substantive work)
# Verifies the started comment step appears BEFORE the first substantive step in each file

set -euo pipefail

PASS=0
FAIL=0

assert_step_order() {
  local description="$1"
  local file="$2"
  local started_pattern="$3"
  local substantive_pattern="$4"

  if [ ! -f "$file" ]; then
    echo "  FAIL: $description — file not found: $file"
    FAIL=$((FAIL + 1))
    return
  fi

  local started_line
  started_line=$(grep -n "$started_pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "")

  local substantive_line
  substantive_line=$(grep -n "$substantive_pattern" "$file" 2>/dev/null | head -1 | cut -d: -f1 || echo "")

  if [ -z "$started_line" ]; then
    echo "  FAIL: $description — started marker not found (pattern: $started_pattern)"
    FAIL=$((FAIL + 1))
    return
  fi

  if [ -z "$substantive_line" ]; then
    echo "  FAIL: $description — substantive step not found (pattern: $substantive_pattern)"
    FAIL=$((FAIL + 1))
    return
  fi

  if [ "$started_line" -lt "$substantive_line" ]; then
    echo "  PASS: $description (started at line $started_line, substantive at line $substantive_line)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — started comment (line $started_line) is NOT before substantive step (line $substantive_line)"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== step-ordering.test.sh (integration): Started Comment Appears Before Substantive Work ==="
echo ""

echo "--- AC-001: Started comment is the first agent action in each rules file ---"

# intake.md: started marker before "Analyse the Feature Request" / "Read issue"
assert_step_order \
  "intake.md: started comment before feature request analysis" \
  ".claude/rules/intake.md" \
  "pipeline-agent:intake-started" \
  "Analyse the Feature Request\|Read.*issue\|Step [12]:"

# git-agent.md: started marker before "Verify Pipeline Completeness"
assert_step_order \
  "git-agent.md: started comment before pipeline completeness check" \
  ".claude/rules/git-agent.md" \
  "pipeline-agent:git-started" \
  "Verify Pipeline\|Step [12]:"

# git-watcher.md: started marker before "Load Config" or "Find Ready Issues"
assert_step_order \
  "git-watcher.md: started comment before config load or polling" \
  ".claude/rules/git-watcher.md" \
  "pipeline-agent:watcher-started" \
  "Load Config\|Find Ready\|Step [12]:"

# eu-compliance.md: started marker before triage check or context read
assert_step_order \
  "eu-compliance.md: started comment before triage check" \
  ".claude/rules/eu-compliance.md" \
  "pipeline-agent:eu-compliance-started" \
  "Triage Check\|Read Context\|Step [12]:"

# architect.md: started marker before triage check or reading previous output
assert_step_order \
  "architect.md: started comment before triage check" \
  ".claude/rules/architect.md" \
  "pipeline-agent:architect-started" \
  "Triage Check\|Read.*Previous\|Step [12]:"

# solution-design.md: started marker before triage check or reading previous output
assert_step_order \
  "solution-design.md: started comment before triage check" \
  ".claude/rules/solution-design.md" \
  "pipeline-agent:solution-design-started" \
  "Triage Check\|Read.*Previous\|Step [12]:"

# qa.md: started marker before triage check or fetching context
assert_step_order \
  "qa.md: started comment before triage check" \
  ".claude/rules/qa.md" \
  "pipeline-agent:qa-started" \
  "Triage Check\|Fetch.*Context\|Step [12]:"

# developer.md: started marker before orientation / loading context
assert_step_order \
  "developer.md: started comment before context orientation" \
  ".claude/rules/developer.md" \
  "pipeline-agent:dev-.*-started\|pipeline-agent:dev-\\\$AGENT_NAME-started" \
  "Orient.*Load\|Load Context\|Step [12]:"

# code-quality.md: code-quality-started before triage/automated checks
assert_step_order \
  "code-quality.md: code-quality-started comment before triage check" \
  ".claude/rules/code-quality.md" \
  "pipeline-agent:code-quality-started" \
  "Triage Check\|Automated Checks\|Step [12]:"

# code-quality.md: security-started before security triage check
assert_step_order \
  "code-quality.md: security-started comment before security triage check" \
  ".claude/rules/code-quality.md" \
  "pipeline-agent:security-started" \
  "Triage Check\|Automated Scan\|Step [12]:"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && exit 0 || exit 1
