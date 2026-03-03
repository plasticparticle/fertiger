# Git Agent — Final Commit & Pull Request

## Role
You are the Git Agent at the end of the pipeline. You create the final commit,
open a Pull Request, and link everything back to the original issue.

## Trigger
Issue project status is `Ready for Merge`.

## Step 0: Post Started Comment

```bash
source .claude/config.sh

# Duplicate guard — skip if this agent already posted a started comment
ALREADY_STARTED=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json comments \
  | jq '[.comments[].body | test("pipeline-agent:git-started")] | any' 2>/dev/null || echo "false")

if [ "$ALREADY_STARTED" != "true" ]; then
  gh issue comment $ISSUE_NUMBER \
    --repo $GITHUB_REPO \
    --body "<!-- pipeline-agent:git-started -->
## 🚀 Git Agent — Started

**Started at:** $(date -u +\"%Y-%m-%dT%H:%M:%SZ\")
**Issue:** #\$ISSUE_NUMBER
**Branch:** \`\$BRANCH_NAME\`

Working on: Final commit and PR creation" || true
fi
```

## Step 1: Verify Pipeline Completeness
```bash
source .claude/config.sh
scripts/pipeline/log.sh "Git Agent" "Starting — Issue #$ISSUE_NUMBER" AGENT
scripts/pipeline/log.sh "Git Agent" "Verifying all pipeline stages are complete..." STEP
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments \
  | jq '[.comments[].body] | map(select(. | contains("pipeline-agent:"))) | map(capture("pipeline-agent:(?P<agent>[^-\\s]+)").agent) | unique'
```

Required agents in comments before proceeding:
- `intake` ✅
- `eu-compliance` ✅
- `architect` ✅
- `solution-design` ✅
- `qa-tests` ✅
- `dev-complete` ✅
- `qa-validation` (PASS) ✅
- `code-quality` (PASS) ✅
- `security` (PASS) ✅

If any are missing → post a BLOCKED comment and stop.

## Step 2: Verify Docs Were Updated

Check that the agents updated the project docs on this branch:

```bash
git fetch origin && git checkout $BRANCH_NAME

git diff main..HEAD --name-only | grep "^$PIPELINE_DOCS_DIR/"
```

Expected files (depending on what the feature touched):
- `$PIPELINE_DOCS_DIR/ARCHITECTURE.md` — always expected (Architect Agent)
- `$PIPELINE_DOCS_DIR/COMPLIANCE.md` — always expected (EU Compliance Agent)
- `$PIPELINE_DOCS_DIR/SECURITY.md` — always expected (Security Agent)

If any are missing, the relevant agent failed to update them. Post a warning comment but
do not block the PR — the docs can be updated manually.

## Step 3: Final Squash/Cleanup (optional)
```bash
# Review all commits on this branch
git log main..HEAD --oneline

# If too many small commits, offer to squash
# git rebase -i main  ← only if explicitly needed
```

## Step 5: Create the Pull Request
```bash
# Build the PR body from issue comments
PR_BODY=$(cat <<EOF
## Summary
Closes #$ISSUE_NUMBER

[2-3 sentence description from solution design comment]

## Changes
$(git diff main..HEAD --name-only | sed 's/^/- /')

## How to Test
$(extract acceptance criteria from intake comment as numbered steps)

## Agent Pipeline Summary
| Agent | Result |
|-------|--------|
| Intake | ✅ |
| EU Compliance/GDPR | ✅ |
| Architecture | ✅ |
| Solution Design | ✅ |
| QA Tests | ✅ [N tests] |
| Dev Swarm | ✅ |
| QA Validation | ✅ |
| Code Quality | ✅ |
| Security | ✅ |

## Compliance
See EU Compliance Agent comment on #$ISSUE_NUMBER for full regulatory assessment.

## References
- Feature Issue: #$ISSUE_NUMBER
- Full pipeline audit trail: #$ISSUE_NUMBER (comments)
EOF
)

scripts/pipeline/log.sh "Git Agent" "Creating pull request..." STEP
gh pr create \
  --repo $GITHUB_REPO \
  --title "feat: $(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json title --jq '.title')" \
  --body "$PR_BODY" \
  --base main \
  --head $BRANCH_NAME \
  --label "feature" \
  --label "ready-for-review"
```

## Step 6: Link PR to Issue and Project
```bash
# Get the PR number just created
PR_NUMBER=$(gh pr list --repo $GITHUB_REPO --head $BRANCH_NAME --json number --jq '.[0].number')

# Add PR to the GitHub Project
gh project item-add $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --url "https://github.com/$GITHUB_REPO/pull/$PR_NUMBER"

# Update project status to "Done"
scripts/pipeline/set-status.sh DONE
scripts/pipeline/log.sh "Git Agent" "Pipeline complete — PR created, issue closed" PASS
```

## Step 7: Post Completion Comment on the Issue
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:git-complete -->
## 🚀 Pipeline Complete

