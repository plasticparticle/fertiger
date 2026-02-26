#!/usr/bin/env bash
# QA Test: detect-stack.sh — Stack Detection
# Covers: AC-001, AC-002
# Expected to FAIL until scripts/pipeline/detect-stack.sh is implemented

set -euo pipefail

PASS=0
FAIL=0

SCRIPT="scripts/pipeline/detect-stack.sh"

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

assert_not_empty() {
  local description="$1"
  local value="$2"
  if [ -n "$value" ]; then
    echo "  PASS: $description"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description — value is empty"
    FAIL=$((FAIL + 1))
  fi
}

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

# Create fixture directories
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

echo ""
echo "=== detect-stack.test.sh: Stack Detection Script ==="
echo ""

# --- Prerequisite: script exists ---
echo "--- Prerequisite: script file exists ---"
assert_file_exists "scripts/pipeline/detect-stack.sh exists" "$SCRIPT"

if [ ! -f "$SCRIPT" ]; then
  echo ""
  echo "=== RESULTS: $PASS passed, $FAIL failed ==="
  exit 1
fi

echo ""
echo "--- AC-001: TypeScript project detection (package.json with typescript devDep) ---"
# Create Node/TS fixture
TS_DIR="$FIXTURE_DIR/typescript-project"
mkdir -p "$TS_DIR"
cat > "$TS_DIR/package.json" <<'PKGJSON'
{
  "name": "my-ts-project",
  "scripts": {
    "test": "npx jest",
    "lint": "npx eslint src/",
    "build": "npx tsc",
    "typecheck": "npx tsc --noEmit"
  },
  "devDependencies": {
    "typescript": "^5.0.0",
    "jest": "^29.0.0"
  }
}
PKGJSON

(
  cd "$TS_DIR"
  # Source the script and check exports
  # We run in a subshell so exports don't leak
  eval_result=$(bash -c "source $(pwd)/../../$SCRIPT 2>&1; echo \"LANG=\$STACK_LANGUAGE TEST=\$STACK_TEST_CMD\"" 2>/dev/null) || true
  STACK_LANGUAGE_VAL=$(bash -c "cd '$TS_DIR' && source $(pwd -P)/../../$SCRIPT 2>/dev/null; echo \$STACK_LANGUAGE" 2>/dev/null) || STACK_LANGUAGE_VAL=""
  STACK_TEST_VAL=$(bash -c "cd '$TS_DIR' && source $(pwd -P)/../../$SCRIPT 2>/dev/null; echo \$STACK_TEST_CMD" 2>/dev/null) || STACK_TEST_VAL=""
  echo "  (TS_DIR: $TS_DIR)"
  echo "  (STACK_LANGUAGE detected: '$STACK_LANGUAGE_VAL')"
  echo "  (STACK_TEST_CMD detected: '$STACK_TEST_VAL')"
) 2>/dev/null || true

REPO_ROOT="$(pwd)"
run_detect() {
  local dir="$1"
  local var="$2"
  bash -c "cd '$dir' && source '$REPO_ROOT/$SCRIPT' 2>/dev/null; printf '%s' \"\$$var\"" 2>/dev/null || echo ""
}

TS_LANG=$(run_detect "$TS_DIR" "STACK_LANGUAGE")
TS_TEST=$(run_detect "$TS_DIR" "STACK_TEST_CMD")
TS_LINT=$(run_detect "$TS_DIR" "STACK_LINT_CMD")
TS_BUILD=$(run_detect "$TS_DIR" "STACK_BUILD_CMD")

assert_equals "TypeScript project: STACK_LANGUAGE=typescript" "typescript" "$TS_LANG"
assert_not_empty "TypeScript project: STACK_TEST_CMD is set" "$TS_TEST"
assert_not_empty "TypeScript project: STACK_LINT_CMD is set" "$TS_LINT"
assert_not_empty "TypeScript project: STACK_BUILD_CMD is set" "$TS_BUILD"

echo ""
echo "--- AC-001: JavaScript project detection (package.json without typescript) ---"
JS_DIR="$FIXTURE_DIR/javascript-project"
mkdir -p "$JS_DIR"
cat > "$JS_DIR/package.json" <<'PKGJSON'
{
  "name": "my-js-project",
  "scripts": {
    "test": "npx jest",
    "lint": "npx eslint src/",
    "build": "node index.js"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  }
}
PKGJSON

