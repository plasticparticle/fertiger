# QA Agent Rules

## Role
Two modes:
- **Mode 1 — Test Author:** Write tests before dev starts (TDD contract)
- **Mode 2 — Validator:** Run tests and verify acceptance criteria after dev

---

## Step 0: Triage Check

```bash
source .claude/config.sh
TRIAGE_LEVEL=$(ISSUE_NUMBER=$ISSUE_NUMBER sh scripts/pipeline/triage.sh 2>/dev/null || echo "STANDARD")
HAS_FULL_REVIEW=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json labels \
  --jq '[.labels[].name] | contains(["pipeline:full-review"])' 2>/dev/null || echo "false")
[ "$HAS_FULL_REVIEW" = "true" ] && TRIAGE_LEVEL="COMPLEX"
```

Test suite by triage level:
- **TRIVIAL** → unit tests only
- **STANDARD** → unit + integration tests
- **COMPLEX** → unit + integration + regression tests

---

## Mode 1: Test Author

### Trigger
Issue has `pipeline:approved` label AND project status is `In Development`.

### Step 1: Fetch Only What You Need

Do **not** fetch the entire comment thread. Pull only the two comments that matter:

```bash
source .claude/config.sh

# Get intake comment (acceptance criteria)
gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments --json comments \
  | jq '[.comments[] | select(.body | contains("pipeline-agent:intake"))] | last | .body'

# Get solution design comment (file list)
gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments --json comments \
  | jq '[.comments[] | select(.body | contains("pipeline-agent:solution-design"))] | last | .body'
```

Extract: acceptance criteria list, affected file list.

### Step 2: Study Existing Test Conventions

Before writing a single test, read one existing test file to match project patterns (mocking style, assertion library, fixture approach, describe/it structure):

```bash
git fetch origin && git checkout $BRANCH_NAME

# Find an existing test file to use as a style reference
find tests/ -name "*.test.*" -type f | head -1 | xargs cat
```

### Step 3: Create Test Structure

```bash
mkdir -p tests/unit/$FEATURE_SLUG
[ "$TRIAGE_LEVEL" != "TRIVIAL" ] && mkdir -p tests/integration/$FEATURE_SLUG
[ "$TRIAGE_LEVEL" = "COMPLEX" ] && mkdir -p tests/regression/$FEATURE_SLUG
```

### Step 4: Write Tests

Naming: `should [behaviour] when [condition]`

For **each acceptance criterion**, write:

1. **Happy path** — valid input, expected output. One test per AC.
2. **Error/failure path** — what happens when a dependency throws, input is invalid, or auth fails. At least one per AC.
3. **Boundary/edge case** — empty collections, zero values, max lengths, concurrent calls, missing optional fields. At least one per AC where applicable.
4. **Negative assertion** — something that must *not* happen (e.g. sensitive field must not appear in response, event must not fire twice).

Additionally, scan the solution design file list for any of these patterns and add tests if present:

| Pattern | Extra tests to write |
|---------|----------------------|
| Auth / permissions | Unauthenticated request returns 401; wrong role returns 403 |
| Database writes | Transaction rollback on partial failure |
| External API calls | Timeout and 5xx handling; retry behaviour |
| Pagination / lists | Empty result set; single item; page boundary |
| Async / queues | Message not lost on consumer crash |

Tests **must fail** at this point — no implementation exists yet. That is correct and expected.

### Step 5: Commit Tests

```bash
git add tests/
git commit -m "test($FEATURE_SLUG): TDD contract for #$ISSUE_NUMBER

ACs covered: $(list AC identifiers)
Suites: $(echo $TRIAGE_LEVEL | tr '[:upper:]' '[:lower:]')"
git push origin $BRANCH_NAME
```

### Step 6: Post Summary Comment

Keep the comment concise. Only expand the table for COMPLEX triage.

```bash
# Build test inventory dynamically from what was actually written
TEST_FILES=$(find tests/ -path "*/$FEATURE_SLUG/*" -name "*.test.*" | sort)
TEST_COUNT=$(grep -r "it\(\|test\(" tests/$FEATURE_SLUG 2>/dev/null | wc -l | tr -d ' ')

gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:qa-tests -->
## 🧪 QA — Tests Written

**Triage:** $TRIAGE_LEVEL | **Tests:** $TEST_COUNT | **Status:** failing (expected — TDD)

$(echo "$TEST_FILES" | sed 's/^/- \`/' | sed 's/$/\`/')

✅ Developer Swarm can now start."
```

---

## Mode 2: Validator

### Trigger
Issue project status is `QA Review`.

### Step 1: Fetch Failure Context (if this is a retry)

```bash
# Check if this is a retry — read only the last QA validation comment
LAST_QA=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments --json comments \
  | jq '[.comments[] | select(.body | contains("pipeline-agent:qa-validation"))] | last | .body')

RETRY_COUNT=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments --json comments \
  | jq '[.comments[] | select(.body | contains("pipeline-agent:qa-validation"))] | length')
```

If `RETRY_COUNT > 0`, read the failure details before running tests so you know what to focus on.

### Step 2: Run Tests

```bash
git fetch origin && git checkout $BRANCH_NAME

npm run test -- --testPathPattern=$FEATURE_SLUG
npm run test:coverage -- --testPathPattern=$FEATURE_SLUG
```

### Step 3a: All Tests Pass → Advance

```bash
PASS_COUNT=$(...)  # parse from test output
COVERAGE=$(...)    # parse from coverage output

gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:qa-validation -->
## ✅ QA Validation PASSED

**Tests:** $PASS_COUNT passed, 0 failed | **Coverage:** $COVERAGE%

$([ "$TRIAGE_LEVEL" = "TRIVIAL" ] && echo "All ACs verified." || echo "
| AC | Result |
|----|--------|
$(list each AC with ✅ PASS)")

Handing off to Code Quality Agent."

gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $CODE_REVIEW_OPTION_ID
```

### Step 3b: Tests Fail → Retry or Escalate

```bash
if [ "$RETRY_COUNT" -ge 3 ]; then
  gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO --body "<!-- pipeline-agent:qa-escalation -->
## ❌ QA Escalation — 3 Failures

Human intervention required. @{TECH_LEAD} please review.

$(list failed tests and unmet ACs)"
  gh issue edit $ISSUE_NUMBER --repo $GITHUB_REPO --add-label "pipeline:blocked"

else
  gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO --body "<!-- pipeline-agent:qa-validation -->
## ❌ QA Validation FAILED (Attempt $((RETRY_COUNT+1))/3)

### Failed Tests
$(list test names and error messages — be specific)

### Unmet Acceptance Criteria
$(for each unmet AC: expected behaviour | actual behaviour)

### Root Cause Hypothesis
$(concise analysis — one paragraph max)

### Fix Guidance for Dev Agent
$(specific, actionable — reference exact file and function if possible)

🔄 Returning to Developer Swarm."

  gh project item-edit \
    --id $PROJECT_ITEM_ID \
    --field-id $STATUS_FIELD_ID \
    --project-id $PROJECT_NODE_ID \
    --single-select-option-id $IN_DEVELOPMENT_OPTION_ID
fi
```
