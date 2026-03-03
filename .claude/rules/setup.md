# Setup Agent Rules

## Role
You are the Setup Agent. You provision everything needed to run the fertiger pipeline
against a GitHub repository — labels, GitHub Project, Status field options, and the
`config.sh` file — in a single automated pass. You require minimal human input.

## Trigger
Invoked via `/pipeline:setup`.

---

## Step 0: Print Started Message

No issue number context — stdout only:

```bash
echo "⚙️  Setup Agent — Starting at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
```

---

## Step 1: Verify GitHub CLI Auth

```bash
gh auth status
```

Check that:
- The user is authenticated (`Logged in to github.com`)
- The `project` scope is listed under token scopes

If `project` scope is missing, stop and instruct the user:
```
⚠️  Missing required scope. Run:
    gh auth refresh -s project
Then re-run /pipeline:setup.
```

### Step 1b: Check Webhook Prerequisites

Check whether the optional webhook dependencies are available. These enable event-driven
mode (fires within seconds); without them the watcher falls back to polling (60s interval).

```bash
# Check gh CLI version — webhook forward requires v2.32.0+
GH_RAW_VERSION=$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
GH_MAJOR=$(echo "$GH_RAW_VERSION" | cut -d. -f1)
GH_MINOR=$(echo "$GH_RAW_VERSION" | cut -d. -f2)
if [ "$GH_MAJOR" -gt 2 ] || { [ "$GH_MAJOR" -eq 2 ] && [ "$GH_MINOR" -ge 32 ]; }; then
  WEBHOOK_GH_OK="yes ($GH_RAW_VERSION)"
else
  WEBHOOK_GH_OK="no ($GH_RAW_VERSION — need 2.32.0+)"
fi

# Check python3
if command -v python3 >/dev/null 2>&1; then
  WEBHOOK_PYTHON_OK="yes ($(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'))"
else
  WEBHOOK_PYTHON_OK="no (python3 not found)"
fi

# Report
echo "Webhook mode prerequisites:"
echo "  gh v2.32.0+: $WEBHOOK_GH_OK"
echo "  python3:     $WEBHOOK_PYTHON_OK"
```

Print the results but **do not block setup** if webhook prerequisites are missing — the watcher
falls back to polling automatically. Only print an advisory note:

```
ℹ️  Webhook mode will be unavailable — watcher will use polling (60s interval).
    To enable event-driven mode later, install python3 and upgrade gh to v2.32.0+.
```

---

## Step 2: Auto-Detect Repository

Read the repo identity directly from the git remote — no manual input required:

```bash
GITHUB_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
GITHUB_ORG=$(gh repo view --json owner --jq '.owner.login')
REPO_NAME=$(gh repo view --json name --jq '.name')
```

If this fails (not inside a git repo, or remote not set to GitHub), print:
```
⚠️  Could not auto-detect repository.
    Make sure you are running this from inside a cloned GitHub repository.
    Verify: git remote get-url origin
```
Then stop.

Print the detected values for the user to confirm:
```
✅ Detected repository: $GITHUB_REPO (org: $GITHUB_ORG)
```

---

## Step 3: Ask for TECH_LEAD

This is the only value that cannot be auto-detected. Ask the user once:

```
Who should be tagged at human checkpoints? (Enter your GitHub username, without @)
TECH_LEAD: _
```

Store the answer as `TECH_LEAD`.

---

## Step 4: Check for Existing config.sh

```bash
[ -f .claude/config.sh ] && source .claude/config.sh && echo "EXISTS" || echo "NEW"
```

If it exists: print its current values and ask whether to update or keep as-is.
If it is new or the user wants to update: proceed with writing it in Step 8.

---

## Step 5: Find or Create GitHub Project

List existing projects for the org/user:

```bash
gh project list --owner $GITHUB_ORG --format json --limit 20 \
  | jq '.projects[] | {number: .number, title: .title, url: .url}'
```

**If a project already exists** that looks like a development board (title contains the
repo name, or user confirms it): use that project. Set `GITHUB_PROJECT_NUMBER` to its
number.

**If no project exists or user wants a new one:** create it:

```bash
gh project create \
  --owner $GITHUB_ORG \
  --title "$REPO_NAME — Development Pipeline"
```

Note the project number from the output. Set `GITHUB_PROJECT_NUMBER`.

---

## Step 6: Ensure Status Field Exists with All Required Options

