Run only the Legal Agent on an issue.

The issue number is provided as $ARGUMENTS.

Before executing, read `.claude/rules/legal.md` in full.

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Follow all steps in the legal rules: read the intake comment, run the compliance
check, post the legal comment, update `docs/COMPLIANCE.md`, create the feature
branch if compliant, and update the project status.
