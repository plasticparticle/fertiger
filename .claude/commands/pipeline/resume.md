Resume a pipeline after human approval (pipeline:approved label has been added).
Runs: QA Test Writing → Dev Swarm → QA Validation → Code Quality → Security → Git PR.
Example: `/pipeline:resume 42`

The issue number is provided as $ARGUMENTS.

Before executing, read the following rules files in order:
1. `.claude/rules/qa.md`
2. `.claude/rules/developer.md`
3. `.claude/rules/code-quality.md`
4. `.claude/rules/security.md`
5. `.claude/rules/git-agent.md`

Then run:
```bash
source .claude/config.sh
ISSUE_NUMBER=$ARGUMENTS
```

Verify the issue has the `pipeline:approved` label before proceeding. Read all
existing issue comments to understand the current pipeline state, then continue
from the QA Test Writing stage.
