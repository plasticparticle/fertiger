Run the Setup Agent. Fully automated first-time configuration:
- Auto-detects the GitHub repository from the git remote (no manual input)
- Finds or creates a GitHub Project for the repo
- Creates all required Status field options on the project board
- Creates all pipeline labels in the repository
- Fetches all node IDs needed for `gh project item-edit`
- Writes a complete `.claude/config.sh` and adds it to `.gitignore`

The only thing you will be asked: your GitHub username (for tagging at approvals).

Run this once per repository before using any other pipeline command.

Before executing, read `.claude/rules/setup.md` in full, then follow all steps
defined there from start to finish.
