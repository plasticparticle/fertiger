Show a live tail of the pipeline activity log — what each agent is doing right now.

Run in a second terminal while `/pipeline:watch` is running in the first.

```bash
LOG_FILE="${PIPELINE_LOG_FILE:-/tmp/pipeline.log}"

# Print last 40 lines of history, then follow new output
tail -n 40 -f "$LOG_FILE" 2>/dev/null \
  || echo "No pipeline log yet — start /pipeline:watch first, then re-run /pipeline:log"
```

The log is written to `/tmp/pipeline.log` by default.
To use a different path, set `PIPELINE_LOG_FILE` in `.claude/config.sh`.
