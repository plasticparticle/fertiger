Run only the QA Validation mode on an issue (after dev is complete).

The issue number is provided as $ARGUMENTS.

Before executing, read `.claude/rules/qa.md` in full. Use Mode 2: Validator.

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Follow the Mode 2 Validator steps: checkout the feature branch, run all tests,
check acceptance criteria, and post the validation result. If tests fail and the
retry count is below 3, return the issue to `In Development`; otherwise escalate.
