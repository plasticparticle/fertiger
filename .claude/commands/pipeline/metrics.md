Show per-agent timing, retry counts, and run history for a pipeline issue.

Usage:
  `/pipeline:metrics N`           — all runs for issue N with per-agent durations
  `/pipeline:metrics N RUN_ID`    — per-agent timing table for a specific run
  `/pipeline:metrics --history`   — last 10 completed runs across all issues

Structured logs are written to `.pipeline-logs/issue-N/<run_id>.jsonl` by
`scripts/pipeline/log.sh` whenever `ISSUE_NUMBER` is set.

---

```bash
source .claude/config.sh

ARGS="${ARGUMENTS:-}"

if [ -z "$ARGS" ]; then
  echo "Usage:"
  echo "  /pipeline:metrics N              — all runs for issue N"
  echo "  /pipeline:metrics N RUN_ID       — per-agent timing for a specific run"
  echo "  /pipeline:metrics --history      — last 10 completed runs"
  exit 0
fi

bash scripts/pipeline/metrics.sh $ARGS
```
