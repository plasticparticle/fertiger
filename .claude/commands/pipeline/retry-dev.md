Manually trigger a dev swarm retry after a QA failure, without re-running
earlier pipeline stages.

The issue number is provided as $ARGUMENTS.

Before executing, read `.claude/rules/developer.md` in full.

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Read the most recent `pipeline-agent:qa-validation` comment to find the specific
failures and suggested fixes. Follow the "On QA Retry" section of the developer
rules. Fix only what is described in the QA failure report.
