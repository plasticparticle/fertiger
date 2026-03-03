#!/bin/sh
# Pipeline Triage Script
# Classifies a feature issue as TRIVIAL, STANDARD, or COMPLEX
# to determine analysis depth for downstream pipeline agents.
#
# Usage (offline/test mode):
#   TRIAGE_CREATE_COUNT=1 TRIAGE_MODIFY_COUNT=0 TRIAGE_KEYWORDS="API" sh triage.sh --offline
#   TRIAGE_CREATE_COUNT=1 TRIAGE_MODIFY_COUNT=0 TRIAGE_KEYWORDS="API" sh triage.sh --offline --explain
#
# Usage (live mode):
#   ISSUE_NUMBER=4 sh triage.sh
#   ISSUE_NUMBER=4 sh triage.sh --explain
#
# Override:
#   TRIAGE_FULL_REVIEW=1 (or pipeline:full-review label on issue) forces COMPLEX output.
#   The label check is performed internally — callers do NOT need to re-check it.
#
# Output (plain mode — default, backward-compatible):
#   TRIVIAL | STANDARD | COMPLEX
#
# Output (--explain mode):
#   Line 1:  TRIVIAL | STANDARD | COMPLEX
#   Line 2:  REASONS: <semicolon-separated list of factors that drove the decision>
#
# Agents parse --explain output as:
#   _TRIAGE=$(ISSUE_NUMBER=$N sh scripts/pipeline/triage.sh --explain 2>/dev/null \
#             || printf 'STANDARD\nREASONS: fallback')
#   TRIAGE_LEVEL=$(printf '%s\n' "$_TRIAGE" | head -1)
#   TRIAGE_REASONS=$(printf '%s\n' "$_TRIAGE" | sed -n 's/^REASONS: //p')

set -e

EXPLAIN=0
OFFLINE=0
for arg in "$@"; do
  case "$arg" in
    --explain)       EXPLAIN=1 ;;
    --offline|--mock) OFFLINE=1 ;;
  esac
done

# ── Reason accumulator ────────────────────────────────────────────────────────
REASONS=""
add_reason() {
  if [ -z "$REASONS" ]; then
    REASONS="$1"
  else
    REASONS="$REASONS; $1"
  fi
}

# ── Emit final result ─────────────────────────────────────────────────────────
# Plain mode (default): identical to previous behaviour — single word on stdout.
# Explain mode: level on line 1, REASONS: ... on line 2.
emit() {
  LEVEL="$1"
  if [ "$EXPLAIN" = "1" ]; then
    printf '%s\n' "$LEVEL"
    printf 'REASONS: %s\n' "${REASONS:-no reasons recorded}"
  else
    echo "$LEVEL"
  fi
}

# ── Override: env var ─────────────────────────────────────────────────────────
if [ "${TRIAGE_FULL_REVIEW:-0}" = "1" ]; then
  add_reason "forced — TRIAGE_FULL_REVIEW=1 env var"
  emit "COMPLEX"
  exit 0
fi

# ── Offline / test mode ───────────────────────────────────────────────────────
if [ "$OFFLINE" = "1" ]; then
  CREATE_COUNT="${TRIAGE_CREATE_COUNT:-0}"
  MODIFY_COUNT="${TRIAGE_MODIFY_COUNT:-0}"
  KEYWORDS="${TRIAGE_KEYWORDS:-}"
else
  # ── Live mode: read from GitHub ────────────────────────────────────────────
  if [ -n "${ISSUE_NUMBER:-}" ]; then
    if [ -f ".claude/config.sh" ]; then
      # shellcheck source=/dev/null
      . ".claude/config.sh"
    fi

    # pipeline:full-review label check lives here — agents do NOT need to repeat it
    HAS_LABEL=$(gh issue view "$ISSUE_NUMBER" \
      --repo "${GITHUB_REPO:-}" \
      --json labels \
      --jq '[.labels[].name] | contains(["pipeline:full-review"])' \
      2>/dev/null || echo "false")
    if [ "$HAS_LABEL" = "true" ]; then
      add_reason "forced — pipeline:full-review label on issue"
      emit "COMPLEX"
      exit 0
    fi

    ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" \
      --repo "${GITHUB_REPO:-}" \
      --json body,comments \
      --jq '.body + " " + ([.comments[].body] | join(" "))' \
      2>/dev/null || echo "")
    KEYWORDS="$ISSUE_BODY"
    CREATE_COUNT="${TRIAGE_CREATE_COUNT:-0}"
    MODIFY_COUNT="${TRIAGE_MODIFY_COUNT:-0}"
  else
    # No issue number and not offline — fall back to STANDARD
    add_reason "fallback — no ISSUE_NUMBER provided"
    emit "STANDARD"
    exit 0
  fi
