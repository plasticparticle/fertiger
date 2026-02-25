Start the Git Watcher Agent. Polls the GitHub Project every 5 minutes for
issues with status "Ready" or label "pipeline:ready". Processes each one
found through the full pipeline.
Stops after 8 hours of no new issues.

Before executing, read `.claude/rules/git-watcher.md` in full.

Then run:
```bash
source .claude/config.sh
```

No issue number is required — the watcher polls the project board autonomously.