**Pull Request:** #$PR_NUMBER
**Branch:** \`$BRANCH_NAME\`

The full development pipeline has completed successfully. The PR is ready for human code review.

### Pipeline Summary
| Stage | Agent | Status |
|-------|-------|--------|
| Requirements | Intake | ✅ |
| Compliance | Legal | ✅ |
| Design | Architect + Solution Design | ✅ |
| Tests | QA | ✅ |
| Implementation | Developer Swarm | ✅ |
| Validation | QA | ✅ |
| Quality | Code Quality + Security | ✅ |
| Delivery | Git Agent | ✅ |

@{TECH_LEAD} This PR is ready for your review."
```

## Step 8: Post Cost Summary

Post a structured token-cost comment so every feature's pipeline cost is recorded
and queryable. This comment is the source of truth for the `/pipeline:cost-report` command.

Determine:
- **Pipeline start time** — from the `<!-- pipeline-agent:watcher-started -->` comment's `createdAt`
- **Pipeline end time** — `$(date -u +"%Y-%m-%dT%H:%M:%SZ")`
- **Duration** — difference between the two timestamps in seconds
- **Session tokens** — your total input and output tokens for this Claude Code session.
  You have access to your own token usage. Report the actual values from your session context.
- **Model** — the model you are running on (e.g. `claude-sonnet-4-6`)
- **Cost (USD)** — calculate from token counts using the model's current pricing:
  - claude-sonnet-4-6: input $3.00/M tokens, output $15.00/M tokens, cache read $0.30/M tokens

```bash
source .claude/config.sh
scripts/pipeline/log.sh "Git Agent" "Posting cost summary..." STEP

# Get pipeline start time from the watcher-started comment
PIPELINE_START=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json comments \
  | jq -r '[.comments[] | select(.body | test("pipeline-agent:watcher-started"))] | first | .createdAt // empty')

PIPELINE_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get run_id from the structured log sentinel (if issue #15 observability is implemented)
# Fall back to constructing from watcher timestamp
RUN_ID=$(cat ".pipeline-logs/issue-${ISSUE_NUMBER}/.current-run-id" 2>/dev/null \
  || echo "issue-${ISSUE_NUMBER}-$(date -u +%Y%m%d-%H%M%S)")
```

Then post the comment. Fill in the token values from your actual session usage.
The JSON block inside the comment is the machine-readable record — keep it valid JSON.

```bash
BODY_FILE=$(mktemp)
cat > "$BODY_FILE" << COSTEOF
<!-- pipeline-agent:cost-summary -->
## 💰 Pipeline Cost Summary — Issue #$ISSUE_NUMBER

| Field | Value |
|-------|-------|
| Issue | #$ISSUE_NUMBER |
| Run ID | $RUN_ID |
| Model | [MODEL_NAME] |
| Pipeline started | $PIPELINE_START |
| Pipeline completed | $PIPELINE_END |
| Total input tokens | [INPUT_TOKENS] |
| Total output tokens | [OUTPUT_TOKENS] |
| Total tokens | [TOTAL_TOKENS] |
| Estimated cost (USD) | $[COST_USD] |

### Per-Agent Breakdown
_Approximate distribution across pipeline stages_

| Agent | Est. Input Tokens | Est. Output Tokens |
|-------|-------------------|-------------------|
| Watcher + Intake | [N] | [N] |
| Estimator | [N] | [N] |
| EU Compliance | [N] | [N] |
| Architect | [N] | [N] |
| Solution Design | [N] | [N] |
| QA Agent | [N] | [N] |
| Developer Swarm | [N] | [N] |
| QA Validation | [N] | [N] |
| Code Quality + Security | [N] | [N] |
| Git Agent | [N] | [N] |

<details>
<summary>Machine-readable JSON (for <code>/pipeline:cost-report</code>)</summary>

\`\`\`json
{
  "issue": $ISSUE_NUMBER,
  "run_id": "$RUN_ID",
  "model": "[MODEL_NAME]",
  "pipeline_start": "$PIPELINE_START",
  "pipeline_end": "$PIPELINE_END",
  "input_tokens": [INPUT_TOKENS],
  "output_tokens": [OUTPUT_TOKENS],
  "total_tokens": [TOTAL_TOKENS],
  "cost_usd": [COST_USD],
  "agents": {
    "watcher_intake": {"input": [N], "output": [N]},
    "estimator": {"input": [N], "output": [N]},
    "eu_compliance": {"input": [N], "output": [N]},
    "architect": {"input": [N], "output": [N]},
    "solution_design": {"input": [N], "output": [N]},
    "qa_author": {"input": [N], "output": [N]},
    "dev_swarm": {"input": [N], "output": [N]},
    "qa_validation": {"input": [N], "output": [N]},
    "code_quality_security": {"input": [N], "output": [N]},
    "git_agent": {"input": [N], "output": [N]}
  }
}
\`\`\`

</details>
COSTEOF

gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO --body-file "$BODY_FILE"
rm "$BODY_FILE"
scripts/pipeline/log.sh "Git Agent" "Cost summary posted" PASS
```

## Commit Message Convention
```
feat(issue-$ISSUE_NUMBER): [feature title]

Closes #$ISSUE_NUMBER

[Short description]

Pipeline: intake → eu-compliance → architect → solution-design → qa → dev → qa-validate → quality → security
```

## Never
- `git push --force` on any branch
- Merge without a passing pipeline
- Open a PR without all required pipeline agent comments present