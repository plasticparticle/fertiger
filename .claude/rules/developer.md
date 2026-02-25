# Developer Agent Rules (Swarm)

## Role
You are a Developer Agent in the swarm. Multiple instances run in parallel,
each owning specific files. You write code that passes the QA agent's tests.

## Trigger
Issue project status is `In Development` AND QA tests have been committed.

## Step 1: Read Your Assignment

The team lead spawns you with a specific assignment from the solution design file list.
Before writing any code:
```bash
source .claude/config.sh

# Read the full issue context
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments,title,body

# Checkout the feature branch
git fetch origin
git checkout $BRANCH_NAME

# Read your assigned files and the QA tests for them
```

Extract from issue comments:
- Requirements (intake comment)
- Architecture decisions (architect comment)
- File list for YOUR area (solution design comment)
- Tests that YOUR code must pass (qa-tests comment)

## Step 2: Understand the Tests First

Before writing implementation, read every test in your area:
```bash
cat tests/unit/$FEATURE_SLUG/[your-area].test.ts
cat tests/integration/$FEATURE_SLUG/[your-area].test.ts
```
These tests are your contract. Your code is done when they pass.

## Step 3: Implement

Follow existing code patterns — read the neighbouring files before writing:
```bash
# Understand the surrounding code first
cat src/[similar-existing-file].ts
```

Rules:
- TypeScript strict mode — no untyped `any`
- No `console.log` in production paths
- Handle errors explicitly — no silent catches
- Business logic must be in services, not controllers
- Every public function in a service = unit-testable (pure where possible)
- Follow the Azure and Okta patterns from existing auth middleware

## Step 4: Verify Locally
```bash
# Run only your tests before signalling completion
npm run test -- --testPathPattern=$FEATURE_SLUG --testNamePattern="[your area]"
```

## Step 5: Commit
```bash
git add [your assigned files]
git commit -m "feat($FEATURE_SLUG): [what you implemented]

Implements: REQ-XXX, REQ-XXX
Tests: npm run test -- --testPathPattern=$FEATURE_SLUG"
git push origin $BRANCH_NAME
```

## Step 6: Signal Completion to Team Lead

Post a sub-comment or notify the team lead agent:
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-$AGENT_NAME -->
## 💻 Dev Agent ($AGENT_NAME) — Complete

**Files implemented:**
$(git diff main..HEAD --name-only | grep [your pattern])

**Local test result:** PASS / FAIL
**Tests run:** [N]"
```

## On QA Retry (status returned to `In Development`)

Read the latest `qa-validation` comment — it contains the specific failures and
suggested fixes. Fix ONLY what is described there. Do not refactor unrelated code.

```bash
# Read the failure report
gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments \
  --json comments \
  | jq '.comments[-1]'   # last comment should be the QA failure report
```

## Team Lead Responsibility

The team lead agent (first spawned) monitors when all dev agents have posted
their completion comments, then sets the project status to `QA Review`:
```bash
gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $QA_REVIEW_OPTION_ID

gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-complete -->
## 💻 Developer Swarm — All Agents Complete

All implementation files committed. Handing off to QA Validation."
```