fi

# ── File count ────────────────────────────────────────────────────────────────
TOTAL_FILES=$((CREATE_COUNT + MODIFY_COUNT))

# ── Keyword matching ──────────────────────────────────────────────────────────
# Each matched keyword is recorded individually for transparent reporting.
MATCHED_KEYWORDS=""
add_kw() {
  if [ -z "$MATCHED_KEYWORDS" ]; then
    MATCHED_KEYWORDS="$1"
  else
    MATCHED_KEYWORDS="$MATCHED_KEYWORDS, $1"
  fi
}

if echo "$KEYWORDS" | grep -q 'API';                              then add_kw "API"; fi
if echo "$KEYWORDS" | grep -qi 'auth';                            then add_kw "auth"; fi
if echo "$KEYWORDS" | grep -qi 'database';                        then add_kw "database"; fi
if echo "$KEYWORDS" | grep -qi 'migration';                       then add_kw "migration"; fi
if echo "$KEYWORDS" | grep -qi 'personal data';                   then add_kw "personal data"; fi
if echo "$KEYWORDS" | grep -qi 'GDPR';                            then add_kw "GDPR"; fi
if echo "$KEYWORDS" | grep -qi 'service';                         then add_kw "service"; fi
if echo "$KEYWORDS" | grep -qi 'EU';                              then add_kw "EU"; fi

HAS_COMPLEX_KEYWORD=0
if [ -n "$MATCHED_KEYWORDS" ]; then
  HAS_COMPLEX_KEYWORD=1
fi

# ── Classification ────────────────────────────────────────────────────────────
if [ "$TOTAL_FILES" -ge 5 ] || [ "$HAS_COMPLEX_KEYWORD" = "1" ]; then
  # Exception: API keyword with ≤2 total files → STANDARD (small-scope API change)
  if echo "$KEYWORDS" | grep -q 'API' && [ "$TOTAL_FILES" -le 2 ]; then
    add_reason "keyword:API matched but file count ≤2 — small-scope API exception"
    [ -n "$MATCHED_KEYWORDS" ] && [ "$MATCHED_KEYWORDS" != "API" ] && \
      add_reason "other keywords matched: $(echo "$MATCHED_KEYWORDS" | sed 's/API, \{0,1\}//' | sed 's/, API//')"
    add_reason "files: ${CREATE_COUNT} new + ${MODIFY_COUNT} modified = ${TOTAL_FILES} total"
    emit "STANDARD"
  else
    [ "$TOTAL_FILES" -ge 5 ] && \
      add_reason "files: ${CREATE_COUNT} new + ${MODIFY_COUNT} modified = ${TOTAL_FILES} total (≥5 threshold)"
    [ -n "$MATCHED_KEYWORDS" ] && \
      add_reason "keywords: $MATCHED_KEYWORDS"
    emit "COMPLEX"
  fi
elif [ "$CREATE_COUNT" = "0" ] && [ "$MODIFY_COUNT" = "1" ]; then
  add_reason "files: 0 new + 1 modified = 1 total; no high-risk keywords"
  emit "TRIVIAL"
else
  [ "$TOTAL_FILES" -gt 0 ] && \
    add_reason "files: ${CREATE_COUNT} new + ${MODIFY_COUNT} modified = ${TOTAL_FILES} total (below threshold)"
  [ -z "$MATCHED_KEYWORDS" ] && \
    add_reason "no high-risk keywords matched"
  emit "STANDARD"
fi
