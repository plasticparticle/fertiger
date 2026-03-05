> **fertiger self-documentation** — This file tracks the fertiger pipeline framework's
> own audit history. It is NOT a template. Consumer projects write to `docs/` instead.

---

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
- All `gh issue comment` heartbeat calls use `|| true` fire-and-forget to prevent pipeline failures from exposing internal state via error messages
- jq patterns in agent rules must use `test()` not `contains()` to avoid bash `!` escape issues
- log.sh JSON escaping uses sed for basic backslash/quote escaping — acceptable for pipeline-authored messages; do not pass user-supplied content as the message argument

---

## Known Risk Areas

_Areas of the codebase that warrant extra scrutiny on future changes._

| Area | Risk | Mitigation in Place | Last Reviewed |
|------|------|---------------------|---------------|
| Agent rules bash commands | Variable injection if $ISSUE_NUMBER contained special chars | gh CLI sanitises arguments; issue numbers are numeric only | 2026-02-26 |
| COMPLIANCE.md register | Append-only; risk of sensitive data if issue body contains PII | COMPLIANCE.md records software feature decisions, not personal data | 2026-02-26 |
| triage.sh keyword matching | Issue body content passed to grep; risk if body contains shell metacharacters | Content quoted via echo "$VAR" before pipe to grep; no eval used | 2026-02-26 |

---

## Security Audit Log

_One row per issue processed. Most recent first._

| Issue | Feature | Result | Critical | High | Medium | Low | Date |
|-------|---------|--------|----------|------|--------|-----|------|
| #15 | Structured Observability — log.sh JSON + metrics.sh | CONDITIONAL | 0 | 0 | 1 | 0 | 2026-03-05 |
| #7 | Pipeline Agents — Post Started Heartbeat Comment | PASS | 0 | 0 | 0 | 0 | 2026-03-02 |
| #5 | New Agent — Business Value, Customer Impact & Complexity Estimator | PASS | 0 | 0 | 0 | 0 | 2026-03-02 |
| #4 | Pipeline Agents — Pre-Research Triage | PASS | 0 | 0 | 0 | 0 | 2026-02-26 |
| #1 | EU Compliance Agent — Requirements | PASS | 0 | 0 | 0 | 0 | 2026-02-26 |
