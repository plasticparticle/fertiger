Run only the Intake Agent on an issue.

The issue number is provided as $ARGUMENTS.

Before executing, read `.claude/rules/intake.md` in full.

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Follow all steps in the intake rules: read the issue, ask clarifying questions
if needed, post the requirements comment, and update the project status.
