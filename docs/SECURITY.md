# Security Posture

> Maintained by the Security Agent. Updated automatically when each feature branch is merged.
> Do not edit manually — changes will be overwritten on the next pipeline run.

---

## Auth & Authorisation Patterns

_How authentication and authorisation work in this codebase._

All pipeline agents authenticate exclusively through the GitHub CLI (`gh`), which is
pre-authenticated via the user's local gh session. No new auth flows are introduced
by any pipeline agent. Agents do not store, log, or transmit credentials.

---

## Established Security Patterns

_Patterns all developers must follow, extracted from past security reviews._

- All bash commands in agent rules files use environment variables from `config.sh`; no hardcoded values
- Agent rules files must never contain secrets, API keys, or credentials
- `config.sh` is gitignored and must never be committed
- All `gh` commands use `--repo $GITHUB_REPO` to scope operations to the correct repository

---

## Known Risk Areas

_Areas of the codebase that warrant extra scrutiny on future changes._

| Area | Risk | Mitigation in Place | Last Reviewed |
|------|------|---------------------|---------------|
| Agent rules bash commands | Variable injection if $ISSUE_NUMBER contained special chars | gh CLI sanitises arguments; issue numbers are numeric only | 2026-02-26 |
| COMPLIANCE.md register | Append-only; risk of sensitive data if issue body contains PII | COMPLIANCE.md records software feature decisions, not personal data | 2026-02-26 |

---

## Security Audit Log

_One row per issue processed. Most recent first._

| Issue | Feature | Result | Critical | High | Medium | Low | Date |
|-------|---------|--------|----------|------|--------|-----|------|
| #1 | EU Compliance Agent — Requirements | PASS | 0 | 0 | 0 | 0 | 2026-02-26 |
