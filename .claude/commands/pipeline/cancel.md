Cancel the pipeline for a specific issue: removes pipeline labels, resets project
status to Backlog, and posts a cancellation comment. Does not delete the feature branch.

Usage: `/pipeline:cancel 42`

The issue number is provided as $ARGUMENTS.

---

## Step 1: Load Config and Check Issue State

```bash
source .claude/config.sh
export ISSUE_NUMBER=$ARGUMENTS

# Fetch current issue title and labels
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --json number,title,labels,state
```

If the issue is already closed or has `pipeline:done`, print a warning and confirm
with the user before proceeding — cancelling a completed pipeline is unusual.

---

## Step 2: Find Feature Branch (if any)

```bash
BRANCH_NAME=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json comments \
  | jq -r '[.comments[] | select(.body | test("Branch created:"))] | last | .body // ""' \
  | grep -oE 'feature/[^`]+' | head -1 || echo "")
```

---

## Step 3: Determine Pipeline Progress

Scan comments to know how far the pipeline got — used in the cancellation comment.

```bash
COMPLETED_AGENTS=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json comments \
  | jq -r '[.comments[].body | select(test("pipeline-agent:")) | capture("pipeline-agent:(?P<a>[^-\\s\"]+)").a] | unique | join(", ")')
```

---

## Step 4: Post Cancellation Comment

```bash
CANCELLED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:cancelled -->
## 🛑 Pipeline Cancelled

**Cancelled at:** $CANCELLED_AT
**Cancelled by:** human (\`/pipeline:cancel $ISSUE_NUMBER\`)

The pipeline has been manually cancelled. All pipeline labels have been removed
and the issue status has been reset to **Backlog**.

**Agents completed before cancel:** ${COMPLETED_AGENTS:-none}

$([ -n "$BRANCH_NAME" ] && echo "**Feature branch:** \`$BRANCH_NAME\` — not deleted. Remove manually if no longer needed:
\`\`\`
git push origin --delete $BRANCH_NAME
git branch -d $BRANCH_NAME
\`\`\`" || echo "**Feature branch:** None was created.")

To restart the pipeline from the beginning, set the issue status to **Ready** or
re-add the \`pipeline:ready\` label."
```

---

## Step 5: Clean Up Labels and Reset Status

```bash
scripts/pipeline/cancel-pipeline.sh
```

---

## Step 6: Log and Print Summary

```bash
scripts/pipeline/log.sh "Cancel" "Pipeline cancelled for issue #$ISSUE_NUMBER — status reset to Backlog" FAIL
```

Print a summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛑  Pipeline cancelled — Issue #$ISSUE_NUMBER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Labels removed:  pipeline:ready, pipeline:blocked
Status:          → Backlog
Branch:          $BRANCH_NAME (not deleted — remove manually if needed)
Completed agents: $COMPLETED_AGENTS

To restart: set issue status to Ready or add `pipeline:ready` label.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
