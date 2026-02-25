# Pipeline Setup Guide

## Automated Setup (recommended)

Run the Setup Agent from inside your repository:

```bash
claude "/pipeline:setup"
```

The agent will:
1. Verify `gh` auth and required scopes
2. Auto-detect your repository from `git remote origin`
3. Find or create a GitHub Project
4. Create all required Status field options on the project board
5. Create all pipeline labels in your repository
6. Fetch all internal GitHub node IDs
7. Write a complete `.claude/config.sh` and gitignore it

**You will only be asked one question:** your GitHub username (used to tag you
at human approval checkpoints).

---

## Prerequisites

Before running setup, make sure you have:

```bash
# 1. GitHub CLI installed and authenticated
gh auth login

# 2. The 'project' OAuth scope (not included by default — required)
gh auth refresh -s project

# 3. Verify
gh auth status
# Must show 'project' in the token scopes
```

---

## What Gets Created

### `.claude/config.sh` (gitignored)

Written automatically by the setup agent. Contains all values needed to run
the pipeline — repo identity, project IDs, status field option IDs:

```bash
export GITHUB_ORG="your-org"
export GITHUB_REPO="your-org/your-repo"
export GITHUB_PROJECT_NUMBER=1
export GITHUB_PROJECT_OWNER="your-org"
export TECH_LEAD="your-github-handle"

export PROJECT_NODE_ID="PVT_..."
export STATUS_FIELD_ID="PVTSSF_..."

export READY_OPTION_ID="..."
export INTAKE_OPTION_ID="..."
# ... one per status
```

### GitHub Project Status field options

```
Backlog → Ready → Intake → Legal Review → Architecture → Solution Design
→ Awaiting Approval → In Development → QA Review → Code Review
→ Security Review → Ready for Merge → Done
```

### GitHub labels

| Label | Purpose |
|-------|---------|
| `pipeline:ready` | Triggers the pipeline |
| `pipeline:blocked` | Agent is waiting for human input |
| `pipeline:approved` | Human approves development to start |
| `pipeline:done` | Pipeline complete, PR created |

---

## Re-running Setup

Setup is idempotent — safe to run again. Existing resources (labels, field
options) are skipped. You will be asked to confirm before overwriting an
existing `config.sh`.

---

## Manual Reference

If you prefer to set things up manually, the values you need are:

```bash
# Get field ID and all option IDs for the Status field:
source .claude/config.sh
gh project field-list $GITHUB_PROJECT_NUMBER \
  --owner $GITHUB_PROJECT_OWNER \
  --format json \
  | jq '.fields[] | select(.name == "Status") | {fieldId: .id, projectId: .project.id, options: .options}'
```

Paste the output IDs into `.claude/config.sh` manually.
