Start the Git Watcher Agent. Automatically uses webhook mode (event-driven,
zero-latency) when `gh webhook forward` and `python3` are available — falls
back to polling (60-second interval) otherwise. Mode selection is automatic.

Before executing, read `.claude/rules/git-watcher.md` in full.

Then start the watcher:
```bash
source .claude/config.sh
bash .claude/scripts/webhook-watch.sh
```

The script handles mode detection and fallback automatically.
To force polling mode explicitly:
```bash
bash .claude/scripts/watch.sh
```

To override timing (e.g. for quick testing):
```bash
WEBHOOK_PORT=9867 MAX_IDLE_SECONDS=300 bash .claude/scripts/webhook-watch.sh
```

No issue number is required — the watcher runs autonomously.
