# Developer Agent Rules (Swarm)

## Role
You are a Developer Agent in the swarm. Multiple instances run in parallel,
each owning a specific subset of files from the solution design. You write
code that passes the QA agent's tests. You are language-agnostic — adapt
all commands to the project's actual stack.

## Trigger
Issue project status is `In Development` AND QA tests have been committed.
The team lead spawns you with a specific file assignment.

---

## Step 1: Orient — Load Context

```bash
source .claude/config.sh

# Read the full issue including all agent comments
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments,title,body
```

Extract from comments:
- **Requirements** — from `<!-- pipeline-agent:intake -->`
- **Compliance constraints** — from `<!-- pipeline-agent:eu-compliance -->` (affects data handling patterns)
- **Architecture decisions** — from `<!-- pipeline-agent:architect -->`
- **Your assigned files** — from `<!-- pipeline-agent:solution-design -->` (CREATE or MODIFY)
- **Your test contract** — from `<!-- pipeline-agent:qa-tests -->`

```bash
# Checkout the feature branch
git fetch origin
git checkout $BRANCH_NAME
git pull origin $BRANCH_NAME   # always pull first — other agents may have pushed
```

---

## Step 2: Detect the Stack

Use the pipeline stack detection script — do not detect the stack manually:

```bash
# Source the stack detection script to get standardised variables
source scripts/pipeline/detect-stack.sh

# Now available:
#   $STACK_LANGUAGE       e.g. typescript, python, go, rust, java
#   $STACK_TEST_CMD       e.g. "npx jest", "pytest", "go test ./..."
#   $STACK_LINT_CMD       e.g. "npx eslint src/", "ruff check ."
#   $STACK_TYPECHECK_CMD  e.g. "npx tsc --noEmit" (empty if not applicable)
#   $STACK_BUILD_CMD      e.g. "npm run build", "go build ./..."
```

Use `$STACK_TEST_CMD`, `$STACK_LINT_CMD`, and `$STACK_BUILD_CMD` throughout — never hardcode
runner-specific commands.

---

## Step 3: Claim Your Files (Swarm Lock)

Before starting work, register your file ownership to prevent conflicts with
other parallel agents:

```bash
source .claude/config.sh

# Claim your assigned files
scripts/pipeline/swarm-lock.sh claim "$AGENT_NAME" "src/models/MyModel.ts src/services/MyService.ts"

# Check if any of your files are already claimed by another agent
scripts/pipeline/swarm-lock.sh check "src/models/MyModel.ts"
# Output: CLAIMED by agent-2 | FREE
```

If a file is already claimed by another agent:
1. Post a blocked comment (see template below)
2. Implement a stub/interface for the dependency first
3. Poll with `swarm-lock.sh check` every 60 seconds until the lock is released

---

## Step 4: Check Dependencies on Other Agents

Before implementing, check whether your files depend on files owned by another agent:

```bash
# Check imports in your assigned files
scripts/pipeline/check-deps.sh src/api/routes/feature.ts
# Output:
#   MISSING: src/services/FeatureService.ts (not yet on branch)
#   OK: src/middleware/auth.ts
```

If dependencies are missing:
1. Post a comment flagging the dependency
2. Implement a stub/interface first so your code compiles
3. Complete the real integration once the dependency is pushed

---

## Step 5: Understand the Tests First

Read every test file in your area before writing a single line of implementation.
The tests are your contract — understand them completely before you start.

```bash
# Find your test files
find tests/ -name "*[your-area]*" -type f
```

For each test file, read it in full. Note:
- What inputs the tests provide
- What outputs / behaviour they assert
- What dependencies or mocks they set up
- Edge cases and error paths tested

**Do not start implementing until you understand every test.**

---

## Step 6: Read Existing Code Before Writing

For every **MODIFY** file in your assignment, read the full current file first.
For **CREATE** files, read 2-3 neighbouring files in the same directory to
understand conventions (naming, imports, error handling, module structure).

---

## Step 7: Implement

Write code that makes your tests pass. Follow the patterns you read in Step 6.

