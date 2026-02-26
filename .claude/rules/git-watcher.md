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

Use the pre-built poll script — it checks the project board and label fallback
in one call and returns structured JSON:

```bash
POLL_RESULT=$(bash .claude/scripts/poll-once.sh)
POLL_EXIT=$?
echo "$POLL_RESULT"
```

Exit code reference:
- `0` — nothing to do
- `1` — ready issues found (`.ready[]`)
- `2` — approved issues found (`.approved[]`)
- `3` — both

Parse the results:
```bash
READY_ISSUES=$(echo "$POLL_RESULT" | jq '.ready')
APPROVED_ISSUES=$(echo "$POLL_RESULT" | jq '.approved')
```

## Step 3: For Each Ready Issue

For each issue found, check it hasn't already been processed:
```bash
# Check for existing pipeline comments — use test() not contains() to avoid jq \! escape bug
ALREADY_STARTED=$(gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments \
  | jq '[.comments[].body | test("pipeline-agent:")] | any')

if [ "$ALREADY_STARTED" = "true" ]; then
  echo "Issue #$ISSUE_NUMBER already in pipeline — skipping"
  continue
fi
```

If a comment from the pipeline already exists, skip this issue — it's already in progress.

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

If running in watch mode (`/pipeline:watch`), run the pre-built watch loop.
It polls every 5 minutes, resets idle timer when work is found, and stops
after 8 hours of inactivity:

```bash
bash .claude/scripts/watch.sh
```

The script streams `[watcher] ACTION: ...` lines when issues are ready or
approved. React to those lines — do not reconstruct the polling logic inline.

To override timing for testing:
```bash
POLL_INTERVAL=60 MAX_IDLE_SECONDS=600 bash .claude/scripts/watch.sh
```

## Polling Interval
Defined in `.claude/scripts/watch.sh` — default 300s poll, 28800s (8h) idle timeout.

## Error Handling
If any agent in the pipeline sets `pipeline:blocked` label:
- Do NOT continue to the next stage
- Send a notification comment tagging the issue author
- Stop the pipeline for that issue until the label is removed