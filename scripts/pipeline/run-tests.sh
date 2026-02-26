#!/usr/bin/env bash
# run-tests.sh — Language-Agnostic Test Runner Wrapper
#
# Usage:
#   scripts/pipeline/run-tests.sh           # run all tests
#   scripts/pipeline/run-tests.sh "filter"  # run tests matching filter
#
# Sources detect-stack.sh to determine the stack and test runner.
# Translates filter argument to the correct runner-specific flag.
# Exits non-zero on any test failure.
# Outputs: "PASS: N tests" or "FAIL: N passed, M failed"
#
# Must be POSIX-compatible (bash 3.2+)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILTER="${1:-}"

# Source stack detection from the same directory
if [ ! -f "$SCRIPT_DIR/detect-stack.sh" ]; then
  echo "ERROR: run-tests.sh — cannot find detect-stack.sh in $SCRIPT_DIR" >&2
  exit 1
fi

# Detect the stack — this repo uses shell scripts, fall back gracefully
STACK_OK=0
# shellcheck source=./detect-stack.sh
. "$SCRIPT_DIR/detect-stack.sh" 2>/dev/null && STACK_OK=1 || STACK_OK=0

if [ "$STACK_OK" -eq 0 ]; then
  # This is a shell-script project — use the project's built-in test runner
  echo "INFO: No standard stack detected — using shell test runner (tests/run-tests.sh)" >&2
  RUNNER_TYPE="shell"
else
  RUNNER_TYPE="$STACK_LANGUAGE"
fi

# Build the test command based on runner type and filter
build_test_cmd() {
  local runner="$1"
  local filter="$2"

  case "$runner" in
    typescript|javascript)
      if [ -n "$filter" ]; then
        echo "$STACK_TEST_CMD --testPathPattern='$filter'"
      else
        echo "$STACK_TEST_CMD"
      fi
      ;;
    python)
      if [ -n "$filter" ]; then
        echo "pytest $filter"
      else
        echo "pytest"
      fi
      ;;
    go)
      if [ -n "$filter" ]; then
        echo "go test ./... -run $filter"
      else
        echo "go test ./..."
      fi
      ;;
    rust)
      if [ -n "$filter" ]; then
        echo "cargo test $filter"
      else
        echo "cargo test"
      fi
      ;;
    java|kotlin)
      if [ -n "$filter" ]; then
        echo "./gradlew test --tests '*$filter*'"
      else
        echo "./gradlew test"
      fi
      ;;
    maven)
      if [ -n "$filter" ]; then
        echo "mvn test -Dtest=$filter"
      else
        echo "mvn test"
      fi
      ;;
    shell|*)
      # Shell project — use the project's own test runner
      if [ -n "$filter" ]; then
        echo "bash tests/run-tests.sh '$filter'"
      else
        echo "bash tests/run-tests.sh"
      fi
      ;;
  esac
}

TEST_CMD=$(build_test_cmd "$RUNNER_TYPE" "$FILTER")
echo "INFO: Running: $TEST_CMD" >&2

# Run the tests and capture output
TEST_OUTPUT=""
TEST_EXIT=0

TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1) || TEST_EXIT=$?

# Parse pass/fail counts from output where possible
PASS_COUNT=0
FAIL_COUNT=0

case "$RUNNER_TYPE" in
  typescript|javascript)
    # Jest output: "Tests: N passed, M failed, X total"
    PASS_COUNT=$(echo "$TEST_OUTPUT" | grep -E "Tests:" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+" | tail -1 || echo "0")
    FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -E "Tests:" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+" | tail -1 || echo "0")
    ;;
  shell|*)
    # Shell runner output: "N suites passed, M suites failed"
    PASS_COUNT=$(echo "$TEST_OUTPUT" | grep "SUMMARY:" | grep -oE "[0-9]+ suites passed" | grep -oE "[0-9]+" || echo "0")
    FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep "SUMMARY:" | grep -oE "[0-9]+ suites failed" | grep -oE "[0-9]+" || echo "0")
    # Also count individual PASS/FAIL lines
    if [ -z "$PASS_COUNT" ] || [ "$PASS_COUNT" = "0" ]; then
      PASS_COUNT=$(echo "$TEST_OUTPUT" | grep -c "PASS:" || echo "0")
    fi
    if [ -z "$FAIL_COUNT" ] || [ "$FAIL_COUNT" = "0" ]; then
      FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -c "FAIL:" || echo "0")
    fi
    ;;
esac

echo "$TEST_OUTPUT"

if [ "$TEST_EXIT" -eq 0 ]; then
  echo "PASS: ${PASS_COUNT:-?} tests"
  exit 0
else
  echo "FAIL: ${PASS_COUNT:-?} passed, ${FAIL_COUNT:-?} failed"
  exit 1
fi
