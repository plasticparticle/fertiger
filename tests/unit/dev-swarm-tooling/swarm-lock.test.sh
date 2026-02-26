#!/usr/bin/env bash
# QA Test: swarm-lock.sh — Swarm Lock Coordination
# Covers: AC-005, AC-006, AC-007
# Uses real GitHub API against issue #3 for integration-style testing.
# Requires: ISSUE_NUMBER, GITHUB_REPO, and gh CLI authentication.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT="scripts/pipeline/swarm-lock.sh"
REPO_ROOT="$(pwd)"

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
    echo "         Got: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_equals() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description"
    echo "         Expected: $expected"
    echo "         Actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== swarm-lock.test.sh: Swarm Lock Coordination ==="
echo ""

echo "--- Prerequisite: script file exists ---"
assert_file_exists "scripts/pipeline/swarm-lock.sh exists" "$SCRIPT"

if [ ! -f "$SCRIPT" ]; then
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-009: swarm-lock.sh is executable ---"
assert_executable "swarm-lock.sh is executable" "$REPO_ROOT/$SCRIPT"

echo ""
echo "--- AC-005: script requires ISSUE_NUMBER env var ---"
# Test that script exits non-zero when ISSUE_NUMBER is unset
UNSET_EXIT=0
UNSET_OUTPUT=$(ISSUE_NUMBER="" GITHUB_REPO="test/repo" bash "$REPO_ROOT/$SCRIPT" claim agent1 "file.ts" 2>&1) || UNSET_EXIT=$?
if [ "$UNSET_EXIT" -ne 0 ]; then
  echo "  PASS: swarm-lock.sh exits non-zero when ISSUE_NUMBER is unset"
  PASS=$((PASS + 1))
else
  echo "  FAIL: swarm-lock.sh should exit non-zero when ISSUE_NUMBER is unset"
  FAIL=$((FAIL + 1))
fi
assert_contains "swarm-lock.sh reports ISSUE_NUMBER error" "$UNSET_OUTPUT" "ISSUE_NUMBER"

echo ""
echo "--- AC-005: script requires GITHUB_REPO env var ---"
UNSET_EXIT2=0
UNSET_OUTPUT2=$(ISSUE_NUMBER="3" GITHUB_REPO="" bash "$REPO_ROOT/$SCRIPT" claim agent1 "file.ts" 2>&1) || UNSET_EXIT2=$?
if [ "$UNSET_EXIT2" -ne 0 ]; then
  echo "  PASS: swarm-lock.sh exits non-zero when GITHUB_REPO is unset"
  PASS=$((PASS + 1))
else
  echo "  FAIL: swarm-lock.sh should exit non-zero when GITHUB_REPO is unset"
  FAIL=$((FAIL + 1))
fi
assert_contains "swarm-lock.sh reports GITHUB_REPO error" "$UNSET_OUTPUT2" "GITHUB_REPO"

echo ""
echo "--- AC-005/AC-006/AC-007: claim/check/release with real GitHub API ---"
# Use the real GitHub API against issue #3 with a unique test agent name
TEST_AGENT="test-agent-$$"
export ISSUE_NUMBER="3"
export GITHUB_REPO="plasticparticle/fertiger"

echo "  (using agent name: $TEST_AGENT)"

# First, ensure no prior test lock exists for this agent
bash "$REPO_ROOT/$SCRIPT" release "$TEST_AGENT" > /dev/null 2>&1 || true

# AC-005: claim writes swarm-lock comment
echo ""
echo "  Testing: claim..."
CLAIM_OUTPUT=$(bash "$REPO_ROOT/$SCRIPT" claim "$TEST_AGENT" "tests/swarm-lock-test-file.txt" 2>&1 || true)
echo "  (claim output: $CLAIM_OUTPUT)"
assert_contains "claim outputs CLAIMED confirmation" "$CLAIM_OUTPUT" "CLAIMED"

# AC-006: check returns CLAIMED for locked file
echo ""
echo "  Testing: check for claimed file..."
CHECK_CLAIMED=$(bash "$REPO_ROOT/$SCRIPT" check "tests/swarm-lock-test-file.txt" 2>&1 || true)
echo "  (check output for claimed file: $CHECK_CLAIMED)"
assert_contains "check returns CLAIMED for locked file" "$CHECK_CLAIMED" "CLAIMED"
assert_contains "check returns owning agent name" "$CHECK_CLAIMED" "$TEST_AGENT"

# AC-006: check returns FREE for unclaimed file
echo ""
echo "  Testing: check for unclaimed file..."
CHECK_FREE=$(bash "$REPO_ROOT/$SCRIPT" check "some/other/file.ts" 2>&1 || true)
echo "  (check output for free file: $CHECK_FREE)"
assert_contains "check returns FREE for unclaimed file" "$CHECK_FREE" "FREE"

# AC-007: release removes agent entries
echo ""
echo "  Testing: release..."
RELEASE_OUTPUT=$(bash "$REPO_ROOT/$SCRIPT" release "$TEST_AGENT" 2>&1 || true)
echo "  (release output: $RELEASE_OUTPUT)"
assert_contains "release outputs RELEASED confirmation" "$RELEASE_OUTPUT" "RELEASED"

# After release, the file should be FREE
CHECK_AFTER_RELEASE=$(bash "$REPO_ROOT/$SCRIPT" check "tests/swarm-lock-test-file.txt" 2>&1 || true)
echo "  (check after release: $CHECK_AFTER_RELEASE)"
assert_contains "check returns FREE after release" "$CHECK_AFTER_RELEASE" "FREE"

echo ""
echo "--- AC-005: script uses ISSUE_NUMBER and GITHUB_REPO env vars ---"
if grep -q "ISSUE_NUMBER\|GITHUB_REPO" "$REPO_ROOT/$SCRIPT"; then
  echo "  PASS: swarm-lock.sh uses ISSUE_NUMBER and GITHUB_REPO env vars"
  PASS=$((PASS + 1))
else
  echo "  FAIL: swarm-lock.sh does not reference ISSUE_NUMBER or GITHUB_REPO"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-005: swarm-lock marker is referenced in the script ---"
if grep -q "swarm-lock" "$REPO_ROOT/$SCRIPT"; then
  echo "  PASS: swarm-lock.sh uses swarm-lock marker"
  PASS=$((PASS + 1))
else
  echo "  FAIL: swarm-lock.sh does not use swarm-lock marker"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