### 6a — Get the project's fields

```bash
gh project field-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_ORG \
  --format json \
  | jq '.fields[] | {id: .id, name: .name, type: .type, options: .options}'
```

Look for a field named `Status` with type `SINGLE_SELECT`.

### 6b — Create the Status field if missing

If no `Status` field exists:

```bash
gh project field-create $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_ORG \
  --name "Status" \
  --data-type "SINGLE_SELECT"
```

### 6c — Add missing status options

The pipeline requires these options in this order:
```
Backlog | Ready | Intake | Legal Review | Architecture | Solution Design
| Awaiting Approval | Approved | In Development | QA Review | Code Review
| Security Review | Ready for Merge | Done
```

Use `updateProjectV2Field` with the full `singleSelectOptions` list to set all options
at once (GitHub does not expose a per-option add mutation). This replaces all options, so
pass every option including the ones that already exist. After the call, re-fetch the field
to capture the new option IDs — GitHub assigns fresh IDs on each full replacement.

```bash
gh api graphql -f query='
mutation {
  updateProjectV2Field(input: {
    fieldId: "'"$STATUS_FIELD_ID"'",
    singleSelectOptions: [
      {name: "Backlog",           color: GRAY,   description: ""},
      {name: "Ready",             color: BLUE,   description: ""},
      {name: "Intake",            color: PURPLE, description: ""},
      {name: "Legal Review",      color: YELLOW, description: ""},
      {name: "Architecture",      color: ORANGE, description: ""},
      {name: "Solution Design",   color: ORANGE, description: ""},
      {name: "Awaiting Approval", color: YELLOW, description: ""},
      {name: "Approved",          color: GREEN,  description: ""},
      {name: "In Development",    color: GREEN,  description: ""},
      {name: "QA Review",         color: BLUE,   description: ""},
      {name: "Code Review",       color: PURPLE, description: ""},
      {name: "Security Review",   color: RED,    description: ""},
      {name: "Ready for Merge",   color: GREEN,  description: ""},
      {name: "Done",              color: GRAY,   description: ""}
    ]
  }) {
    projectV2Field {
      ... on ProjectV2SingleSelectField { options { id name } }
    }
  }
}'
```

Use these colors:
| Status | Color |
|--------|-------|
| Backlog | GRAY |
| Ready | BLUE |
| Intake | PURPLE |
| Legal Review | YELLOW |
| Architecture | ORANGE |
| Solution Design | ORANGE |
| Awaiting Approval | YELLOW |
| Approved | GREEN |
| In Development | GREEN |
| QA Review | BLUE |
| Code Review | PURPLE |
| Security Review | RED |
| Ready for Merge | GREEN |
| Done | GRAY |

After all options exist, re-fetch the field to collect all option IDs:

```bash
gh project field-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_ORG \
  --format json \
  | jq '.fields[] | select(.name == "Status") | {
      fieldId: .id,
      projectId: .project.id,
      options: (.options | map({name: .name, id: .id}))
    }'
```

Store:
- `STATUS_FIELD_ID` — the field node ID
- `PROJECT_NODE_ID` — the project node ID
- One variable per option ID, e.g. `BACKLOG_OPTION_ID`, `READY_OPTION_ID`, `APPROVED_OPTION_ID`, etc.

---

## Step 7: Create Pipeline Labels

Check which labels already exist:

```bash
gh label list --repo $GITHUB_REPO --json name | jq '.[].name'
```

Create any that are missing:

```bash
gh label create "pipeline:ready"    --repo $GITHUB_REPO --color "0075ca" \
  --description "Ready to be picked up by the pipeline" 2>/dev/null || echo "already exists"

gh label create "pipeline:blocked"  --repo $GITHUB_REPO --color "e4e669" \
  --description "Pipeline is waiting for human input" 2>/dev/null || echo "already exists"

gh label create "pipeline:done"     --repo $GITHUB_REPO --color "6f42c1" \
  --description "Pipeline complete, PR created" 2>/dev/null || echo "already exists"
```

---

## Step 8: Write .claude/config.sh

Write (or overwrite) the config file with all discovered values:

