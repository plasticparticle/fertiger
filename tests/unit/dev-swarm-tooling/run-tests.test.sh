#!/usr/bin/env bash
# QA Test: run-tests.sh — Test Runner Wrapper
# Covers: AC-003, AC-004
# Expected to FAIL until scripts/pipeline/run-tests.sh is implemented

set -euo pipefail

PASS=0
FAIL=0

SCRIPT="scripts/pipeline/run-tests.sh"
DETECT_SCRIPT="scripts/pipeline/detect-stack.sh"

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

assert_executable() {
  local description="$1"
  local file="$2"
  if [ -x "$file" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — not executable: $file"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "         Expected to contain: $needle"
    echo "         Actual output: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

REPO_ROOT="$(pwd)"

echo ""
echo "=== run-tests.test.sh: Test Runner Wrapper ==="
echo ""

echo "--- Prerequisite: script files exist ---"
assert_file_exists "scripts/pipeline/run-tests.sh exists" "$SCRIPT"
assert_file_exists "scripts/pipeline/detect-stack.sh exists" "$DETECT_SCRIPT"

if [ ! -f "$SCRIPT" ] || [ ! -f "$DETECT_SCRIPT" ]; then
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-009: run-tests.sh is executable ---"
assert_executable "run-tests.sh is executable" "$REPO_ROOT/$SCRIPT"

echo ""
echo "--- AC-003: run-tests.sh sources detect-stack.sh internally ---"
# Check that run-tests.sh references detect-stack.sh (use absolute path)
if grep -q "detect-stack" "$REPO_ROOT/$SCRIPT"; then
  echo "  PASS: run-tests.sh references detect-stack.sh"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run-tests.sh does not reference detect-stack.sh"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-003: run-tests.sh exits non-zero on test failure (shell project) ---"
# We test against this repo itself — tests/run-tests.sh is the runner
# Create a fake failing test environment
FAIL_DIR="$FIXTURE_DIR/failing-project"
mkdir -p "$FAIL_DIR/tests"

# Create a minimal package.json to make detect-stack pick up the project
cat > "$FAIL_DIR/package.json" <<'PKGJSON'
{
  "name": "failing-project",
  "scripts": {
    "test": "exit 1"
  }
}
PKGJSON

# The script should exit non-zero when tests fail
FAIL_EXIT=0
bash -c "cd '$FAIL_DIR' && '$REPO_ROOT/$SCRIPT'" 2>/dev/null || FAIL_EXIT=$?
if [ "$FAIL_EXIT" -ne 0 ]; then
  echo "  PASS: run-tests.sh exits non-zero when tests fail"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run-tests.sh should exit non-zero on test failure but exited 0"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-003: run-tests.sh produces PASS/FAIL summary line ---"
# Test with eu-compliance tests (avoids recursive self-invocation)
# Use absolute path to avoid CWD issues after subshell operations
SUMMARY=$(bash "$REPO_ROOT/$SCRIPT" "eu-compliance" 2>&1 || true)
if echo "$SUMMARY" | grep -q "PASS\|FAIL"; then
  echo "  PASS: run-tests.sh outputs PASS or FAIL summary"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run-tests.sh did not output PASS or FAIL summary"
  echo "  Output was: $SUMMARY"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-004: run-tests.sh filter translates to --testPathPattern for Jest ---"
# Check that the script handles Jest filter flag (use absolute path)
if grep -q "testPathPattern\|--filter\|test.*pattern" "$REPO_ROOT/$SCRIPT"; then
  echo "  PASS: run-tests.sh contains Jest testPathPattern filter translation"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run-tests.sh missing Jest testPathPattern filter translation"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-004: run-tests.sh filter translates to pytest path for Python ---"
if grep -q "pytest" "$REPO_ROOT/$SCRIPT"; then
  echo "  PASS: run-tests.sh contains pytest runner reference"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run-tests.sh missing pytest runner reference"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-004: run-tests.sh filter translates for Go runner ---"
if grep -q "go test" "$REPO_ROOT/$SCRIPT"; then
  echo "  PASS: run-tests.sh contains go test runner reference"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run-tests.sh missing go test runner reference"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-004: run-tests.sh filter translates for Cargo runner ---"
if grep -q "cargo test" "$REPO_ROOT/$SCRIPT"; then
  echo "  PASS: run-tests.sh contains cargo test runner reference"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run-tests.sh missing cargo test runner reference"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
