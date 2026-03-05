#!/usr/bin/env bash
# metrics.sh — Pipeline run metrics and historical summaries
#
# Usage:
#   metrics.sh ISSUE_NUMBER              — list all runs for an issue with per-agent timing
#   metrics.sh ISSUE_NUMBER RUN_ID       — per-agent timing table for a specific run
#   metrics.sh --history                 — last 10 completed runs across all issues
#
# Env:
#   PIPELINE_LOGS_DIR — base log directory (default: .pipeline-logs)

set -euo pipefail

LOGS_BASE="${PIPELINE_LOGS_DIR:-.pipeline-logs}"

iso_to_epoch() {
  date -d "$1" +%s 2>/dev/null || echo "0"
}

format_duration() {
  local secs="$1"
  if [ "$secs" -ge 60 ] 2>/dev/null; then
    printf '%dm%ds' "$((secs / 60))" "$((secs % 60))"
  else
    printf '%ds' "$secs"
  fi
}

# Determine overall outcome of a run from its .jsonl file
run_outcome() {
  local f="$1"
  local last_level
  last_level=$(tail -1 "$f" | jq -r '.level // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
  case "$last_level" in
    PASS) echo "PASS" ;;
    FAIL|BLOCK) echo "FAIL" ;;
    *) echo "UNKNOWN" ;;
  esac
}

# Compute duration between first and last ts in a .jsonl file
run_duration() {
  local f="$1"
  local first_ts last_ts t1 t2 diff
  first_ts=$(head -1 "$f" | jq -r '.ts // empty' 2>/dev/null || true)
  last_ts=$(tail -1 "$f" | jq -r '.ts // empty' 2>/dev/null || true)
  if [ -n "$first_ts" ] && [ -n "$last_ts" ]; then
    t1=$(iso_to_epoch "$first_ts")
    t2=$(iso_to_epoch "$last_ts")
    diff=$((t2 - t1))
    format_duration "$diff"
  else
    echo "?"
  fi
}

show_usage() {
  echo "Usage:"
  echo "  metrics.sh ISSUE_NUMBER              — all runs for an issue"
  echo "  metrics.sh ISSUE_NUMBER RUN_ID       — per-agent timing for a run"
  echo "  metrics.sh --history                 — last 10 completed runs"
}