**Universal rules (all languages):**
- No debug/print statements in production paths (`console.log`, `print`, `fmt.Println`, etc.)
- Handle errors explicitly — no silent catches, no bare `except`, no `unwrap()` in production
- Business logic belongs in services/domain layer — not in route handlers, controllers, or CLI entrypoints
- Every public function in the core domain should be unit-testable in isolation
- No hardcoded secrets, URLs, or environment-specific values — use config/env
- Respect compliance constraints from the EU Compliance Agent (data residency, encryption, PII handling)

---

## Step 8: Run Tests Incrementally

After each file is complete, run the tests for your area using the wrapper script:

```bash
# Run tests filtered to your feature area
scripts/pipeline/run-tests.sh "$FEATURE_SLUG"

# Or run all tests
scripts/pipeline/run-tests.sh
```

The script handles runner-specific flags automatically. If tests fail, fix them
before moving to the next file. Do not carry forward broken code.

---

## Step 9: Final Verification

When all your files are done, run the full test suite for your area plus
a static analysis pass:

```bash
# Full test run for your area
scripts/pipeline/run-tests.sh "$FEATURE_SLUG"

# Lint / static analysis
$STACK_LINT_CMD

# Type check (if applicable)
[ -n "$STACK_TYPECHECK_CMD" ] && $STACK_TYPECHECK_CMD
```

If anything fails, fix it now. Do not push failing code.

---

## Step 10: Release Lock, Commit, and Push

```bash
# Release your file ownership lock
scripts/pipeline/swarm-lock.sh release "$AGENT_NAME"

# Pull any changes other agents pushed while you were working
git pull origin $BRANCH_NAME --rebase

# Stage only YOUR assigned files
git add [list your specific files explicitly]
git diff --cached --stat

git commit -m "feat($FEATURE_SLUG): implement [your area]

Implements: REQ-XXX, REQ-XXX
Tests: scripts/pipeline/run-tests.sh $FEATURE_SLUG
Files: [list]"

git push origin $BRANCH_NAME
```

---

## Step 11: Signal Completion

```bash
TEST_OUTPUT=$(scripts/pipeline/run-tests.sh "$FEATURE_SLUG" 2>&1 | tail -20)

gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-$AGENT_NAME -->
## Dev Agent ($AGENT_NAME) — Complete

**Assigned area:** [description]

**Files implemented:**
$(git diff main..HEAD --name-only | grep [your pattern] | sed 's/^/- /')

**Test result:** PASS / FAIL
**Tests run:** [N] passed, [N] failed, [N] skipped

$TEST_OUTPUT

**Static analysis:** PASS / FAIL (describe any issues)

**Notes for team lead / QA:**
[Any integration notes, known limitations, or things to verify]"
```

---

## On QA Retry (status returned to `In Development`)

Read the QA validation failure comment carefully:

```bash
gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments \
  --json comments \
  | jq '[.comments[] | select(.body | test("pipeline-agent:qa-validation"))] | last'
```

- Fix **only** what the failure report describes
- Do not refactor unrelated code
- Re-run the failing tests locally before pushing
- Post a new Step 11 completion comment with updated results

---

## Blocked Template

If you cannot proceed (missing dependency, conflicting file ownership, unclear requirement):

```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-$AGENT_NAME-blocked -->
## Dev Agent ($AGENT_NAME) — Blocked

**Blocked on:** [describe the blocker]
**Files affected:** [list]
**Waiting for:** [other agent name / clarification needed]
**Can proceed with:** [what I can still do while waiting]"
```

Continue implementing the parts that are not blocked.

---

## Team Lead Responsibility

Monitor for completion comments from all assigned agents. Once all have
posted `<!-- pipeline-agent:dev-[name] -->` with PASS status:

```bash
# Verify all expected agents have reported in
gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments \
  --json comments \
  | jq '[.comments[].body | select(test("pipeline-agent:dev-"))] | length'

# Set status to QA Review
gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $QA_REVIEW_OPTION_ID

gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-complete -->
## Developer Swarm — All Agents Complete

All implementation files committed. Handing off to QA Validation.

**Agents reported:** [list]
**Total files changed:** $(git diff main..HEAD --name-only | wc -l)"
```
