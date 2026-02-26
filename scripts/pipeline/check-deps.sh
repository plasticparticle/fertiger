#!/usr/bin/env bash
# check-deps.sh — Import-Based Dependency Existence Check
#
# Usage:
#   scripts/pipeline/check-deps.sh <file> [<file2> ...]
#
# For each file, parses import statements and checks whether imported files
# exist on the current branch. Outputs:
#   MISSING: path/to/file.ts (not yet on branch)
#   OK: path/to/file.ts
#
# Supported languages:
#   TypeScript/JavaScript: import ... from '...'; require('...')
#   Python: import ...; from ... import ...
#   Go: import (...) blocks and single import statements
#   Other: grep for common import patterns
#
# Must be POSIX-compatible (bash 3.2+)

set -eu

if [ $# -eq 0 ]; then
  echo "Usage: check-deps.sh <file> [<file2> ...]" >&2
  exit 0
fi

# Detect file language by extension
_get_file_lang() {
  local file="$1"
  case "$file" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) echo "js" ;;
    *.py) echo "python" ;;
    *.go) echo "go" ;;
    *) echo "other" ;;
  esac
}

# Resolve a TypeScript/JavaScript import path to a filesystem path
# relative to the importing file's directory
_resolve_js_import() {
  local import_path="$1"
  local source_file="$2"
  local source_dir
  source_dir="$(dirname "$source_file")"

  # Skip node_modules, absolute package imports, and type-only imports
  case "$import_path" in
    ./*|../*) : ;;  # relative -- proceed
    *) return 0 ;;  # package import -- skip
  esac

  # Resolve relative path from source file's directory
  local resolved
  resolved="$source_dir/$import_path"

  # Try common extensions if no extension given
  if echo "$import_path" | grep -qE '\.[a-zA-Z]+$'; then
    # Has extension already
    echo "$resolved"
  else
    # Try .ts, .tsx, .js, .jsx in order
    for ext in .ts .tsx .js .jsx; do
      if [ -f "${resolved}${ext}" ]; then
        echo "${resolved}${ext}"
        return 0
      fi
    done
    # Try as directory with index file
    for idx_ext in /index.ts /index.tsx /index.js /index.jsx; do
      if [ -f "${resolved}${idx_ext}" ]; then
        echo "${resolved}${idx_ext}"
        return 0
      fi
    done
    # Return with .ts extension as best guess -- shows as MISSING if not found
    echo "${resolved}.ts"
  fi
}

# Resolve a Python import to a filesystem path
# Searches upward from the source file's directory to find the project root
_resolve_python_import() {
  local module="$1"
  local source_file="$2"
  local source_dir
  source_dir="$(dirname "$source_file")"

  # Convert module path to file path: app.models.user -> app/models/user.py
  local file_path
  file_path=$(echo "$module" | sed 's/\./\//g')

  # Get first component of the module path to find project root
  local first_component
  first_component=$(echo "$file_path" | cut -d'/' -f1)

  # Search upward from source_dir for the directory containing first_component
  local search_dir="$source_dir"
  local found_root=""
  local max_levels=10
  local level=0

  while [ $level -lt $max_levels ]; do
    # Check if first_component exists as a directory at this level
    if [ -d "$search_dir/$first_component" ] || [ -f "$search_dir/$first_component.py" ]; then
      found_root="$search_dir"
      break
    fi
    # Check if we're already at root
    local parent
    parent="$(dirname "$search_dir")"
    if [ "$parent" = "$search_dir" ]; then
      break
    fi
    search_dir="$parent"
    level=$((level + 1))
  done

  # If we found a root, use it; otherwise fall back to source_dir
  local project_root="${found_root:-$source_dir}"

  # Try as .py file
  local candidate="$project_root/$file_path.py"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return 0
  fi

  # Try as package directory
  candidate="$project_root/$file_path/__init__.py"
  if [ -f "$candidate" ]; then
    echo "$candidate"
    return 0
  fi

  echo "$project_root/$file_path.py"
}

# Parse TypeScript/JavaScript imports from a file
_check_js_deps() {
  local file="$1"

  # Extract import paths from:
  #   import ... from 'path'
  #   import ... from "path"
  #   require('path')
  #   require("path")
  local imports
  imports=$(grep -E "(import .+ from ['\"]|import ['\"]|require\(['\"])" "$file" 2>/dev/null \
    | sed "s/.*from ['\"\`]\([^'\"\`]*\)['\"\`].*/\1/; s/.*require(['\"\`]\([^'\"\`]*\)['\"\`]).*/\1/" \
    | grep -E "^\.\." \
    || true)

  while IFS= read -r import_path; do
    [ -z "$import_path" ] && continue

    local resolved
    resolved=$(_resolve_js_import "$import_path" "$file")
    [ -z "$resolved" ] && continue

    if [ -f "$resolved" ]; then
      echo "OK: $resolved"
    else
      echo "MISSING: $resolved"
    fi
  done <<EOF
$imports
EOF

  return 0
}

# Parse Python imports from a file
_check_python_deps() {
  local file="$1"

  # Extract from:
  #   import module.name
  #   from module.name import thing
  local imports
  imports=$(grep -E "^(import |from )" "$file" 2>/dev/null \
    | sed 's/^import \([a-zA-Z0-9_.]*\).*/\1/; s/^from \([a-zA-Z0-9_.]*\) import.*/\1/' \
    || true)

  while IFS= read -r module; do
    [ -z "$module" ] && continue

    # Skip single-word stdlib modules (no dots in name means stdlib or simple import)
    if ! echo "$module" | grep -q '\.'; then
      continue
    fi

    local resolved
    resolved=$(_resolve_python_import "$module" "$file")
    [ -z "$resolved" ] && continue

    if [ -f "$resolved" ]; then
      echo "OK: $resolved"
    else
      echo "MISSING: $resolved"
    fi
  done <<EOF
$imports
EOF
}

# Parse Go imports from a file
_check_go_deps() {
  local file="$1"
  local file_dir
  file_dir="$(dirname "$file")"

  # Extract from single-line and block imports
  # Single: import "path/to/pkg"
  # Block: import (\n  "path/to/pkg"\n)
  local imports
  imports=$(awk '
    /^import \(/ { in_block=1; next }
    in_block && /^\)/ { in_block=0; next }
    in_block { gsub(/["\t ]/, ""); if (length($0) > 0) print $0 }
    /^import "/ { gsub(/^import "/, ""); gsub(/"$/, ""); print }
  ' "$file" 2>/dev/null || true)

  while IFS= read -r import_path; do
    [ -z "$import_path" ] && continue

    # Skip standard library (no domain in path — stdlib paths have no dots or slashes at start)
    if ! echo "$import_path" | grep -q '\.'; then
      continue
    fi

    # For project-local imports, try to resolve to a local directory
    # This is a best-effort check -- Go imports reference the module path
    local last_component
    last_component=$(echo "$import_path" | sed 's|.*/||')

    # Try to find a directory matching the last component of the import path
    if find "$file_dir" -type d -name "$last_component" 2>/dev/null | grep -q .; then
      local found_dir
      found_dir=$(find "$file_dir" -type d -name "$last_component" 2>/dev/null | head -1)
      echo "OK: $found_dir"
    else
      # Try searching from repo root as well
      local repo_root
      repo_root="$(cd "$file_dir" && git rev-parse --show-toplevel 2>/dev/null || echo ".")"
      if find "$repo_root" -type d -name "$last_component" 2>/dev/null | grep -q .; then
        local found_dir2
        found_dir2=$(find "$repo_root" -type d -name "$last_component" 2>/dev/null | head -1)
        echo "OK: $found_dir2"
      else
        echo "MISSING: $import_path (package not found locally)"
      fi
    fi
  done <<EOF
$imports
EOF
}

# Fallback: grep for common import patterns
_check_other_deps() {
  local file="$1"

  # Look for lines that look like imports/includes/requires
  local imports
  imports=$(grep -E "^(#include|require|use |import |from |source )" "$file" 2>/dev/null \
    | grep -v "^#" \
    || true)

  if [ -z "$imports" ]; then
    return 0
  fi

  echo "INFO: $file uses import-like patterns (manual review recommended):"
  echo "$imports" | head -10
}

# --- Main: process each file argument ---
for input_file in "$@"; do
  if [ ! -f "$input_file" ]; then
    echo "ERROR: check-deps.sh -- file not found: $input_file" >&2
    continue
  fi

  lang=$(_get_file_lang "$input_file")

  case "$lang" in
    js)   _check_js_deps "$input_file" ;;
    python) _check_python_deps "$input_file" ;;
    go)   _check_go_deps "$input_file" ;;
    *)    _check_other_deps "$input_file" ;;
  esac
done
