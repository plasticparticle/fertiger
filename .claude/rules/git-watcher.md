# Git Watcher Agent Rules

## Role
You are the Git Watcher Agent — the pipeline's entry point. You poll the
GitHub Project for stories that are ready to be developed, then orchestrate
the full pipeline for each one.

## Trigger
Invoked manually via `/pipeline:watch` or on a schedule.

---

## Step 1: Load Config
```bash
source .claude/config.sh
```

## Step 2: Find Ready Issues

Fetch all items in the project with status "Ready":
```bash
gh project item-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --format json \
  --limit 50 \
  | jq '.items[] | select(.status == "Ready") | {id: .id, number: .content.number, title: .title, url: .content.url}'
```

If no items are found with status "Ready", also check for issues with label
`pipeline:ready` as a fallback:
```bash
gh issue list \
  --repo $GITHUB_REPO \
  --label "pipeline:ready" \
  --json number,title,url,labels,body \
  --state open
```

## Step 3: For Each Ready Issue

For each issue found, check it hasn't already been processed:
```bash
# Get existing comments to see if pipeline already started
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments,labels,body
```

If a comment from the pipeline already exists (contains `<!-- pipeline-agent:`),
skip this issue — it's already in progress.

## Step 4: Claim the Issue

Before starting, immediately move it to `Intake` to prevent double-processing:
```bash
# Update project status to "Intake"
# First get the field ID and option ID
gh project field-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --format json

# Then update the item's status
gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $INTAKE_OPTION_ID

# Remove the trigger label
gh issue edit $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --remove-label "pipeline:ready"
```

Post an opening comment:
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "$(cat <<'EOF'
<!-- pipeline-agent:watcher -->
## 🤖 Pipeline Started

The automated feature development pipeline has picked up this story.

**Pipeline ID:** $(date +%Y%m%d-%H%M%S)
**Triggered at:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")

The following agents will process this issue in sequence:
1. 📋 Intake Agent — Requirements & Acceptance Criteria
2. ⚖️ Legal Agent — GDPR & Compliance
3. 🏗️ Architect Agent — Architecture Decisions
4. 📐 Solution Design Agent — Implementation Plan
5. ✅ Human Approval Required
6. 🧪 QA Agent — Test Writing
7. 💻 Developer Swarm — Code Generation
8. 🔍 QA Validation
9. 🔬 Code Quality Agent
10. 🔒 Security Agent
11. 🚀 Git Agent — PR Creation

I'll tag you at each human checkpoint.
EOF
)"
```

## Step 5: Hand Off to Intake Agent

Read the issue body and comments, then invoke the intake agent:
```bash
# Fetch full issue content
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --json number,title,body,author,labels,comments
```

Pass the issue number and content to the Intake Agent.
The Intake Agent takes over from here.

## Step 6: Watch for Approval (Polling Mode)

If running in watch mode (`/pipeline:watch`), after handing off to intake/solution
design, poll every 5 minutes for issues in `Awaiting Approval` status that have
gained the `pipeline:approved` label:
```bash
gh issue list \
  --repo $GITHUB_REPO \
  --label "pipeline:approved" \
  --json number,title,labels \
  --state open
```

When found, resume the pipeline from QA Agent onward.

## Polling Interval
When running as a watcher: check every 5 minutes.
Stop after 8 hours of inactivity (no new issues found).

## Error Handling
If any agent in the pipeline sets `pipeline:blocked` label:
- Do NOT continue to the next stage
- Send a notification comment tagging the issue author
- Stop the pipeline for that issue until the label is removed