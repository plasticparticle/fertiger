#!/bin/sh
# Pipeline Triage Script
# Classifies a feature issue as TRIVIAL, STANDARD, or COMPLEX
# to determine analysis depth for downstream pipeline agents.
#
# Usage (offline/test mode):
#   TRIAGE_CREATE_COUNT=1 TRIAGE_MODIFY_COUNT=0 TRIAGE_KEYWORDS="API" sh triage.sh --offline
#
# Usage (live mode):
#   ISSUE_NUMBER=4 sh triage.sh
#
# Override:
#   TRIAGE_FULL_REVIEW=1 (or pipeline:full-review label on issue) forces COMPLEX output

set -e

# --- pipeline:full-review / TRIAGE_FULL_REVIEW override ---
# This check is unconditional: full-review always wins regardless of other factors.
if [ "${TRIAGE_FULL_REVIEW:-0}" = "1" ]; then
  TRIAGE_LEVEL="COMPLEX"
  echo "$TRIAGE_LEVEL"
  export TRIAGE_LEVEL
  exit 0
fi

# --- Offline / test mode ---
# When --offline or --mock flag is passed, use env vars directly without GitHub API calls.
OFFLINE=0
for arg in "$@"; do
  case "$arg" in
    --offline|--mock) OFFLINE=1 ;;
  esac
done

if [ "$OFFLINE" = "1" ]; then
  CREATE_COUNT="${TRIAGE_CREATE_COUNT:-0}"
  MODIFY_COUNT="${TRIAGE_MODIFY_COUNT:-0}"
  KEYWORDS="${TRIAGE_KEYWORDS:-}"
else
  # --- Live mode: read from GitHub ---
  if [ -n "${ISSUE_NUMBER:-}" ]; then
    # Source config if available
    if [ -f ".claude/config.sh" ]; then
      # shellcheck source=/dev/null
      . ".claude/config.sh"
    fi
    ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" \
      --repo "${GITHUB_REPO:-}" \
      --json body,comments \
      --jq '.body + " " + ([.comments[].body] | join(" "))' 2>/dev/null || echo "")
    KEYWORDS="$ISSUE_BODY"
    CREATE_COUNT="${TRIAGE_CREATE_COUNT:-0}"
    MODIFY_COUNT="${TRIAGE_MODIFY_COUNT:-0}"
  else
    # No issue number and not offline — fall back to STANDARD
    TRIAGE_LEVEL="STANDARD"
    echo "$TRIAGE_LEVEL"
    export TRIAGE_LEVEL
    exit 0
  fi
fi

# --- Total file count ---
TOTAL_FILES=$((CREATE_COUNT + MODIFY_COUNT))

# --- Keyword analysis ---
# High-risk keywords that force COMPLEX classification
# Keyword matching is done via grep — user input is never eval'd
HAS_COMPLEX_KEYWORD=0

# Check for standalone "API" keyword (case-sensitive per spec)
if echo "$KEYWORDS" | grep -q 'API'; then
  HAS_COMPLEX_KEYWORD=1
fi

# Check other high-risk keywords (case-insensitive)
if echo "$KEYWORDS" | grep -qi 'database\|migration\|personal data\|GDPR\|service\|EU'; then
  HAS_COMPLEX_KEYWORD=1
fi

# Check for "auth" keyword
if echo "$KEYWORDS" | grep -qi 'auth'; then
  HAS_COMPLEX_KEYWORD=1
fi

# --- Classification logic ---
# COMPLEX: 5+ total files OR high-risk keyword present (with exceptions)
# TRIVIAL: exactly 1 MODIFY file, 0 CREATE files, no complex keywords
# STANDARD: everything else (2-4 files, mixed CREATE/MODIFY, no high-risk keywords that elevate)

if [ "$TOTAL_FILES" -ge 5 ] || [ "$HAS_COMPLEX_KEYWORD" = "1" ]; then
  # Exception: "API" keyword with exactly 2 total files is STANDARD per acceptance criteria
  if echo "$KEYWORDS" | grep -q 'API' && [ "$TOTAL_FILES" -le 2 ]; then
    TRIAGE_LEVEL="STANDARD"
  else
    TRIAGE_LEVEL="COMPLEX"
  fi
elif [ "$CREATE_COUNT" = "0" ] && [ "$MODIFY_COUNT" = "1" ]; then
  TRIAGE_LEVEL="TRIVIAL"
else
  TRIAGE_LEVEL="STANDARD"
fi

echo "$TRIAGE_LEVEL"
export TRIAGE_LEVEL
