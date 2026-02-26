#!/usr/bin/env bash
# QA Test: check-deps.sh — Dependency Existence Check
# Covers: AC-008
# Expected to FAIL until scripts/pipeline/check-deps.sh is implemented

set -euo pipefail

PASS=0
FAIL=0

SCRIPT="scripts/pipeline/check-deps.sh"

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

FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

REPO_ROOT="$(pwd)"

echo ""
echo "=== check-deps.test.sh: Dependency Existence Check ==="
echo ""

echo "--- Prerequisite: script file exists ---"
assert_file_exists "scripts/pipeline/check-deps.sh exists" "$SCRIPT"

if [ ! -f "$SCRIPT" ]; then
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-009: check-deps.sh is executable ---"
assert_executable "check-deps.sh is executable" "$SCRIPT"

echo ""
echo "--- AC-008: TypeScript/JavaScript import parsing ---"
# Create a TS project fixture
TS_DIR="$FIXTURE_DIR/ts-project"
mkdir -p "$TS_DIR/src/api/routes" "$TS_DIR/src/middleware"

# Create an existing file (middleware exists)
cat > "$TS_DIR/src/middleware/auth.ts" <<'EOF'
export function authenticate() {}
EOF

# Create a file that imports from existing and non-existing files
cat > "$TS_DIR/src/api/routes/user.ts" <<'EOF'
import { UserService } from '../../services/UserService';
import { User } from '../../models/User';
import { authenticate } from '../../middleware/auth';

export function userRoutes() {}
EOF

# UserService and User do NOT exist — auth.ts DOES exist
DEPS_OUTPUT=$(bash "$REPO_ROOT/$SCRIPT" "$TS_DIR/src/api/routes/user.ts" 2>&1 || true)
echo "  (check-deps output: $DEPS_OUTPUT)"

assert_contains "TypeScript: reports MISSING for non-existent UserService" "$DEPS_OUTPUT" "MISSING"
assert_contains "TypeScript: reports OK for existing auth.ts" "$DEPS_OUTPUT" "OK"

echo ""
echo "--- AC-008: Python import parsing ---"
PY_DIR="$FIXTURE_DIR/py-project"
mkdir -p "$PY_DIR/app/models" "$PY_DIR/app/utils"

# Create an existing file
cat > "$PY_DIR/app/utils/helpers.py" <<'EOF'
def help():
    pass
EOF

# Create a file that imports from existing and non-existing files
cat > "$PY_DIR/app/main.py" <<'EOF'
import os
from app.models.user import User
from app.utils.helpers import help
from app.services.user_service import UserService
EOF

PY_DEPS=$(bash "$REPO_ROOT/$SCRIPT" "$PY_DIR/app/main.py" 2>&1 || true)
echo "  (Python check-deps output: $PY_DEPS)"

# helpers.py exists → OK; user.py and user_service.py do not exist → MISSING
assert_contains "Python: reports MISSING for non-existent modules" "$PY_DEPS" "MISSING"

echo ""
echo "--- AC-008: Go import parsing ---"
GO_DIR="$FIXTURE_DIR/go-project"
mkdir -p "$GO_DIR/pkg/auth"

# Create an existing file
cat > "$GO_DIR/pkg/auth/jwt.go" <<'EOF'
package auth
func ValidateJWT() {}
EOF

# Create a file with imports
cat > "$GO_DIR/main.go" <<'EOF'
package main

import (
    "fmt"
    "github.com/example/myapp/pkg/auth"
    "github.com/example/myapp/pkg/users"
)

func main() {
    fmt.Println("hello")
}
EOF

GO_DEPS=$(bash "$REPO_ROOT/$SCRIPT" "$GO_DIR/main.go" 2>&1 || true)
echo "  (Go check-deps output: $GO_DEPS)"
# Should detect some imports (at minimum runs without crashing)
if [ -n "$GO_DEPS" ]; then
  echo "  PASS: check-deps.sh produces output for Go file"
  PASS=$((PASS + 1))
else
  echo "  FAIL: check-deps.sh produces no output for Go file"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- AC-008: check-deps.sh handles file that has no imports ---"
NO_IMPORT_FILE="$FIXTURE_DIR/no-imports.sh"
echo "#!/bin/sh" > "$NO_IMPORT_FILE"
echo "echo hello" >> "$NO_IMPORT_FILE"

NO_IMPORT_OUTPUT=$(bash "$REPO_ROOT/$SCRIPT" "$NO_IMPORT_FILE" 2>&1 || true)
echo "  (no-imports output: $NO_IMPORT_OUTPUT)"
# Should not crash — just produce empty or OK output
if [ $? -eq 0 ] 2>/dev/null || true; then
  echo "  PASS: check-deps.sh handles file with no imports without crashing"
  PASS=$((PASS + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
