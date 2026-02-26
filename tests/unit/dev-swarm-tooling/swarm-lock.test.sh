#!/usr/bin/env bash
# QA Test: swarm-lock.sh — Swarm Lock Coordination
# Covers: AC-005, AC-006, AC-007
# Expected to FAIL until scripts/pipeline/swarm-lock.sh is implemented
# NOTE: These tests mock the gh CLI to avoid real GitHub API calls.

set -euo pipefail

PASS=0
FAIL=0

SCRIPT="scripts/pipeline/swarm-lock.sh"

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

REPO_ROOT="$(pwd)"
MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR"' EXIT

# Create a mock 'gh' that simulates GitHub Issue comment operations
# The mock stores state in a temp file to simulate the GitHub comment
LOCK_STATE_FILE="$MOCK_DIR/lock-state.txt"
LOCK_COMMENT_ID="42"

create_mock_gh() {
  local mock_bin="$MOCK_DIR/bin"
  mkdir -p "$mock_bin"

  # Write mock gh script
  cat > "$mock_bin/gh" <<MOCK_GH
#!/usr/bin/env bash
# Mock gh CLI for swarm-lock tests
LOCK_STATE_FILE="$LOCK_STATE_FILE"
LOCK_COMMENT_ID="$LOCK_COMMENT_ID"

# Handle: gh api /repos/.../issues/ISSUE_NUM/comments (GET — list comments)
if [ "\$1" = "api" ] && echo "\$*" | grep -q "issues/.*comments" && ! echo "\$*" | grep -q "comments/"; then
  if [ -f "\$LOCK_STATE_FILE" ]; then
    CONTENT=\$(cat "\$LOCK_STATE_FILE")
    # Return JSON array with one comment containing lock state
    printf '[{"id": %s, "body": "%s"}]\n' "\$LOCK_COMMENT_ID" "\$(echo \$CONTENT | sed 's/"/\\\\"/g')"
  else
    echo "[]"
  fi
  exit 0
fi

# Handle: gh api -X POST /repos/.../issues/ISSUE_NUM/comments (POST — create comment)
if [ "\$1" = "api" ] && [ "\$2" = "-X" ] && [ "\$3" = "POST" ]; then
  # Extract body from -f body="..." argument
  BODY=""
  for arg in "\$@"; do
    case "\$arg" in
      body=*) BODY="\${arg#body=}" ;;
    esac
  done
  echo "\$BODY" > "\$LOCK_STATE_FILE"
  printf '{"id": %s}\n' "\$LOCK_COMMENT_ID"
  exit 0
fi

# Handle: gh api -X PATCH /repos/.../issues/comments/COMMENT_ID (PATCH — update comment)
if [ "\$1" = "api" ] && [ "\$2" = "-X" ] && [ "\$3" = "PATCH" ]; then
  BODY=""
  for arg in "\$@"; do
    case "\$arg" in
      body=*) BODY="\${arg#body=}" ;;
    esac
  done
  echo "\$BODY" > "\$LOCK_STATE_FILE"
  printf '{"id": %s}\n' "\$LOCK_COMMENT_ID"
  exit 0
fi

# Handle: gh api -X DELETE (DELETE — delete comment)
if [ "\$1" = "api" ] && [ "\$2" = "-X" ] && [ "\$3" = "DELETE" ]; then
  rm -f "\$LOCK_STATE_FILE"
  exit 0
fi

# Fallback: pass through to real gh for any other commands
exec /usr/bin/gh "\$@" 2>/dev/null || exit 0
MOCK_GH
  chmod +x "$mock_bin/gh"
  echo "$mock_bin"
}

MOCK_BIN=$(create_mock_gh)
export ISSUE_NUMBER="3"
export GITHUB_REPO="plasticparticle/fertiger"

