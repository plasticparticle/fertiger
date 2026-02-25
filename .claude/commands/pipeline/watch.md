Start the Git Watcher Agent. Polls the GitHub Project every 5 minutes for
issues with status "Ready" or label "pipeline:ready". Processes each one
found through the full pipeline.
Stops after 8 hours of no new issues.

Before executing, read `.claude/rules/git-watcher.md` in full.

Then start the watcher using the pre-built script:
```bash
source .claude/config.sh
bash .claude/scripts/watch.sh
```

The watch loop is fully defined in `.claude/scripts/watch.sh`.
Do NOT reconstruct polling logic inline — use the script.

To override timing (e.g. for quick testing):
```bash
POLL_INTERVAL=60 MAX_IDLE_SECONDS=300 bash .claude/scripts/watch.sh
```

No issue number is required — the watcher polls autonomously.