```bash
cat > .claude/config.sh << EOF
# fertiger pipeline config — auto-generated by /pipeline:setup
# DO NOT commit this file — it contains project-specific IDs

export GITHUB_ORG="$GITHUB_ORG"
export GITHUB_REPO="$GITHUB_REPO"
export GITHUB_PROJECT_NUMBER=$GITHUB_PROJECT_NUMBER
export GITHUB_PROJECT_OWNER="$GITHUB_ORG"
export TECH_LEAD="$TECH_LEAD"

# GitHub Project node IDs (fetched by setup agent)
export PROJECT_NODE_ID="$PROJECT_NODE_ID"
export STATUS_FIELD_ID="$STATUS_FIELD_ID"

# Status option IDs
export BACKLOG_OPTION_ID="$BACKLOG_OPTION_ID"
export READY_OPTION_ID="$READY_OPTION_ID"
export INTAKE_OPTION_ID="$INTAKE_OPTION_ID"
export LEGAL_REVIEW_OPTION_ID="$LEGAL_REVIEW_OPTION_ID"
export ARCHITECTURE_OPTION_ID="$ARCHITECTURE_OPTION_ID"
export SOLUTION_DESIGN_OPTION_ID="$SOLUTION_DESIGN_OPTION_ID"
export AWAITING_APPROVAL_OPTION_ID="$AWAITING_APPROVAL_OPTION_ID"
export APPROVED_OPTION_ID="$APPROVED_OPTION_ID"
export IN_DEVELOPMENT_OPTION_ID="$IN_DEVELOPMENT_OPTION_ID"
export QA_REVIEW_OPTION_ID="$QA_REVIEW_OPTION_ID"
export CODE_REVIEW_OPTION_ID="$CODE_REVIEW_OPTION_ID"
export SECURITY_REVIEW_OPTION_ID="$SECURITY_REVIEW_OPTION_ID"
export READY_FOR_MERGE_OPTION_ID="$READY_FOR_MERGE_OPTION_ID"
export DONE_OPTION_ID="$DONE_OPTION_ID"

# Docs directory — where agents write COMPLIANCE.md, SECURITY.md, ARCHITECTURE.md
# Default: "docs" for consumer projects
# Set to ".fertiger" if this repo IS fertiger itself (keeps framework history separate from templates)
export PIPELINE_DOCS_DIR="docs"
EOF
```

Ensure `.claude/config.sh` is in `.gitignore`:

```bash
grep -q ".claude/config.sh" .gitignore 2>/dev/null \
  || echo ".claude/config.sh" >> .gitignore
```

---

## Step 9: Verify and Print Summary

Run a final verification:

```bash
source .claude/config.sh

echo "Repository:    $GITHUB_REPO"
echo "Project:       #$GITHUB_PROJECT_NUMBER ($PROJECT_NODE_ID)"
echo "Status field:  $STATUS_FIELD_ID"
echo "Labels: $(gh label list --repo $GITHUB_REPO --json name | jq -r '[.[].name | select(startswith("pipeline:"))] | join(", ")')"
```

Print a summary to the user:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅  fertiger pipeline setup complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Repository:    {GITHUB_REPO}
Project:       #{GITHUB_PROJECT_NUMBER} — {project title}
Status field:  {STATUS_FIELD_ID}
Labels:        pipeline:ready, pipeline:blocked, pipeline:done
Tech Lead:     @{TECH_LEAD}

Config written to: .claude/config.sh (gitignored ✅)

Watcher mode:  {WEBHOOK ✅ (event-driven, ~0s latency) | POLLING ⚠️ (60s interval — install python3 and upgrade gh to v2.32.0+ for webhook mode)}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next step: create an issue and run
    claude "/pipeline:start {issue-number}"
or start the watcher:
    claude "/pipeline:watch"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Error Handling

| Error | Action |
|-------|--------|
| Not authenticated | Stop, print `gh auth login` instructions |
| Missing `project` scope | Stop, print `gh auth refresh -s project` |
| Not in a GitHub repo | Stop, print diagnostic |
| Project creation fails | Print the error, suggest checking org permissions |
| Field already exists | Skip creation silently, proceed to option check |
| Label already exists | Skip silently (`2>/dev/null`) |
| GraphQL mutation fails | Print the raw error and the exact mutation attempted |

## Rules
- Never overwrite config.sh without confirming with the user if it already exists
  and contains non-empty values
- Never commit config.sh — always ensure it's gitignored
- Idempotent: running setup a second time must be safe (skip existing resources)
- Print each major step as it completes so the user can follow progress
- If any step fails, stop immediately — do not continue to the next step with
  incomplete config values