JS_LANG=$(run_detect "$JS_DIR" "STACK_LANGUAGE")
assert_equals "JavaScript project: STACK_LANGUAGE=javascript" "javascript" "$JS_LANG"

echo ""
echo "--- AC-001: Rust project detection (Cargo.toml) ---"
RUST_DIR="$FIXTURE_DIR/rust-project"
mkdir -p "$RUST_DIR"
touch "$RUST_DIR/Cargo.toml"

RUST_LANG=$(run_detect "$RUST_DIR" "STACK_LANGUAGE")
RUST_TEST=$(run_detect "$RUST_DIR" "STACK_TEST_CMD")
assert_equals "Rust project: STACK_LANGUAGE=rust" "rust" "$RUST_LANG"
assert_not_empty "Rust project: STACK_TEST_CMD is set" "$RUST_TEST"

echo ""
echo "--- AC-001: Go project detection (go.mod) ---"
GO_DIR="$FIXTURE_DIR/go-project"
mkdir -p "$GO_DIR"
touch "$GO_DIR/go.mod"

GO_LANG=$(run_detect "$GO_DIR" "STACK_LANGUAGE")
GO_TEST=$(run_detect "$GO_DIR" "STACK_TEST_CMD")
assert_equals "Go project: STACK_LANGUAGE=go" "go" "$GO_LANG"
assert_not_empty "Go project: STACK_TEST_CMD is set" "$GO_TEST"

echo ""
echo "--- AC-001: Python project detection (requirements.txt) ---"
PY_DIR="$FIXTURE_DIR/python-project"
mkdir -p "$PY_DIR"
touch "$PY_DIR/requirements.txt"

PY_LANG=$(run_detect "$PY_DIR" "STACK_LANGUAGE")
PY_TEST=$(run_detect "$PY_DIR" "STACK_TEST_CMD")
assert_equals "Python project: STACK_LANGUAGE=python" "python" "$PY_LANG"
assert_not_empty "Python project: STACK_TEST_CMD is set" "$PY_TEST"

echo ""
echo "--- AC-001: Java (Maven) project detection (pom.xml) ---"
JAVA_DIR="$FIXTURE_DIR/java-project"
mkdir -p "$JAVA_DIR"
touch "$JAVA_DIR/pom.xml"

JAVA_LANG=$(run_detect "$JAVA_DIR" "STACK_LANGUAGE")
JAVA_TEST=$(run_detect "$JAVA_DIR" "STACK_TEST_CMD")
assert_equals "Java/Maven project: STACK_LANGUAGE=java" "java" "$JAVA_LANG"
assert_not_empty "Java/Maven project: STACK_TEST_CMD is set" "$JAVA_TEST"

echo ""
echo "--- AC-001: package.json takes priority over other files ---"
MIXED_DIR="$FIXTURE_DIR/mixed-project"
mkdir -p "$MIXED_DIR"
cat > "$MIXED_DIR/package.json" <<'PKGJSON'
{
  "name": "mixed-project",
  "scripts": { "test": "jest" },
  "devDependencies": { "typescript": "^5.0.0" }
}
PKGJSON
touch "$MIXED_DIR/go.mod"

MIXED_LANG=$(run_detect "$MIXED_DIR" "STACK_LANGUAGE")
assert_equals "package.json takes priority over go.mod: STACK_LANGUAGE=typescript" "typescript" "$MIXED_LANG"

echo ""
echo "--- AC-002: exit non-zero when no known stack file present ---"
EMPTY_DIR="$FIXTURE_DIR/empty-project"
mkdir -p "$EMPTY_DIR"

# Run in a subshell — script should exit non-zero
if bash -c "cd '$EMPTY_DIR' && source '$REPO_ROOT/$SCRIPT'" 2>/dev/null; then
  echo "  FAIL: detect-stack.sh should exit non-zero for unknown stack but exited 0"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: detect-stack.sh exits non-zero for unknown stack"
  PASS=$((PASS + 1))
fi

# Should also produce an error message
ERROR_MSG=$(bash -c "cd '$EMPTY_DIR' && source '$REPO_ROOT/$SCRIPT'" 2>&1 || true)
if [ -n "$ERROR_MSG" ]; then
  echo "  PASS: detect-stack.sh produces error message for unknown stack"
  PASS=$((PASS + 1))
else
  echo "  FAIL: detect-stack.sh produces no error message for unknown stack"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== RESULTS: $PASS passed, $FAIL failed ==="
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0
