#!/usr/bin/env bash
# QA Test: Pipeline Triage — Rules File Triage Gate Validation
# Covers: AC-003 (triage gate in each rules file), AC-004 (triage declaration in comment templates)
# Expected to FAIL until .claude/rules/*.md files are updated with triage gates

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

echo ""
echo "=== rules-gate.test.sh: Triage Gate Present in Agent Rules Files ==="
echo ""

RULES_FILES=(
  ".claude/rules/eu-compliance.md"
  ".claude/rules/architect.md"
  ".claude/rules/solution-design.md"
  ".claude/rules/qa.md"
  ".claude/rules/code-quality.md"
  ".claude/rules/security.md"
)

echo "--- AC-003: Each rules file contains a triage gate ---"
for f in "${RULES_FILES[@]}"; do
  echo ""
  echo "  Checking: $f"
  assert_file_exists "$f exists" "$f"
  assert_contains \
    "$f contains triage.sh invocation" \
    "$f" \
    "triage.sh\|TRIAGE_LEVEL"
  assert_contains \
    "$f documents TRIVIAL fast path" \
    "$f" \
    "TRIVIAL"
  assert_contains \
    "$f documents STANDARD path" \
    "$f" \
    "STANDARD"
  assert_contains \
    "$f documents COMPLEX full path" \
    "$f" \
    "COMPLEX"
done

echo ""
echo "--- AC-003: Triage gate is at Step 0 (before expensive operations) ---"
for f in "${RULES_FILES[@]}"; do
  assert_contains \
    "$f has Step 0 triage section" \
    "$f" \
    "Step 0\|Triage Check\|Triage Gate"
done

echo ""
echo "--- AC-003: full-review label path documented in each rules file ---"
for f in "${RULES_FILES[@]}"; do
  assert_contains \
    "$f references pipeline:full-review label override" \
    "$f" \
    "full-review\|pipeline:full-review"
done

echo ""
echo "--- AC-004: Each rules file includes triage declaration in comment template ---"
for f in "${RULES_FILES[@]}"; do
  assert_contains \
    "$f includes Triage declaration line in comment template" \
    "$f" \
    "\*\*Triage:\*\*\|Triage:.*TRIAGE_LEVEL\|\\\$TRIAGE_LEVEL"
done

echo ""
echo "--- triage.sh script exists at expected location ---"
assert_file_exists \
  "scripts/pipeline/triage.sh exists at scripts/pipeline/triage.sh" \
  "scripts/pipeline/triage.sh"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
