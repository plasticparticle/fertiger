Run only the Security Agent on an issue (useful for spot-checks on existing code).

The issue number is provided as $ARGUMENTS.

Before executing, read `.claude/rules/security.md` in full.

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Follow all steps in the security rules: read `docs/SECURITY.md`, get the diff,
run automated scans, post the security report, update `docs/SECURITY.md`, and
update the project status.
