#!/usr/bin/env bash
# QA Integration Test: developer.md Script Integration
# Covers: AC-010
# Verifies developer.md references the pipeline scripts and no longer contains
# inline stack-detection logic

set -euo pipefail

PASS=0
FAIL=0

RULES_FILE=".claude/rules/developer.md"

assert_file_exists() {
  local description="$1"
  local file="$2"
  if [ -f "$file" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — file not found: $file"
    FAIL=$((FAIL + 1))
  fi
}

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
    echo "  FAIL: $description — still contains inline pattern: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== developer-md.test.sh: developer.md Script Integration (AC-010) ==="
echo ""

echo "--- Prerequisite: developer.md exists ---"
assert_file_exists "developer.md exists" "$RULES_FILE"

if [ ! -f "$RULES_FILE" ]; then
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-010: developer.md references detect-stack.sh ---"
assert_contains \
  "developer.md references scripts/pipeline/detect-stack.sh" \
  "$RULES_FILE" \
  "detect-stack"

echo ""
echo "--- AC-010: developer.md references run-tests.sh ---"
assert_contains \
  "developer.md references scripts/pipeline/run-tests.sh" \
  "$RULES_FILE" \
  "run-tests"

echo ""
echo "--- AC-010: developer.md references swarm-lock.sh ---"
assert_contains \
  "developer.md references scripts/pipeline/swarm-lock.sh" \
  "$RULES_FILE" \
  "swarm-lock"

echo ""
echo "--- AC-010: developer.md references check-deps.sh ---"
assert_contains \
  "developer.md references scripts/pipeline/check-deps.sh" \
  "$RULES_FILE" \
  "check-deps"

echo ""
echo "--- AC-010: developer.md no longer contains inline stack detection table ---"
# The old developer.md had an inline table: | package.json | Node/JS/TS | ...
# This should be replaced by a reference to detect-stack.sh
assert_not_contains \
  "developer.md does not contain old inline stack-detection logic (ls package.json Cargo.toml ...)" \
  "$RULES_FILE" \
  "ls package.json Cargo.toml go.mod requirements.txt"

echo ""
echo "--- AC-010: developer.md references scripts/pipeline/ directory ---"
assert_contains \
  "developer.md references scripts/pipeline/ path" \
  "$RULES_FILE" \
  "scripts/pipeline"

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