run_swarm_lock() {
  PATH="$MOCK_BIN:$PATH" bash "$REPO_ROOT/$SCRIPT" "$@" 2>&1
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
assert_executable "swarm-lock.sh is executable" "$SCRIPT"

echo ""
echo "--- AC-005: swarm-lock.sh claim writes swarm-lock comment ---"
rm -f "$LOCK_STATE_FILE"

CLAIM_OUTPUT=$(run_swarm_lock claim "agent-alpha" "src/models/User.ts src/services/UserService.ts" 2>&1 || true)
echo "  (claim output: $CLAIM_OUTPUT)"

if [ -f "$LOCK_STATE_FILE" ]; then
  LOCK_CONTENT=$(cat "$LOCK_STATE_FILE")
  echo "  (lock state: $LOCK_CONTENT)"
  assert_contains "claim writes swarm-lock marker to comment" "$LOCK_CONTENT" "swarm-lock"
  assert_contains "claim writes agent name to lock comment" "$LOCK_CONTENT" "agent-alpha"
  assert_contains "claim writes file list to lock comment" "$LOCK_CONTENT" "User.ts"
else
  echo "  FAIL: claim did not write lock state file (no GitHub comment created)"
  FAIL=$((FAIL + 1))
  echo "  FAIL: claim did not write agent name"
  FAIL=$((FAIL + 1))
  echo "  FAIL: claim did not write file list"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-006: swarm-lock.sh check returns CLAIMED when file is locked ---"
# File was claimed by agent-alpha above
CHECK_CLAIMED=$(run_swarm_lock check "src/models/User.ts" 2>&1 || true)
echo "  (check output for claimed file: $CHECK_CLAIMED)"
assert_contains "check returns CLAIMED for locked file" "$CHECK_CLAIMED" "CLAIMED"
assert_contains "check returns owning agent name" "$CHECK_CLAIMED" "agent-alpha"

echo ""
echo "--- AC-006: swarm-lock.sh check returns FREE when file is not locked ---"
CHECK_FREE=$(run_swarm_lock check "src/some/other/file.ts" 2>&1 || true)
echo "  (check output for free file: $CHECK_FREE)"
assert_contains "check returns FREE for unlocked file" "$CHECK_FREE" "FREE"

echo ""
echo "--- AC-007: swarm-lock.sh release removes agent entries ---"
RELEASE_OUTPUT=$(run_swarm_lock release "agent-alpha" 2>&1 || true)
echo "  (release output: $RELEASE_OUTPUT)"

# After release, the file should no longer be claimed
CHECK_AFTER_RELEASE=$(run_swarm_lock check "src/models/User.ts" 2>&1 || true)
echo "  (check after release: $CHECK_AFTER_RELEASE)"
assert_contains "check returns FREE after release" "$CHECK_AFTER_RELEASE" "FREE"

echo ""
echo "--- AC-007: swarm-lock.sh release only removes the releasing agent's entries ---"
# Claim two agents
rm -f "$LOCK_STATE_FILE"
run_swarm_lock claim "agent-alpha" "src/models/User.ts" > /dev/null 2>&1 || true
run_swarm_lock claim "agent-beta" "src/services/OtherService.ts" > /dev/null 2>&1 || true

# Release only agent-alpha
run_swarm_lock release "agent-alpha" > /dev/null 2>&1 || true

# agent-beta's files should still be claimed
CHECK_BETA=$(run_swarm_lock check "src/services/OtherService.ts" 2>&1 || true)
echo "  (agent-beta check after agent-alpha release: $CHECK_BETA)"
assert_contains "agent-beta files remain claimed after agent-alpha releases" "$CHECK_BETA" "CLAIMED"

echo ""
echo "--- AC-005: script requires ISSUE_NUMBER and GITHUB_REPO ---"
if grep -q "ISSUE_NUMBER\|GITHUB_REPO" "$SCRIPT"; then
  echo "  PASS: swarm-lock.sh uses ISSUE_NUMBER and GITHUB_REPO env vars"
  PASS=$((PASS + 1))
else
  echo "  FAIL: swarm-lock.sh does not reference ISSUE_NUMBER or GITHUB_REPO"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
