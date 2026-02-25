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
The Git Watcher Agent polls the GitHub Project for issues with status `Ready`.
When found, it triggers the full pipeline. Every agent communicates exclusively
through GitHub Issue comments and labels — no local state files.

```
[GIT WATCHER] detects issue with status "Ready"
      ↓
[INTAKE AGENT]       → posts comment, sets status: Intake
      ↓
[EU COMPLIANCE AGENT] → posts legal memo, creates branch, sets status: Architecture
      ↓
[ARCHITECT]     → posts comment, sets status: Solution Design
      ↓
[SOLUTION DESIGN] → posts comment, sets status: Awaiting Approval
      ↓
⏸ HUMAN APPROVAL  ← adds label `pipeline:approved` to continue
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
`Solution Design` | `Awaiting Approval` | `In Development` | `QA Review` |
`Code Review` | `Security Review` | `Ready for Merge` | `Done`

## GitHub Labels — Required Labels in Repo
Create these labels in the repo:
- `pipeline:ready`      — human adds to trigger pipeline
- `pipeline:blocked`    — agent sets when stuck
- `pipeline:approved`   — human adds to approve development
- `pipeline:done`       — pipeline complete

## Agent Rules (modular)
Each agent has its own rules file:
- `.claude/rules/git-watcher.md`       ← entry point, polls GitHub Project
- `.claude/rules/intake.md`
- `.claude/rules/eu-compliance.md`    ← EU regulatory review (replaces legal.md)
- `.claude/rules/architect.md`
- `.claude/rules/solution-design.md`
- `.claude/rules/qa.md`
- `.claude/rules/developer.md`
- `.claude/rules/code-quality.md`
- `.claude/rules/security.md`
- `.claude/rules/git-agent.md`         ← final commit + PR

## Universal Rules (all agents)
- Source config: `source .claude/config.sh` before any `gh` command
- Read ALL existing issue comments before posting yours
- Post output as a structured comment (see each agent's template)
- Update the issue's Project status field after posting
- Never post duplicate comments — check if your section already exists
- If blocked: add label `pipeline:blocked`, post a BLOCKED comment explaining why
- Use `gh issue comment $ISSUE_NUMBER --body "..."` for all communication

## Human-in-the-Loop Checkpoints
1. **Intake clarifications** — Intake agent posts questions as a comment,
   tags the issue author with `@username`, waits. Pipeline resumes when
   the author replies (watcher detects the reply).
2. **Development approval** — After Solution Design, status is set to
   `Awaiting Approval`. Pipeline resumes ONLY when a human adds the
   label `pipeline:approved` to the issue.

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