Start the Git Watcher Agent. Automatically uses webhook mode (event-driven,
zero-latency) when `gh webhook forward` and `python3` are available — falls
back to polling (120-second interval) otherwise. Mode selection is automatic.

Before executing, read `.claude/rules/git-watcher.md` in full.

Then run the watcher in a restart loop — the script exits when it finds
actionable issues, so you must run it again after handling each batch:

```bash
source .claude/config.sh
while true; do
  bash .claude/scripts/webhook-watch.sh
  EXIT=$?
  if [ $EXIT -eq 0 ]; then
    # Clean exit (idle timeout) — stop watching
    echo "[watcher] Session ended."
    break
  fi
  # Non-zero exit = actionable issues found above. Handle them per git-watcher.md
  # rules (Steps 3-5), then the loop restarts the watcher automatically.
done
```

The script handles mode detection and fallback automatically.
To force polling mode explicitly, replace `webhook-watch.sh` with `watch.sh`.

To override timing (e.g. for quick testing):
```bash
WEBHOOK_PORT=9867 MAX_IDLE_SECONDS=300 bash .claude/scripts/webhook-watch.sh
```

No issue number is required — the watcher runs autonomously.
