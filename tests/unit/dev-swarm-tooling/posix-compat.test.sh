#!/usr/bin/env bash
# QA Test: POSIX Compatibility and Executability
# Covers: AC-009
# Expected to FAIL until scripts/pipeline/*.sh are implemented

set -euo pipefail

PASS=0
FAIL=0

SCRIPTS=(
  "scripts/pipeline/detect-stack.sh"
  "scripts/pipeline/run-tests.sh"
  "scripts/pipeline/swarm-lock.sh"
  "scripts/pipeline/check-deps.sh"
)

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
    echo "  FAIL: $description — found POSIX-incompatible pattern: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== posix-compat.test.sh: POSIX Compatibility and Executability ==="
echo ""

for SCRIPT in "${SCRIPTS[@]}"; do
  SCRIPT_NAME=$(basename "$SCRIPT")
  echo "--- Checking: $SCRIPT_NAME ---"

  assert_file_exists "$SCRIPT_NAME exists" "$SCRIPT"

  if [ ! -f "$SCRIPT" ]; then
    echo "  (skipping further checks — file missing)"
    echo ""
    continue
  fi

  assert_executable "$SCRIPT_NAME is executable (chmod +x)" "$SCRIPT"

  # Check for a shebang line
  SHEBANG=$(head -1 "$SCRIPT")
  if echo "$SHEBANG" | grep -q "^#!"; then
    echo "  PASS: $SCRIPT_NAME has shebang line: $SHEBANG"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $SCRIPT_NAME missing shebang line"
    FAIL=$((FAIL + 1))
  fi

  # Check for bash 4+ incompatible features:
  # - declare -A (associative arrays — bash 4+ only, not bash 3.2 on macOS)
  assert_not_contains "$SCRIPT_NAME does not use 'declare -A' (bash 4+ only)" \
    "$SCRIPT" "declare -A"

  # - mapfile / readarray (bash 4+ only)
  assert_not_contains "$SCRIPT_NAME does not use 'mapfile' (bash 4+ only)" \
    "$SCRIPT" "mapfile"
  assert_not_contains "$SCRIPT_NAME does not use 'readarray' (bash 4+ only)" \
    "$SCRIPT" "readarray"

  # Check that script syntax is valid bash
  if bash -n "$SCRIPT" 2>/dev/null; then
    echo "  PASS: $SCRIPT_NAME passes bash -n syntax check"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $SCRIPT_NAME failed bash -n syntax check"
    FAIL=$((FAIL + 1))
  fi

  echo ""
done

echo "--- AC-009: scripts/pipeline/ directory exists ---"
if [ -d "scripts/pipeline" ]; then
  echo "  PASS: scripts/pipeline/ directory exists"
  PASS=$((PASS + 1))
else
  echo "  FAIL: scripts/pipeline/ directory does not exist"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
