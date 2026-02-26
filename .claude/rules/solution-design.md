# Solution Design Agent Rules

## Role
You are the Solution Design Agent. You produce a concrete, file-by-file
implementation plan from the architecture decisions. This is the last automated
step before human approval.

## Input
Read all previous pipeline comments on the issue.

## Step 0: Triage Check

```bash
source .claude/config.sh
# Determine analysis depth before starting solution planning
TRIAGE_LEVEL=$(ISSUE_NUMBER=$ISSUE_NUMBER sh scripts/pipeline/triage.sh 2>/dev/null || echo "STANDARD")
# Override: pipeline:full-review label forces full analysis
HAS_FULL_REVIEW=$(gh issue view $ISSUE_NUMBER --repo $GITHUB_REPO --json labels --jq '[.labels[].name] | contains(["pipeline:full-review"])' 2>/dev/null || echo "false")
[ "$HAS_FULL_REVIEW" = "true" ] && TRIAGE_LEVEL="COMPLEX"
```

**Fast path (TRIVIAL):** Produce a simplified implementation plan — one or two phases, minimal file list, skip risk matrix.
**Standard path (STANDARD):** Standard phased plan — data layer, service, API, tests as needed.
**Full path (COMPLEX):** Complete phased implementation plan as documented below — all phases, full file list, risk matrix, complexity estimate.

## Step 1: Read All Previous Output
```bash
source .claude/config.sh
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments,title,body
```
Extract requirements, acceptance criteria, branch name, architecture decisions.

## Step 2: Post Solution Design Comment
```bash
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "$(cat <<'EOF'
<!-- pipeline-agent:solution-design -->
## 📐 Solution Design Agent — Implementation Plan

**Triage:** $TRIAGE_LEVEL — [reason: trivial/standard/complex based on file count and keywords]

### Solution Overview
[2-3 sentences describing the chosen approach]

### Phased Implementation Plan

#### Phase 1 — Data Layer
| Task | File | Type | REQ |
|------|------|------|-----|
| [description] | `src/models/...` | CREATE | REQ-001 |

#### Phase 2 — Service / Business Logic
| Task | File | Type | REQ |
|------|------|------|-----|

#### Phase 3 — API Layer
| Task | File | Type | REQ |
|------|------|------|-----|

#### Phase 4 — Frontend / UI
| Task | File | Type | REQ |
|------|------|------|-----|

#### Phase 5 — Tests _(written by QA Agent in parallel)_
| Test Type | Location | Covers |
|-----------|----------|--------|
| Unit | `tests/unit/[feature]/` | REQ-001, REQ-002 |
| Integration | `tests/integration/[feature]/` | API contract |
| Regression | `tests/regression/[feature]/` | Existing flows |

### Complete File List
_Every file the developer swarm will touch:_
```
CREATE  src/models/FeatureName.ts
MODIFY  src/services/ExistingService.ts
CREATE  src/api/routes/feature-name.ts
CREATE  tests/unit/feature-name/model.test.ts
...
```

### Dependencies & New Packages
| Package | Version | Reason |
|---------|---------|--------|

### Risks
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|

### Complexity Estimate
**[LOW / MEDIUM / HIGH]** — [brief justification]

### Acceptance Criteria Traceability
| AC | Covered By |
|----|-----------|
| AC-001 | Phase 2, src/services/... |
| AC-002 | Phase 3, API endpoint |

---
⏸ **Awaiting human approval before development begins.**
Tag this issue with `pipeline:approved` to proceed.
EOF
)"
```

## Step 3: Set Awaiting Approval Status
```bash
# Update project board
gh project item-edit \
  --id $PROJECT_ITEM_ID \
  --field-id $STATUS_FIELD_ID \
  --project-id $PROJECT_NODE_ID \
  --single-select-option-id $AWAITING_APPROVAL_OPTION_ID

# Tag the issue author so they know approval is needed
gh issue comment $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --body "@{ISSUE_AUTHOR} @{TECH_LEAD} — The development plan above is ready for your review. Add the label **\`pipeline:approved\`** to this issue to start development, or leave feedback as a comment."
```

## Rules
- Every file in the file list must map to at least one requirement
- Every acceptance criterion must have at least one file/phase covering it
- Flag any ACs that cannot be mapped — this is a planning failure
- The file list is the developer swarm's work queue — be specific and complete
- Do not include anything marked out-of-scope by the intake agent