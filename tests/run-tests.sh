#!/usr/bin/env bash
# Test runner for fertiger pipeline validation tests
# Usage: ./tests/run-tests.sh [pattern]
#   pattern: optional grep pattern to filter test files (e.g. "eu-compliance")

set -euo pipefail

PATTERN="${1:-}"
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

# Find test files
if [ -n "$PATTERN" ]; then
  TEST_FILES=$(find tests/ -name "*.test.sh" | grep "$PATTERN" | sort)
else
  TEST_FILES=$(find tests/ -name "*.test.sh" | sort)
fi

if [ -z "$TEST_FILES" ]; then
  echo "No test files found matching pattern: ${PATTERN:-*}"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  fertiger test runner"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for test_file in $TEST_FILES; do
  chmod +x "$test_file"
  echo "Running: $test_file"
  if bash "$test_file"; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_SUITES+=("$test_file")
  fi
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SUMMARY: $TOTAL_PASS suites passed, $TOTAL_FAIL suites failed"
if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
  echo ""
  echo "  Failed suites:"
  for s in "${FAILED_SUITES[@]}"; do
    echo "    - $s"
  done
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $TOTAL_FAIL -gt 0 ]; then
  exit 1
fi
exit 0
