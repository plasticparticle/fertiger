Manually trigger the full pipeline for a specific GitHub Issue number.
Example: `/pipeline:start 42`

The issue number is provided as $ARGUMENTS.

Before executing, read `.claude/rules/git-watcher.md` in full.

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Then follow the Git Watcher rules to claim and process the issue through the full pipeline.
