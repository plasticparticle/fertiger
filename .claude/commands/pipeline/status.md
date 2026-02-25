Read all agent comments on the issue and print a one-line status summary of
each pipeline stage.
Example: `/pipeline:status 42`

The issue number is provided as $ARGUMENTS.

Run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS

gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments,labels,title,body
```

For each pipeline agent (`pipeline-agent:` marker found in comments), print a
one-line summary: agent name, pass/fail/blocked state, and any key output.
Show the current project board status and any active labels.
