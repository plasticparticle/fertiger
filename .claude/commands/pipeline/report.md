Show a live dashboard of all active pipeline issues: what stage each is in,
which agent is currently responsible, and whether anything is blocked.

Usage: `/pipeline:report` — no arguments needed.
       `/pipeline:report --all` — include Done and Backlog items too.

---

## Step 1: Fetch Project Data

```bash
source .claude/config.sh

# All project items with their status
gh project item-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --format json \
  --limit 100 \
  | jq '[.items[] | select(.content.number) | {
      number: .content.number,
      title: .title,
      status: (.status // "No Status")
    }] | sort_by(.number)'

# Issues currently blocked
gh issue list \
  --repo $GITHUB_REPO \
  --label "pipeline:blocked" \
  --json number \
  --state open \
  | jq '[.[].number]'
```

## Step 2: Determine Active Agent

Map each issue's **Status** field to the agent currently responsible:

| Status            | Active Agent                              |
|-------------------|-------------------------------------------|
| Ready             | 👁️  Watcher — queued, not yet picked up  |
| Intake            | 📋 Intake Agent                           |
| Legal Review      | ⚖️  EU Compliance Agent                  |
| Architecture      | 🏗️  Architect Agent                      |
| Solution Design   | 📐 Solution Design Agent                  |
| Awaiting Approval | ⏸  Human approval needed                 |
| In Development    | 💻 Developer Swarm                        |
| QA Review         | 🔍 QA Validation Agent                   |
| Code Review       | 🔬 Code Quality Agent                    |
| Security Review   | 🔒 Security Agent                         |
| Ready for Merge   | 🚀 Git Agent                              |
| Done              | ✅ Complete                               |
| Backlog           | —  Not started                            |

## Step 3: Print the Dashboard

Print this exact format, substituting real values:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔎  Pipeline Dashboard — {GITHUB_REPO}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  #   │ Title                          │ Stage               │ Who's working on it
──────┼────────────────────────────────┼─────────────────────┼────────────────────────────
  42  │ Add user authentication        │ Security Review     │ 🔒 Security Agent
  38  │ Payment integration flow       │ Awaiting Approval   │ ⏸  Human approval needed
  35🚫│ Export feature                 │ In Development      │ 💻 Developer Swarm — BLOCKED

🚫 = pipeline:blocked label is set on this issue

──────────────────────────────────────────────────────────
  Active: 2   Awaiting human: 1   Blocked: 1   Total: 3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For details on a specific issue: /pipeline:status <number>
```

**Formatting rules:**
- Truncate titles to 30 characters (add `…` if cut)
- Append 🚫 immediately after the issue number (no space) if that issue has `pipeline:blocked`
- Append `— BLOCKED` after the agent name for blocked issues
- By default, **exclude** issues with status `Done` or `Backlog` from the table
  (if `--all` was passed as $ARGUMENTS, include everything)
- Sort rows by issue number ascending
- If there are no active issues, print: `  No active pipeline issues.`

**Summary line counts:**
- **Active**: issues currently being processed by an agent (any status except
  Done, Backlog, Awaiting Approval, Ready)
- **Awaiting human**: issues with status `Awaiting Approval` or label `pipeline:blocked`
  but NOT actively blocked (i.e. at a human checkpoint)
- **Blocked**: issues with `pipeline:blocked` label set
- **Total**: all issues shown in the table
