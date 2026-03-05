Show a live dashboard of all active pipeline issues: what stage each is in,
which agent is currently responsible, and whether anything is blocked.

Usage: `/pipeline:report` — no arguments needed.
       `/pipeline:report --all` — include Done and Backlog items too.

---

## Step 1: Fetch Project Data

The `gh project item-list` output can be large (multi-KB JSON). Save to a temp
file before piping to jq to avoid silent truncation:

```bash
source .claude/config.sh

# Save project items to temp file, then parse
gh project item-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --format json \
  --limit 100 > /tmp/pipeline-items.json

jq '[.items[] | select(.content.number) | {
    number: .content.number,
    title: .title,
    status: (.status // "No Status")
  }] | sort_by(.number)' /tmp/pipeline-items.json
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
| Blocked           | 🚫 Blocked — human intervention needed    |
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
  35🚫│ Export feature                 │ Blocked             │ 🚫 Blocked — human intervention needed

🚫 = status is Blocked on the project board

──────────────────────────────────────────────────────────
  Active: 2   Awaiting human: 1   Blocked: 1   Total: 3
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For details on a specific issue: /pipeline:status <number>
```

**Formatting rules:**
- Truncate titles to 30 characters (add `…` if cut)
- Append 🚫 immediately after the issue number (no space) if that issue has status `Blocked`
- Append `— BLOCKED` after the agent name for blocked issues
- By default, **exclude** issues with status `Done` or `Backlog` from the table
  (if `--all` was passed as $ARGUMENTS, include everything)
- Sort rows by issue number ascending
- If there are no active issues, print: `  No active pipeline issues.`

**Summary line counts:**
- **Active**: issues currently being processed by an agent (any status except
  Done, Backlog, Awaiting Approval, Ready)
- **Awaiting human**: issues with status `Awaiting Approval`
- **Blocked**: issues with status `Blocked`
- **Total**: all issues shown in the table

## Step 3: Show Run History (last 10 completed runs)

After the live dashboard, print a historical summary of the last 10 pipeline
runs using the structured log files written by `log.sh` (issue #15).

```bash
source .claude/config.sh

# Check whether the pipeline-logs directory has any data yet
if [ -d ".pipeline-logs" ] && find ".pipeline-logs" -name "*.jsonl" -quit 2>/dev/null; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Recent Run History"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bash scripts/pipeline/metrics.sh --history
else
  echo ""
  echo "  (No structured run history yet — runs will appear here once the pipeline"
  echo "   has executed with the observability update from issue #15.)"
fi
```

The metrics command reads `.pipeline-logs/` and prints each run with its
run ID, issue number, outcome (✅ PASS / ❌ FAIL), and total duration.
For per-agent timing of a specific run: `scripts/pipeline/metrics.sh N RUN_ID`.
