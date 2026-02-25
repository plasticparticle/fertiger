List all open issues in the GitHub Project and their current pipeline status.
Shows: issue number, title, current stage, blocked/active state.

Run:
```bash
source .claude/config.sh

gh project item-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --format json \
  --limit 100 \
  | jq '.items[] | {number: .content.number, title: .title, status: .status}'

gh issue list \
  --repo $GITHUB_REPO \
  --label "pipeline:blocked" \
  --json number,title,labels \
  --state open
```

Format the output as a table showing issue number, title, current pipeline stage,
and whether the issue is blocked or active.
