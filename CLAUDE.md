# Feature Development Pipeline — GitHub Native

## Project Configuration
<!-- SET THESE FOR YOUR PROJECT -->
```
GITHUB_ORG=your-org
GITHUB_REPO=your-org/your-repo
GITHUB_PROJECT_NUMBER=1          # number from https://github.com/orgs/your-org/projects/1
GITHUB_PROJECT_OWNER=your-org
```

Store these in `.claude/config.sh` (gitignored):
```bash
export GITHUB_ORG="your-org"
export GITHUB_REPO="your-org/your-repo"
export GITHUB_PROJECT_NUMBER=1
export GITHUB_PROJECT_OWNER="your-org"
```

## Tech Stack
<!-- ADAPT TO YOUR PROJECT -->
- Runtime: Node.js / TypeScript
- Framework: [your framework]
- Testing: [your test framework]
- Cloud: Azure
- Auth: Okta

## Key Commands
```bash
npm run test            # unit tests
npm run test:coverage   # with coverage
npm run lint            # ESLint
npm run build           # compile
```

## Pipeline Overview
The Git Watcher Agent monitors the GitHub Project for issues with status `Ready`.
It uses webhook mode by default (event-driven via `gh webhook forward`, fires within
seconds) and falls back to polling (60-second interval) when prerequisites are absent.
When a ready issue is found, it triggers the full pipeline. Every agent communicates
exclusively through GitHub Issue comments and labels — no local state files.

```
[GIT WATCHER] detects issue with status "Ready"
      ↓
[INTAKE AGENT]       → posts comment, sets status: Intake
      ↓
[ESTIMATOR AGENT]    → posts business value + complexity assessment, sets status: Legal Review
      ↓
[EU COMPLIANCE AGENT] → posts legal memo, creates branch, sets status: Architecture
      ↓
[ARCHITECT]     → posts comment, sets status: Solution Design
      ↓
[SOLUTION DESIGN] → posts comment, sets status: Awaiting Approval
      ↓
⏸ HUMAN APPROVAL  ← sets status to `Approved` on project board to continue
      ↓
[QA AGENT]      → writes tests, sets status: In Development
      ↓
[DEV SWARM]     → builds code, sets status: QA Review
      ↓
[QA VALIDATION] → validates ↺ loops to Dev on failure (max 3x)
      ↓
[CODE QUALITY]  → gates, sets status: Security Review
      ↓
[SECURITY]      → audit, sets status: Ready for Merge
      ↓
[GIT AGENT]     → commit + PR, sets status: Done
```

## GitHub Project Board — Required Status Field Values
Configure these as options in your GitHub Project's "Status" field:
`Backlog` | `Ready` | `Intake` | `Legal Review` | `Architecture` |
`Solution Design` | `Awaiting Approval` | `Approved` | `In Development` | `QA Review` |
`Code Review` | `Security Review` | `Ready for Merge` | `Blocked` | `Done`

## GitHub Labels — Required Labels in Repo
Create these labels in the repo:
- `compliance:drift`    — created automatically by `/agent:compliance-audit` when drift is found

## Agent Rules (modular)
Each agent has its own rules file:
- `.claude/rules/git-watcher.md`       ← entry point, polls GitHub Project
- `.claude/rules/intake.md`
- `.claude/rules/estimator.md`        ← business value, customer impact & complexity
- `.claude/rules/eu-compliance.md`    ← EU regulatory review (replaces legal.md)
- `.claude/rules/architect.md`
- `.claude/rules/solution-design.md`
- `.claude/rules/qa.md`
- `.claude/rules/developer.md`
- `.claude/rules/code-quality.md`
- `.claude/rules/security.md`
- `.claude/rules/git-agent.md`         ← final commit + PR
- `.claude/rules/compliance-audit.md`  ← periodic drift check, run via `/agent:compliance-audit`

## Pipeline Script Library
Reusable scripts live in `scripts/pipeline/`. Full docs: `scripts/pipeline/SCRIPTS.md`.
- **Before writing a bash block**, check the registry — the script may already exist
- **After writing a reusable script**, add it to `scripts/pipeline/SCRIPTS.md` and commit both together
- Key scripts: `set-status.sh STATUS_NAME` · `get-agent-comment.sh AGENT` · `checkout-branch.sh`
- Agents may create new scripts in `scripts/pipeline/` and register them at runtime

## Universal Rules (all agents)
- Source config: `source .claude/config.sh` before any `gh` command
- `ISSUE_NUMBER` is NOT in config.sh — always set it manually: `export ISSUE_NUMBER=N`
- Read ALL existing issue comments before posting yours
- Post output as a structured comment (see each agent's template)
- Update the issue's Project status field after posting — use `scripts/pipeline/set-status.sh`
- Never post duplicate comments — check if your section already exists
- If blocked: set status to `Blocked` with `scripts/pipeline/set-status.sh BLOCKED`, post a BLOCKED comment explaining why
- Use `gh issue comment $ISSUE_NUMBER --body "..."` for all communication
- **jq + HTML comments:** Never use `contains("<!--")` in jq — the `!` causes a `\!` escape error. Use `test("pipeline-agent:")` instead:
  ```bash
  jq '[.comments[].body | test("pipeline-agent:")] | any'
  ```

## Human-in-the-Loop Checkpoints
1. **Intake clarifications** — Intake agent posts questions as a comment,
   tags the issue author with `@username`, waits. Pipeline resumes when
   the author replies (watcher detects the reply).
2. **Development approval** — After Solution Design, status is set to
   `Awaiting Approval`. Pipeline resumes when a human changes the status
   to **`Approved`** on the project board.

## Settings
```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Bash(gh *)",
      "Bash(git *)",
      "Bash(npm run *)",
      "Edit(/src/**)",
      "Edit(/tests/**)"
    ],
    "deny": [
      "Bash(git push --force)",
      "Bash(gh auth *)"
    ]
  }
}
```