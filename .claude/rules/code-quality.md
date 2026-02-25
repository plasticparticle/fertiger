# Code Quality Agent Rules

## Role
You enforce code quality standards after QA passes.
You do NOT change functionality — you improve maintainability.

## Trigger
Issue project status is `Code Review`.

## Step 1: Checkout and Run Automated Checks
```bash
source .claude/config.sh
git fetch origin && git checkout $BRANCH_NAME

npm run lint
npx tsc --noEmit
npm run test:coverage
```

## Step 2: Review Changed Files Only
```bash
git diff main...HEAD --name-only
```
Review only files in this diff.

## Step 3: Post Quality Report
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "$(cat <<'EOF'
<!-- pipeline-agent:code-quality -->
## 🔬 Code Quality Agent — Review

### Automated Checks
| Check | Result |
|-------|--------|
| ESLint | ✅ PASS / ❌ FAIL |
| TypeScript | ✅ PASS / ❌ FAIL |
| Test Coverage | X% (threshold: Y%) |

### Manual Review
| Category | Result | Notes |
|----------|--------|-------|
| Function length (≤40 lines) | PASS/FAIL | |
| Naming clarity | PASS/FAIL | |
| Error handling | PASS/FAIL | |
| No business logic in controllers | PASS/FAIL | |
| No hardcoded config values | PASS/FAIL | |
| JSDoc on public functions | PASS/FAIL | |

### Issues Found
[List specific violations with file:line references]

### Auto-fixed
[List issues auto-corrected by eslint --fix]

### Overall: [PASS / FAIL]
---
[PASS: ✅ Handing off to Security Agent]
[FAIL: ❌ Issues above must be resolved before proceeding]
EOF
)"
```

## Step 4: Update Status
```bash
# PASS → Security Review
gh project item-edit \
  --id $PROJECT_ITEM_ID --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $SECURITY_REVIEW_OPTION_ID

# FAIL → set pipeline:blocked
gh issue edit $ISSUE_NUMBER --repo $GITHUB_REPO --add-label "pipeline:blocked"
```

## Auto-fix Allowed
```bash
npx eslint --fix src/
npx prettier --write src/
git add -A && git commit -m "chore($FEATURE_SLUG): auto-fix code quality issues"
git push origin $BRANCH_NAME
```

---
---

# Security Agent Rules

## Role
You review new code for cybersecurity vulnerabilities. Focus ONLY on the diff.

## Trigger
Issue project status is `Security Review`.

## Step 1: Get the Diff and Read Security Context
```bash
source .claude/config.sh
git fetch origin && git checkout $BRANCH_NAME
git diff main...HEAD -- src/ tests/
```

Also read `docs/SECURITY.md` before reviewing. It describes the established auth patterns,
known risk areas, and past findings — use it to calibrate your review and spot regressions.

## Step 2: Run Automated Scans
```bash
npm audit --audit-level=moderate
npx semgrep --config auto src/   # if available
```

## Step 3: Post Security Report
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "$(cat <<'EOF'
<!-- pipeline-agent:security -->
## 🔒 Security Agent — Audit

### Automated Scan Results
| Tool | Result | Findings |
|------|--------|----------|
| npm audit | PASS/FAIL | N vulnerabilities |
| semgrep | PASS/FAIL | N findings |

### Manual Review — OWASP Top 10
| Check | Result | Notes |
|-------|--------|-------|
| Input validation / Injection | PASS/FAIL | |
| Okta token server-side validation | PASS/FAIL | |
| No auth logic client-side only | PASS/FAIL | |
| No secrets in source | PASS/FAIL | |
| Personal data encrypted | PASS/FAIL | |
| Sensitive data NOT in localStorage | PASS/FAIL | GDPR |
| Azure Redis TTL set for sessions | PASS/FAIL | |
| Error messages don't leak data | PASS/FAIL | |
| Logging doesn't include PII | PASS/FAIL | |

### Vulnerabilities Found
| Severity | Finding | File:Line | Fix |
|----------|---------|-----------|-----|
| [CRITICAL/HIGH/MEDIUM/LOW] | | | |

### Overall: [PASS / CONDITIONAL / BLOCKED]
- PASS = no critical/high issues
- CONDITIONAL = medium/low issues noted but not blocking
- BLOCKED = critical/high issues must be fixed

---
[PASS: ✅ Handing off to Git Agent]
[BLOCKED: ❌ Fix the issues above before merge]
EOF
)"
```

## Step 4: Update docs/SECURITY.md

Read the current `docs/SECURITY.md`, then update it:

**Auth & Authorisation Patterns** — if this feature introduced or changed how auth works,
update this section to reflect the current pattern.

**Established Security Patterns** — if this review confirmed or introduced a security
pattern that all future features should follow (e.g. "all file uploads must be virus-scanned
before storage"), add it here.

**Known Risk Areas** — if a risk was found and mitigated, update the relevant row.
If a new risk area was identified (even if not blocking), add a row.

**Security Audit Log** — always append a row regardless of result:
```markdown
| #$ISSUE_NUMBER | [feature title] | PASS/CONDITIONAL/BLOCKED | [critical count] | [high] | [medium] | [low] | [YYYY-MM-DD] |
```

Commit to the feature branch:
```bash
git add docs/SECURITY.md
git commit -m "docs(security): update posture for issue #$ISSUE_NUMBER"
git push origin $BRANCH_NAME
```

## Step 5: Update Status
```bash
# PASS → Ready for Merge
gh project item-edit \
  --id $PROJECT_ITEM_ID --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $READY_FOR_MERGE_OPTION_ID

# BLOCKED → set pipeline:blocked and tag author
gh issue edit $ISSUE_NUMBER --repo $GITHUB_REPO --add-label "pipeline:blocked"
gh issue comment $ISSUE_NUMBER --repo $GITHUB_REPO \
  --body "@{TECH_LEAD} Security issues require manual review before this can proceed."
```