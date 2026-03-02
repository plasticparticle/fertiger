Show full pipeline status for a single issue: current stage, which agent is
active, what each previous agent found, and whether anything is blocked.

Usage: `/pipeline:status 42`

The issue number is provided as $ARGUMENTS.

---

## Step 1: Fetch Issue Data

```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS

# Full issue + all comments
gh issue view $ISSUE_NUMBER \
  --repo $GITHUB_REPO \
  --comments \
  --json comments,labels,title,body,number

# Current project board status
gh project item-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --format json \
  --limit 100 \
  | jq --argjson n $ISSUE_NUMBER \
      '.items[] | select(.content.number == $n) | .status'
```

## Step 2: Extract Per-Agent Results

Scan comments for `<!-- pipeline-agent:X -->` markers. For each agent found,
extract the verdict line (PASS / FAIL / BLOCKED / COMPLIANT / CONDITIONAL).

Agent markers to look for (in pipeline order):
- `pipeline-agent:intake`
- `pipeline-agent:eu-compliance`
- `pipeline-agent:dpo-escalation`
- `pipeline-agent:architect`
- `pipeline-agent:solution-design`
- `pipeline-agent:qa-tests`
- `pipeline-agent:dev-` (any dev agent)
- `pipeline-agent:dev-complete`
- `pipeline-agent:qa-validation`
- `pipeline-agent:code-quality`
- `pipeline-agent:security`
- `pipeline-agent:git-complete`

## Step 3: Print the Status Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Pipeline Status — Issue #{number}: {title}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current stage:    {project board status}
Active agent:     {agent name from status mapping below}
Blocked:          YES 🚫 / NO

Pipeline progress:
  ✅ Intake             — [one-line summary or "not yet run"]
  ✅ EU Compliance      — COMPLIANT / CONDITIONAL / BLOCKED / not yet run
  ✅ Architecture       — [one-line summary]
  ✅ Solution Design    — [one-line summary]
  ✅ QA Tests           — [N tests written]
  ✅ Developer Swarm    — [N agents, PASS/FAIL]
  ✅ QA Validation      — PASSED / FAILED (attempt N/3)
  ✅ Code Quality       — PASS / FAIL
  ✅ Security           — PASS / CONDITIONAL / BLOCKED
  ⏳ Git Agent          — not yet run
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Use ✅ for completed stages, ⏳ for the current/pending stage, and — for not-yet-reached stages.

**Status → Active Agent mapping:**
| Status            | Active Agent                  |
|-------------------|-------------------------------|
| Ready             | 👁️  Watcher — queued         |
| Intake            | 📋 Intake Agent               |
| Legal Review      | ⚖️  EU Compliance Agent       |
| Architecture      | 🏗️  Architect Agent           |
| Solution Design   | 📐 Solution Design Agent      |
| Awaiting Approval | ⏸  Human approval needed      |
| In Development    | 💻 Developer Swarm            |
| QA Review         | 🔍 QA Validation Agent        |
| Code Review       | 🔬 Code Quality Agent         |
| Security Review   | 🔒 Security Agent             |
| Ready for Merge   | 🚀 Git Agent                  |
| Done              | ✅ Complete — see PR link     |

For complete details on a specific agent's output, read its comment on the issue directly.
