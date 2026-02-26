# Architecture

> Maintained by the Architect Agent. Updated automatically when each feature branch is merged.
> Do not edit manually — changes will be overwritten on the next pipeline run.

---

## System Overview

fertiger is a GitHub-native feature development pipeline. It orchestrates a sequence of
AI agents that each read GitHub Issue comments as input and write structured comments as
output. Agents communicate exclusively through GitHub Issues and the GitHub Projects API —
there is no shared database, message queue, or persistent state beyond git and GitHub.

Each agent is implemented as a Claude Code rules file (`.claude/rules/*.md`) containing
step-by-step instructions and bash commands using the `gh` CLI. The pipeline is triggered
by the Git Watcher Agent polling the GitHub Project for issues with status "Ready".

---

## Component Map

| Component | Type | Responsibility | Key Files |
|-----------|------|----------------|-----------|
| Git Watcher | Agent (rules) | Polls GitHub Project; claims ready issues; hands off to Intake | `.claude/rules/git-watcher.md` |
| Intake Agent | Agent (rules) | Analyzes issue body; writes structured requirements + ACs | `.claude/rules/intake.md` |
| EU Compliance Agent | Agent (rules) | Deep EU regulatory review (GDPR, AI Act, NIS2, DSA, etc.); creates feature branch | `.claude/rules/eu-compliance.md` |
| Architect Agent | Agent (rules) | Explores codebase; produces ADRs and component decisions | `.claude/rules/architect.md` |
| Solution Design Agent | Agent (rules) | Produces file-by-file implementation plan; triggers human approval | `.claude/rules/solution-design.md` |
| QA Agent | Agent (rules) | Writes TDD tests before dev; validates after dev | `.claude/rules/qa.md` |
| Developer Agent | Agent (rules) | Implements code; runs as a swarm of parallel agents | `.claude/rules/developer.md` |
| Code Quality Agent | Agent (rules) | Enforces ESLint, TypeScript, naming, architecture compliance | `.claude/rules/code-quality.md` |
| Security Agent | Agent (rules) | OWASP + automated scans; updates docs/SECURITY.md | `.claude/rules/security.md` |
| Git Agent | Agent (rules) | Creates PR; links to issue; sets pipeline:done | `.claude/rules/git-agent.md` |
| Setup Agent | Agent (rules) | One-time provisioning of GitHub Project, labels, config.sh | `.claude/rules/setup.md` |
| Compliance Register | Document | Running log of GDPR/compliance decisions per feature | `docs/COMPLIANCE.md` |
| Security Register | Document | Running log of security audits and patterns per feature | `docs/SECURITY.md` |
| Pipeline Config | Shell script | GitHub Project node IDs, status option IDs, org/repo config | `.claude/config.sh` (gitignored) |
| Triage Script | Shell script | Classifies feature complexity as TRIVIAL/STANDARD/COMPLEX before agents start deep analysis | `scripts/pipeline/triage.sh` |

---

## Architecture Decision Records

_ADRs are appended here by the Architect Agent on each feature. Most recent first._

### ADR-007: Full-review label override centralised in triage.sh — Issue #4 (2026-02-26)
- **Context:** The `pipeline:full-review` label must force all agents to their full analysis path. The override could be checked in each agent's rules file separately, or once inside triage.sh.
- **Decision:** triage.sh checks for the `pipeline:full-review` label via `gh issue view` and outputs `COMPLEX` if the label is present, regardless of keyword/file-count analysis.
- **Rationale:** Centralising the override in triage.sh means a single change point. Agent rules files need no special-case label logic; they branch only on TRIAGE_LEVEL output.
- **Consequences:** triage.sh requires gh CLI access and ISSUE_NUMBER as an argument. When `pipeline:full-review` is present the output is `COMPLEX`.

### ADR-006: Triage gate inserted as Step 1 in each agent's rules file — Issue #4 (2026-02-26)
- **Context:** The triage gate must fire before any expensive codebase exploration, compliance checklist iteration, or test generation.
- **Decision:** Each of the six agent rules files gains a new Step 1 (triage gate) that calls triage.sh and branches on TRIAGE_LEVEL. Existing steps are renumbered.
- **Rationale:** Step 1 position guarantees the fast path exits before any further gh API calls. No expensive operations can run before the gate fires.
- **Consequences:** Six agent rules files have step numbering incremented by one. The triage declaration line must appear at the top of each agent's posted GitHub comment.

### ADR-005: Triage implemented as a standalone shared bash script — Issue #4 (2026-02-26)
- **Context:** Triage classification logic must be shared across six agent rules files. It could be embedded inline in each rules file or extracted to a single shared script.
- **Decision:** Implement triage as `scripts/pipeline/triage.sh`. Each agent's rules file calls this script rather than duplicating logic.
- **Rationale:** Single source of truth for classification thresholds. Consistent with the existing pattern: `.claude/scripts/poll-once.sh` and `.claude/scripts/watch.sh` are shared bash utilities invoked by rules files.
- **Consequences:** A new `scripts/pipeline/` directory is created. All six agent rules files invoke triage.sh at Step 1. Triage threshold changes require updating one file only.

### ADR-004: Replacement strategy for legal.md — Issue #1 (2026-02-26)
- **Context:** The EU Compliance Agent replaces the current Legal Agent. The old `.claude/rules/legal.md` file must be retired to prevent accidental invocation.
- **Decision:** Delete `.claude/rules/legal.md` and replace with `.claude/rules/eu-compliance.md`. Update `CLAUDE.md` and `.claude/rules/git-agent.md` to reference the new agent.
- **Rationale:** Keeping both files risks the watcher accidentally invoking the old agent. Clean removal with git history as audit trail is the safest approach.
- **Consequences:** Pipeline documentation must reference "EU Compliance Agent" rather than "Legal Agent" going forward.

### ADR-003: Structured compliance summary block for downstream agents — Issue #1 (2026-02-26)
- **Context:** The EU Compliance Agent must pass legal constraints to the Architect Agent (e.g., data residency requirements affecting Azure region choice).
- **Decision:** The eu-compliance comment includes a `### Compliance Constraints for Architecture` section with key:value pairs (e.g., `DATA_RESIDENCY: EU only`). Architect Agent reads this section when making infrastructure decisions.
- **Rationale:** Structured output allows downstream agents to extract constraints without natural language parsing.
- **Consequences:** Architect Agent rules updated to explicitly read this section.

### ADR-002: HTML comment marker `pipeline-agent:eu-compliance` — Issue #1 (2026-02-26)
- **Context:** All pipeline agents use `<!-- pipeline-agent:X -->` markers for downstream detection. The EU Compliance Agent needs a unique marker distinct from the old `legal` marker.
- **Decision:** Use `<!-- pipeline-agent:eu-compliance -->`. Git Agent completeness check updated to verify `eu-compliance` instead of `legal`.
- **Rationale:** Consistent with all other agents; enables automated pipeline detection.
- **Consequences:** Git Agent rules updated to check for `eu-compliance` marker.

### ADR-001: Rules-file architecture (no executable code) — Issue #1 (2026-02-26)
- **Context:** fertiger agents are markdown rules files read by Claude Code. The EU Compliance Agent must follow the same pattern.
- **Decision:** Implement the EU Compliance Agent entirely as `.claude/rules/eu-compliance.md` — no compiled code, no new runtime dependencies.
- **Rationale:** Consistent with all agents; no deployment changes; regulatory knowledge comes from Claude's training.
- **Consequences:** Legal accuracy bounded by Claude's training data; human DPO review at DPIA/high-risk checkpoints is the quality gate.
