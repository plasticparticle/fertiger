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

Identify the language and toolchain from project files — do not assume:

```bash
# Detect package manager / language
ls package.json Cargo.toml go.mod requirements.txt pyproject.toml pom.xml build.gradle 2>/dev/null
```

| File found | Stack | Test command | Lint command |
|------------|-------|-------------|--------------|
| `package.json` | Node/JS/TS | see scripts in package.json | `npm run lint` / `npx eslint` |
| `Cargo.toml` | Rust | `cargo test` | `cargo clippy` |
| `go.mod` | Go | `go test ./...` | `go vet ./...` |
| `requirements.txt` / `pyproject.toml` | Python | `pytest` / `python -m pytest` | `ruff check` / `flake8` |
| `pom.xml` | Java/Maven | `mvn test` | `mvn checkstyle:check` |
| `build.gradle` | Java/Kotlin/Gradle | `./gradlew test` | `./gradlew lint` |

```bash
# For Node projects: check what test runner and scripts are configured
cat package.json | jq '.scripts'
```

Use the project's configured commands throughout — never assume `npm run test`.

---

## Step 3: Understand the Tests First

Read every test file in your area before writing a single line of implementation.
The tests are your contract — understand them completely before you start.

```bash
# Find your test files (adapt extension to language)
find tests/ -name "*[your-area]*" -type f
```

For each test file, read it in full. Note:
- What inputs the tests provide
- What outputs / behaviour they assert
- What dependencies or mocks they set up
- Edge cases and error paths tested

**Do not start implementing until you understand every test.**

---

## Step 4: Read Existing Code Before Writing

For every **MODIFY** file in your assignment, read the full current file first:

```bash
# Read each file you will modify — understand existing patterns before touching them
cat [file-to-modify]
```

For **CREATE** files, read 2–3 neighbouring files in the same directory to
understand conventions (naming, imports, error handling, module structure).

Ask yourself:
- What patterns does the existing code use?
- What would a reviewer expect to see here?
- What shared utilities or base classes should I extend rather than rewrite?

---

## Step 5: Check for Dependency on Other Agents

Before implementing, check whether your files depend on interfaces or types
that another agent in the swarm is creating simultaneously:

```bash
# See what other dev agents have already pushed
git log origin/$BRANCH_NAME --oneline --since="1 hour ago"
```

If your code imports from a file another agent owns and that file doesn't
exist yet:
1. Post a comment flagging the dependency (see blocked template below)
2. Implement a stub / interface first so your tests can at least compile
3. Complete the real integration once the dependency is pushed

---

## Step 6: Implement

Write code that makes your tests pass. Follow the patterns you read in Step 4.

**Universal rules (all languages):**
- No debug/print statements in production paths (`console.log`, `print`, `fmt.Println`, etc.)
- Handle errors explicitly — no silent catches, no bare `except`, no `unwrap()` in production
- Business logic belongs in services/domain layer — not in route handlers, controllers, or CLI entrypoints
- Every public function in the core domain should be unit-testable in isolation
- No hardcoded secrets, URLs, or environment-specific values — use config/env
- Respect compliance constraints from the EU Compliance Agent (data residency, encryption, PII handling)

**After each file, verify it compiles / parses:**
```bash
# Node/TS example
npx tsc --noEmit

# Go
go build ./...

# Rust
cargo check

# Python
python -m py_compile [file]
```

Fix compile errors immediately — do not accumulate them.

---

## Step 7: Run Tests Incrementally

Do not wait until everything is done. After each file is complete, run the
relevant tests:

```bash
# Run only the tests covering your area (adapt to your stack/runner)
# Jest (Node):      npx jest --testPathPattern="[your-area]"
# Go:               go test ./[package]/...
# Pytest:           pytest tests/[your-area]/ -v
# Cargo:            cargo test [module_name]
# Maven:            mvn test -Dtest=[TestClass]
```

If tests fail, fix them before moving to the next file. Do not carry forward
broken code.

---

## Step 8: Final Verification

When all your files are done, run the full test suite for your area plus
a static analysis pass:

```bash
# Full test run for your area
[test command] [your area filter]

# Lint / static analysis
[lint command]

# Type check (if applicable)
[type check command]
```

If anything fails, fix it now. Do not push failing code.

---

## Step 9: Pull, Then Commit and Push

```bash
# Pull any changes other agents have pushed while you were working
git pull origin $BRANCH_NAME --rebase

# Stage only YOUR assigned files — never stage files outside your assignment
git add [list your specific files explicitly]

# Verify what you're about to commit
git diff --cached --stat

git commit -m "feat($FEATURE_SLUG): implement [your area]

Implements: REQ-XXX, REQ-XXX
Tests: [test command] [filter]
Files: [list]"

git push origin $BRANCH_NAME
```

If the rebase has conflicts with another agent's changes:
1. Resolve the conflict, preferring the union of both agents' work
2. If the conflict is in a file outside your assignment, notify the team lead before resolving
3. Never discard another agent's work to resolve a conflict

---

## Step 10: Signal Completion

```bash
TEST_OUTPUT=$([test command] [your area filter] 2>&1 | tail -20)

gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-$AGENT_NAME -->
## 💻 Dev Agent ($AGENT_NAME) — Complete

**Assigned area:** [description]

**Files implemented:**
$(git diff main..HEAD --name-only | grep [your pattern] | sed 's/^/- /')

**Test result:** ✅ PASS / ❌ FAIL
**Tests run:** [N] passed, [N] failed, [N] skipped

\`\`\`
$TEST_OUTPUT
\`\`\`

**Static analysis:** ✅ PASS / ❌ FAIL (describe any issues)

**Notes for team lead / QA:**
[Any integration notes, known limitations, or things to verify]"
```

---

## On QA Retry (status returned to `In Development`)

Read the QA validation failure comment carefully:

```bash
gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --comments \
  --json comments \
  | jq '[.comments[] | select(.body | contains("pipeline-agent:qa-validation"))] | last'
```

- Fix **only** what the failure report describes
- Do not refactor unrelated code
- Re-run the failing tests locally before pushing
- Post a new Step 10 completion comment with updated results

---

## Blocked Template

If you cannot proceed (missing dependency, conflicting file ownership, unclear requirement):

```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-$AGENT_NAME-blocked -->
## ⚠️ Dev Agent ($AGENT_NAME) — Blocked

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
  | jq '[.comments[].body | select(contains("pipeline-agent:dev-"))] | length'

# Set status to QA Review
gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $QA_REVIEW_OPTION_ID

gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO \
  --body "<!-- pipeline-agent:dev-complete -->
## 💻 Developer Swarm — All Agents Complete

All implementation files committed. Handing off to QA Validation.

**Agents reported:** [list]
**Total files changed:** $(git diff main..HEAD --name-only | wc -l)"
```
