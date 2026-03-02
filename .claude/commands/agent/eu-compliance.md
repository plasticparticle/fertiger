Run only the EU Compliance Agent on an issue (useful for spot-checks or re-running compliance review).

The issue number is provided as $ARGUMENTS.

Before executing, read `.claude/rules/eu-compliance.md` in full.

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Follow all steps in the eu-compliance rules: read the intake comment, run the full
regulatory triage, post the compliance memo, update `$PIPELINE_DOCS_DIR/COMPLIANCE.md`,
create the feature branch if compliant, and update the project status.
