# Pipeline Slash Commands

## /pipeline:watch
Start the Git Watcher Agent. Polls the GitHub Project every 5 minutes for
issues with status "Ready" or label "pipeline:ready". Processes each one
found through the full pipeline.
Stops after 8 hours of no new issues.

## /pipeline:start [issue-number]
Manually trigger the full pipeline for a specific GitHub Issue number.
Example: `/pipeline:start 42`

## /pipeline:resume [issue-number]
Resume a pipeline after human approval (pipeline:approved label has been added).
Runs: QA Test Writing → Dev Swarm → QA Validation → Code Quality → Security → Git PR.
Example: `/pipeline:resume 42`

## /pipeline:status [issue-number]
Read all agent comments on the issue and print a one-line status summary of
each pipeline stage.
Example: `/pipeline:status 42`

## /pipeline:retry-dev [issue-number]
Manually trigger a dev swarm retry after a QA failure, without re-running
earlier pipeline stages.

## /agent:intake [issue-number]
Run only the Intake Agent on an issue.

## /agent:legal [issue-number]
Run only the Legal Agent on an issue.

## /agent:security [issue-number]
Run only the Security Agent on an issue (useful for spot-checks on existing code).

## /agent:qa-validate [issue-number]
Run only the QA Validation mode on an issue (after dev is complete).

## /pipeline:report
List all open issues in the GitHub Project and their current pipeline status.
Shows: issue number, title, current stage, blocked/active state.

## /pipeline:setup
Run the Setup Agent. Fully automated first-time configuration:
- Auto-detects the GitHub repository from the git remote (no manual input)
- Finds or creates a GitHub Project for the repo
- Creates all required Status field options on the project board
- Creates all pipeline labels in the repository
- Fetches all node IDs needed for `gh project item-edit`
- Writes a complete `.claude/config.sh` and adds it to `.gitignore`

The only thing you will be asked: your GitHub username (for tagging at approvals).

Run this once per repository before using any other pipeline command.