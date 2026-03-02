# Pipeline Script Library

This file is the single source of truth for reusable pipeline shell scripts.

**Before writing an ad-hoc bash block, check here first.**
If a script already does what you need, use it.
If you write a new reusable script, add it below.

---

## How to add a script

1. Write the script to `scripts/pipeline/your-script.sh`
2. Make it executable: `chmod +x scripts/pipeline/your-script.sh`
3. Add an entry below in the correct category
4. Commit both the script and this file in the same commit

Entry format:
```
### script-name.sh
**Purpose:** One sentence.
**Usage:** `scripts/pipeline/script-name.sh ARG1 [ARG2]`
**Arguments:** list each arg
**Env required:** list env vars it reads (beyond .claude/config.sh)
**Used by:** list agent rule files
```

---

## Core Utilities

### set-status.sh
**Purpose:** Update the GitHub Project board status for the current issue.
**Usage:** `scripts/pipeline/set-status.sh STATUS_NAME`
**Arguments:**
- `STATUS_NAME` — one of: `INTAKE`, `LEGAL_REVIEW`, `ARCHITECTURE`, `SOLUTION_DESIGN`,
  `AWAITING_APPROVAL`, `IN_DEVELOPMENT`, `QA_REVIEW`, `CODE_REVIEW`,
  `SECURITY_REVIEW`, `READY_FOR_MERGE`, `DONE`
**Env required:** `ISSUE_NUMBER` (not in config.sh — must be set manually)
**Auto-fetches:** `PROJECT_ITEM_ID` if not already exported
**Used by:** All pipeline agents

---

### get-agent-comment.sh
**Purpose:** Fetch the body of the last GitHub Issue comment from a named pipeline agent.
**Usage:** `scripts/pipeline/get-agent-comment.sh AGENT_NAME [ISSUE_NUMBER]`
**Arguments:**
- `AGENT_NAME` — matches the `pipeline-agent:` marker used in comments, e.g.:
  `intake`, `eu-compliance`, `architect`, `solution-design`, `qa-tests`,
  `qa-validation`, `dev-complete`, `code-quality`, `security`, `git-complete`
- `ISSUE_NUMBER` — optional, falls back to `$ISSUE_NUMBER` env var
**Returns:** Full comment body on stdout. Exits 1 if no comment found.
**Used by:** Any agent that reads previous agent output

Example:
```bash
# Read the intake requirements comment
INTAKE=$(scripts/pipeline/get-agent-comment.sh intake)

# Read QA test contract
QA_CONTRACT=$(scripts/pipeline/get-agent-comment.sh qa-tests)
```

---

### checkout-branch.sh
**Purpose:** Fetch and checkout the feature branch for the current issue, with pull.
**Usage:** `BRANCH_NAME=$(scripts/pipeline/checkout-branch.sh [ISSUE_NUMBER])`
**Arguments:**
- `ISSUE_NUMBER` — optional, falls back to `$ISSUE_NUMBER` env var
**Behaviour:**
- If `BRANCH_NAME` is already exported, uses it directly
- Otherwise extracts it from the "Branch created:" comment on the issue
- Always runs: `git fetch origin && git checkout $BRANCH && git pull origin $BRANCH`
- Echoes the branch name to stdout
**Used by:** architect, qa, developer, code-quality, security, git-agent

Example:
```bash
BRANCH_NAME=$(scripts/pipeline/checkout-branch.sh)
```

---

## Stack Detection

### detect-stack.sh
**Purpose:** Detect project language, test runner, lint command, build command.
**Usage:** `source scripts/pipeline/detect-stack.sh`
**Sets variables:** `$STACK_LANGUAGE`, `$STACK_TEST_CMD`, `$STACK_LINT_CMD`,
  `$STACK_TYPECHECK_CMD`, `$STACK_BUILD_CMD`
**Used by:** developer

---

### triage.sh
**Purpose:** Determine analysis depth (TRIVIAL / STANDARD / COMPLEX) for an issue.
**Usage:** `TRIAGE_LEVEL=$(ISSUE_NUMBER=$ISSUE_NUMBER sh scripts/pipeline/triage.sh)`
**Returns:** `TRIVIAL`, `STANDARD`, or `COMPLEX` on stdout
**Used by:** eu-compliance, architect, solution-design, qa, code-quality, security

---

## Dev Swarm Utilities

### run-tests.sh
**Purpose:** Run the test suite, optionally filtered to a feature slug.
**Usage:** `scripts/pipeline/run-tests.sh [FEATURE_SLUG]`
**Arguments:**
- `FEATURE_SLUG` — optional filter (e.g. `user-auth`)
**Used by:** developer, qa

---

### check-deps.sh
**Purpose:** Check whether files imported by a given file exist on the current branch.
**Usage:** `scripts/pipeline/check-deps.sh FILE_PATH`
**Returns:** Lines of `OK: path` or `MISSING: path (reason)` on stdout
**Used by:** developer

---

### swarm-lock.sh
**Purpose:** Claim or release file ownership locks to prevent parallel agent conflicts.
**Usage:**
```bash
scripts/pipeline/swarm-lock.sh claim  AGENT_NAME "file1 file2"
scripts/pipeline/swarm-lock.sh check  FILE_PATH
scripts/pipeline/swarm-lock.sh release AGENT_NAME
```
**Used by:** developer

---

## Terminal Progress Logging

### log.sh
**Purpose:** Print a timestamped progress line to stdout (visible in the watch terminal)
and append it to the pipeline log file for tailing in a second terminal.
**Usage:** `scripts/pipeline/log.sh AGENT_NAME MESSAGE [LEVEL]`
**Arguments:**
- `AGENT_NAME` — free-text label, e.g. `"EU Compliance"`, `"Dev[alpha]"`
- `MESSAGE` — what is happening right now
- `LEVEL` — one of: `AGENT` (🤖 new agent starting), `STEP` (▸ sub-step),
  `PASS` (✅ success), `FAIL` (❌ failure), `BLOCK` (🚫 blocked), `INFO` (default)
**Env vars:**
- `PIPELINE_LOG_FILE` — log file path (default: `/tmp/pipeline.log`)
**Used by:** All pipeline agents — called at agent start, key milestones, and completion
**Companion skill:** `/pipeline:log` — tails the log file in a second terminal

Example output:
```
[10:42:15] 🤖 [Intake] Starting — Issue #7
[10:42:20]  ▸  [Intake] Writing requirements and acceptance criteria...
[10:43:01]  ✅ [Intake] Complete — requirements posted, handing off to EU Compliance
[10:43:03] 🤖 [EU Compliance] Starting — Issue #7
[10:43:05]  ▸  [EU Compliance] Triage: STANDARD
[10:43:06]  ▸  [EU Compliance] Running STANDARD regulatory triage across 16 regulations...
```

---

## Framework Update

### `/pipeline:update` (no script — uses git directly)
**Purpose:** Pull the latest fertiger framework files from upstream without touching
project-specific files (`docs/`, `.fertiger/`, `.claude/config.sh`, source code).
**Mechanism:** `git checkout fertiger/main -- .claude/rules/ .claude/commands/ scripts/pipeline/ .claude/scripts/ CLAUDE.md`
**Rules file:** `.claude/rules/pipeline-update.md`
**Used by:** Consumer projects upgrading to a newer version of the fertiger framework
