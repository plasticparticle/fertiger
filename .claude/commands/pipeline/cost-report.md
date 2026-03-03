Show pipeline token costs per feature, aggregated across all completed issues.

Usage: `/pipeline:cost-report`        — table of all features with cost summaries
       `/pipeline:cost-report N`       — cost breakdown for a single issue N
       `/pipeline:cost-report --json`  — raw JSON for scripting

```bash
source .claude/config.sh
scripts/pipeline/cost-report.sh $ARGUMENTS
```

Cost data is sourced from `<!-- pipeline-agent:cost-summary -->` comments posted
by the Git Agent at the end of each completed pipeline run. Issues without a
completed pipeline have no cost data.
