#!/usr/bin/env bash
# detect-stack.sh — Language/Stack Detection for Pipeline Agents
#
# Usage: source scripts/pipeline/detect-stack.sh
#
# Exports:
#   STACK_LANGUAGE       e.g. typescript, javascript, python, go, rust, java, kotlin
#   STACK_TEST_CMD       e.g. "npx jest", "pytest", "go test ./...", "cargo test"
#   STACK_LINT_CMD       e.g. "npx eslint src/", "ruff check .", "go vet ./..."
#   STACK_TYPECHECK_CMD  e.g. "npx tsc --noEmit", "" (empty if not applicable)
#   STACK_BUILD_CMD      e.g. "npm run build", "go build ./...", "cargo build"
#
# Detection priority: package.json > Cargo.toml > go.mod > pyproject.toml/requirements.txt
#                     > pom.xml > build.gradle/build.gradle.kts
#
# Must be POSIX-compatible (bash 3.2+)

_detect_stack_error() {
  echo "ERROR: detect-stack.sh — no known stack file found in $(pwd)" >&2
  echo "Checked: package.json, Cargo.toml, go.mod, pyproject.toml, requirements.txt, pom.xml, build.gradle, build.gradle.kts" >&2
  return 1
}

_detect_node_stack() {
  local pkg_json="$1"

  # Determine TypeScript vs JavaScript by checking devDependencies for typescript
  if grep -q '"typescript"' "$pkg_json" 2>/dev/null; then
    STACK_LANGUAGE="typescript"
    STACK_TYPECHECK_CMD="npx tsc --noEmit"
  else
    STACK_LANGUAGE="javascript"
    STACK_TYPECHECK_CMD=""
  fi

  # Read actual configured scripts from package.json using jq if available
  if command -v jq >/dev/null 2>&1; then
    local test_script
    local lint_script
    local build_script

    test_script=$(jq -r '.scripts.test // empty' "$pkg_json" 2>/dev/null)
    lint_script=$(jq -r '.scripts.lint // empty' "$pkg_json" 2>/dev/null)
    build_script=$(jq -r '.scripts.build // empty' "$pkg_json" 2>/dev/null)

    if [ -n "$test_script" ]; then
      STACK_TEST_CMD="$test_script"
    else
      STACK_TEST_CMD="npx jest"
    fi

    if [ -n "$lint_script" ]; then
      STACK_LINT_CMD="$lint_script"
    else
      STACK_LINT_CMD="npx eslint src/"
    fi

    if [ -n "$build_script" ]; then
      STACK_BUILD_CMD="$build_script"
    else
      STACK_BUILD_CMD="npm run build"
    fi
  else
    # Fallback: use grep to find script values without jq
    local test_val
    local lint_val
    local build_val

    test_val=$(grep '"test"' "$pkg_json" 2>/dev/null | sed 's/.*"test"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    lint_val=$(grep '"lint"' "$pkg_json" 2>/dev/null | sed 's/.*"lint"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
    build_val=$(grep '"build"' "$pkg_json" 2>/dev/null | sed 's/.*"build"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)

    STACK_TEST_CMD="${test_val:-npx jest}"
    STACK_LINT_CMD="${lint_val:-npx eslint src/}"
    STACK_BUILD_CMD="${build_val:-npm run build}"
  fi

  export STACK_LANGUAGE STACK_TEST_CMD STACK_LINT_CMD STACK_TYPECHECK_CMD STACK_BUILD_CMD
}

# --- Detection logic (priority order) ---

if [ -f "package.json" ]; then
  _detect_node_stack "package.json"

elif [ -f "Cargo.toml" ]; then
  STACK_LANGUAGE="rust"
  STACK_TEST_CMD="cargo test"
  STACK_LINT_CMD="cargo clippy"
  STACK_TYPECHECK_CMD=""
  STACK_BUILD_CMD="cargo build"
  export STACK_LANGUAGE STACK_TEST_CMD STACK_LINT_CMD STACK_TYPECHECK_CMD STACK_BUILD_CMD

elif [ -f "go.mod" ]; then
  STACK_LANGUAGE="go"
  STACK_TEST_CMD="go test ./..."
  STACK_LINT_CMD="go vet ./..."
  STACK_TYPECHECK_CMD=""
  STACK_BUILD_CMD="go build ./..."
  export STACK_LANGUAGE STACK_TEST_CMD STACK_LINT_CMD STACK_TYPECHECK_CMD STACK_BUILD_CMD

elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  STACK_LANGUAGE="python"
  STACK_TEST_CMD="pytest"
  STACK_LINT_CMD="ruff check ."
  STACK_TYPECHECK_CMD=""
  STACK_BUILD_CMD="python -m build"
  export STACK_LANGUAGE STACK_TEST_CMD STACK_LINT_CMD STACK_TYPECHECK_CMD STACK_BUILD_CMD

elif [ -f "pom.xml" ]; then
  STACK_LANGUAGE="java"
  STACK_TEST_CMD="mvn test"
  STACK_LINT_CMD="mvn checkstyle:check"
  STACK_TYPECHECK_CMD=""
  STACK_BUILD_CMD="mvn package"
  export STACK_LANGUAGE STACK_TEST_CMD STACK_LINT_CMD STACK_TYPECHECK_CMD STACK_BUILD_CMD

elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  # Determine Java vs Kotlin by checking for .kts suffix
  if [ -f "build.gradle.kts" ]; then
    STACK_LANGUAGE="kotlin"
  else
    STACK_LANGUAGE="java"
  fi
  STACK_TEST_CMD="./gradlew test"
  STACK_LINT_CMD="./gradlew lint"
  STACK_TYPECHECK_CMD=""
  STACK_BUILD_CMD="./gradlew build"
  export STACK_LANGUAGE STACK_TEST_CMD STACK_LINT_CMD STACK_TYPECHECK_CMD STACK_BUILD_CMD

else
  _detect_stack_error
fi
