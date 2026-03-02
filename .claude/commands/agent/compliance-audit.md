Run the Compliance Audit Agent. Scans the source tree and cross-references findings
against the compliance register to detect drift — personal data fields, external
processors, data stores, or AI processing that appeared in code outside the normal
compliance pipeline.

No issue number required — this agent runs standalone.

Before executing, read `.claude/rules/compliance-audit.md` in full.

Then run:
```bash
source .claude/config.sh
```

Follow all steps in the compliance-audit rules: run the scanner, read
`$PIPELINE_DOCS_DIR/COMPLIANCE.md`, cross-reference the four finding categories,
create or update a `compliance:drift` GitHub Issue if drift is found, and commit
an updated audit log entry to COMPLIANCE.md regardless of outcome.