case "${1:-}" in
  --history)
    if [ ! -d "$LOGS_BASE" ]; then
      echo "No pipeline logs found in $LOGS_BASE"
      exit 0
    fi

    # Collect all .jsonl files (skip .current-run-id sentinels)
    TMPROWS=$(mktemp)
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      RUN_ID=$(basename "$f" .jsonl)
      ISSUE=$(basename "$(dirname "$f")" | sed 's/issue-//')
      OUTCOME=$(run_outcome "$f")
      DURATION=$(run_duration "$f")
      MTIME=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      printf '%s\t%s\t%s\t%s\t%s\n' "$MTIME" "$RUN_ID" "$ISSUE" "$OUTCOME" "$DURATION" >> "$TMPROWS"
    done < <(find "$LOGS_BASE" -name "*.jsonl" 2>/dev/null | sort)

    if [ ! -s "$TMPROWS" ]; then
      rm -f "$TMPROWS"
      echo "No completed runs found."
      exit 0
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Pipeline Run History (last 10)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf '  %-42s │ %-6s │ %-12s │ %s\n' "Run ID" "Issue" "Result" "Duration"
    echo "  ──────────────────────────────────────────────────────────────────"

    sort -t$'\t' -k1 -nr "$TMPROWS" | head -10 | while IFS=$'\t' read -r _ rid issue outcome dur; do
      ICON="✅"
      [ "$outcome" = "FAIL" ] && ICON="❌"
      [ "$outcome" = "UNKNOWN" ] && ICON="⚠️ "
      printf '  %-42s │ #%-5s │ %s %-9s │ %s\n' "$rid" "$issue" "$ICON" "$outcome" "$dur"
    done

    echo ""
    rm -f "$TMPROWS"
    ;;

  "")
    show_usage
    exit 0
    ;;

  *)
    ISSUE_NUM="$1"
    ISSUE_DIR="$LOGS_BASE/issue-${ISSUE_NUM}"

    if [ ! -d "$ISSUE_DIR" ]; then
      echo "No runs found for issue #$ISSUE_NUM (looked in $ISSUE_DIR)"
      exit 0
    fi

    # Per-run detail mode: metrics.sh N RUN_ID
    if [ -n "${2:-}" ]; then
      RUN_ID="$2"
      JSONL="$ISSUE_DIR/${RUN_ID}.jsonl"

      if [ ! -f "$JSONL" ]; then
        echo "Run not found: $JSONL"
        exit 1
      fi

      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📊 Per-Agent Timing — $RUN_ID"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      printf '  %-22s │ %-10s │ %s\n' "Agent" "Duration" "Result"
      echo "  ────────────────────────────────────────────────"

      PREV_AGENT=""
      PREV_TS=""
      while IFS= read -r line; do
        AGENT=$(printf '%s' "$line" | jq -r '.agent // empty' 2>/dev/null || true)
        LEVEL=$(printf '%s' "$line" | jq -r '.level // empty' 2>/dev/null || true)
        TS=$(printf '%s' "$line" | jq -r '.ts // empty' 2>/dev/null || true)

        if [ "$LEVEL" = "AGENT" ]; then
          PREV_AGENT="$AGENT"
          PREV_TS="$TS"
        elif { [ "$LEVEL" = "PASS" ] || [ "$LEVEL" = "FAIL" ]; } && [ -n "$PREV_AGENT" ]; then
          DURATION="?"
          if [ -n "$PREV_TS" ] && [ -n "$TS" ]; then
            T1=$(iso_to_epoch "$PREV_TS")
            T2=$(iso_to_epoch "$TS")
            DIFF=$((T2 - T1))
            DURATION=$(format_duration "$DIFF")
          fi
          ICON="✅"
          [ "$LEVEL" = "FAIL" ] && ICON="❌"
          printf '  %-22s │ %-10s │ %s %s\n' "$PREV_AGENT" "$DURATION" "$ICON" "$LEVEL"
          PREV_AGENT=""
          PREV_TS=""
        fi
      done < "$JSONL"
      echo ""

    else
      # All runs for this issue: metrics.sh N
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📊 Runs for Issue #${ISSUE_NUM}"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      printf '  %-42s │ %-12s │ %s\n' "Run ID" "Result" "Duration"
      echo "  ──────────────────────────────────────────────────────────────────"

      RUN_COUNT=0
      ALL_AGENTS=""

      for f in "$ISSUE_DIR"/*.jsonl; do
        [ -f "$f" ] || continue
        RUN_ID=$(basename "$f" .jsonl)
        OUTCOME=$(run_outcome "$f")
        DURATION=$(run_duration "$f")

        ICON="✅"
        [ "$OUTCOME" = "FAIL" ] && ICON="❌"
        [ "$OUTCOME" = "UNKNOWN" ] && ICON="⚠️ "

        printf '  %-42s │ %s %-9s │ %s\n' "$RUN_ID" "$ICON" "$OUTCOME" "$DURATION"
        RUN_COUNT=$((RUN_COUNT + 1))

        # Accumulate agent invocations for retry summary
        while IFS= read -r line; do
          AG=$(printf '%s' "$line" | jq -r '.agent // empty' 2>/dev/null || true)
          LV=$(printf '%s' "$line" | jq -r '.level // empty' 2>/dev/null || true)
          [ "$LV" = "AGENT" ] && [ -n "$AG" ] && ALL_AGENTS="$ALL_AGENTS
$AG"
        done < "$f"
      done

      echo ""
      echo "  Total runs: $RUN_COUNT"

      if [ -n "$ALL_AGENTS" ]; then
        echo ""
        echo "  Agent Invocations (all runs):"
        printf '%s\n' "$ALL_AGENTS" | grep -v '^$' | sort | uniq -c | while read -r count agent; do
          RETRIES=$((count - 1))
          RETRY_NOTE=""
          [ "$RETRIES" -gt 0 ] && RETRY_NOTE=" — $RETRIES Retry"
          printf '  %-24s %d invocation(s)%s\n' "$agent" "$count" "$RETRY_NOTE"
        done
      fi
      echo ""
    fi
    ;;
esac
