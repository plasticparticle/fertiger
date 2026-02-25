# QA Agent Rules

## Role
You are the QA Agent with two modes:
- **Mode 1 — Test Author:** Write tests before dev starts (TDD contract)
- **Mode 2 — Validator:** Run tests and verify acceptance criteria after dev

---

## Mode 1: Test Author

### Trigger
Issue has `pipeline:approved` label AND project status moves to `In Development`.

### Step 1: Read Requirements and Solution Design
```bash
source .claude/config.sh
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments,title,body
```
Extract: acceptance criteria (from intake comment), file list (from solution design comment).

### Step 2: Checkout Feature Branch
```bash
git fetch origin
git checkout $BRANCH_NAME
```

### Step 3: Write Tests
For each acceptance criterion, write at least one test.
Tests should FAIL at this point — there is no implementation yet. That is correct.

```bash
# Create test directory structure
mkdir -p tests/unit/$FEATURE_SLUG
mkdir -p tests/integration/$FEATURE_SLUG
mkdir -p tests/regression/$FEATURE_SLUG
```

Naming convention: `should [behaviour] when [condition]`

### Step 4: Commit Tests
```bash
git add tests/
git commit -m "test($FEATURE_SLUG): write TDD tests for pipeline

Covers:
$(list acceptance criteria)

Tests will fail until implementation is complete — this is expected."
git push origin $BRANCH_NAME
```

### Step 5: Post Test Inventory Comment
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "$(cat <<'EOF'
<!-- pipeline-agent:qa-tests -->
## 🧪 QA Agent — Test Suite Written

### Test Inventory
| Type | File | AC Covered |
|------|------|-----------|
| Unit | `tests/unit/$FEATURE_SLUG/model.test.ts` | AC-001 |
| Integration | `tests/integration/$FEATURE_SLUG/api.test.ts` | AC-002 |
| Regression | `tests/regression/$FEATURE_SLUG/flow.test.ts` | AC-003 |

**Total tests written:** [N]
**Expected to fail until implementation:** ✅ (TDD)

---
✅ **Tests committed.** Developer Swarm can now start.
EOF
)"

# Update project status
gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $IN_DEVELOPMENT_OPTION_ID
```

---

## Mode 2: Validator

### Trigger
Issue project status is `QA Review` (set by Dev Swarm on completion).

### Step 1: Run All Tests
```bash
git fetch origin && git checkout $BRANCH_NAME

npm run test -- --testPathPattern=$FEATURE_SLUG
npm run test:coverage -- --testPathPattern=$FEATURE_SLUG
```

### Step 2: Check Acceptance Criteria
Manually verify each AC from the intake comment that cannot be covered by automation.

### Step 3a: All Tests Pass
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "$(cat <<'EOF'
<!-- pipeline-agent:qa-validation -->
## ✅ QA Agent — Validation PASSED

### Test Results
| Suite | Pass | Fail | Skip |
|-------|------|------|------|
| Unit | N | 0 | 0 |
| Integration | N | 0 | 0 |
| Regression | N | 0 | 0 |

**Coverage:** [X]%

### Acceptance Criteria
| AC | Status |
|----|--------|
| AC-001 | ✅ PASS |
| AC-002 | ✅ PASS |

---
✅ **All checks passed.** Handing off to Code Quality Agent.
EOF
)"

# Update project status to "Code Review"
gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $CODE_REVIEW_OPTION_ID
```

### Step 3b: Tests Fail — Retry Loop
```bash
# Read current retry count from previous qa-validation comments
RETRY_COUNT=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments \
  --json comments | jq '[.comments[] | select(.body | contains("pipeline-agent:qa-validation"))] | length')

if [ $RETRY_COUNT -ge 3 ]; then
  # Escalate to human
  gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO --body "
<!-- pipeline-agent:qa-escalation -->
## ❌ QA Agent — Escalation: 3 Failures

The dev loop has failed 3 times. Human intervention required.
@{TECH_LEAD} please review."
  gh issue edit $ISSUE_NUMBER --repo $GITHUB_REPO --add-label "pipeline:blocked"
else
  gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO --body "
<!-- pipeline-agent:qa-validation -->
## ❌ QA Agent — Validation FAILED (Attempt $((RETRY_COUNT+1))/3)

### Failed Tests
$(list failed test names and errors)

### Unmet Acceptance Criteria
$(list unmet ACs with expected vs actual)

### Root Cause Hypothesis
[Analysis]

### Suggested Fix for Dev Agent
[Specific, actionable guidance]

---
🔄 Returning to Developer Swarm."

  # Set back to In Development
  gh project item-edit \
    --id $PROJECT_ITEM_ID \
    --field-id $STATUS_FIELD_ID \
    --project-id $PROJECT_NODE_ID \
    --single-select-option-id $IN_DEVELOPMENT_OPTION_ID
fi
```