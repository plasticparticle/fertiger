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

A shared executable layer lives under `scripts/pipeline/` — POSIX-compatible bash scripts
that any agent can source or invoke for stack detection, test running, swarm coordination,
and dependency checking.

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
| Developer Agent | Agent (rules) | Implements code; runs as a swarm of parallel agents; uses pipeline scripts | `.claude/rules/developer.md` |
| Code Quality Agent | Agent (rules) | Enforces ESLint, TypeScript, naming, architecture compliance | `.claude/rules/code-quality.md` |
| Security Agent | Agent (rules) | OWASP + automated scans; updates docs/SECURITY.md | `.claude/rules/security.md` |
| Git Agent | Agent (rules) | Creates PR; links to issue; sets pipeline:done | `.claude/rules/git-agent.md` |
| Setup Agent | Agent (rules) | One-time provisioning of GitHub Project, labels, config.sh | `.claude/rules/setup.md` |
| Stack Detection Script | Pipeline script | Detects language; exports STACK_* env vars; sourced by agents | `scripts/pipeline/detect-stack.sh` |
| Test Runner Script | Pipeline script | Abstracts test execution across stacks; accepts optional filter | `scripts/pipeline/run-tests.sh` |
| Swarm Lock Script | Pipeline script | File ownership coordination via GitHub Issue comments | `scripts/pipeline/swarm-lock.sh` |
| Dependency Check Script | Pipeline script | Parses imports; lists files missing from current branch | `scripts/pipeline/check-deps.sh` |
| Compliance Register | Document | Running log of GDPR/compliance decisions per feature | `docs/COMPLIANCE.md` |
| Security Register | Document | Running log of security audits and patterns per feature | `docs/SECURITY.md` |
| Pipeline Config | Shell script | GitHub Project node IDs, status option IDs, org/repo config | `.claude/config.sh` (gitignored) |
| Triage Script | Shell script | Classifies feature complexity as TRIVIAL/STANDARD/COMPLEX before agents start deep analysis | `scripts/pipeline/triage.sh` |

---

## Architecture Decision Records

_ADRs are appended here by the Architect Agent on each feature. Most recent first._

### ADR-008: POSIX sh compatibility as the primary portability constraint — Issue #3 (2026-02-26)
- **Context:** Issue #3 requires Linux and macOS compatibility for pipeline scripts. macOS ships bash 3.x (pre-associative arrays) and the default shell is zsh.
- **Decision:** All pipeline scripts use `#!/usr/bin/env bash` shebangs but restrict themselves to POSIX-compatible bash constructs. No bash 4+ features (no associative arrays, no `mapfile`, no complex `[[ ]]` regex).
- **Rationale:** Ensures scripts work on macOS default bash 3.2 as well as Linux bash 5.x. Windows is explicitly out of scope.
- **Consequences:** Pattern matching and text processing use `grep`, `sed`, `awk`. No `declare -A`. No `readarray`/`mapfile`.

### ADR-007: Swarm lock state stored as a GitHub Issue comment, not a file — Issue #3 (2026-02-26)
- **Context:** Multiple parallel dev agents need to coordinate file ownership. Options: a lockfile on the branch, a Redis/DB record, or a GitHub Issue comment.
- **Decision:** Lock state is stored as a `<!-- swarm-lock -->` comment on the GitHub Issue, read and updated by `scripts/pipeline/swarm-lock.sh` via `gh api`.
- **Rationale:** Consistent with the pipeline's core principle: all agent state lives in GitHub Issues and Comments. No new infrastructure required. Survives agent restarts. Visible in the audit trail.
- **Consequences:** `swarm-lock.sh` requires `gh` CLI and `$GITHUB_REPO` + `$ISSUE_NUMBER` to be set. Lock operations require one network round-trip. Race condition window is small; agents polling every 60s mitigates this acceptably for a dev workflow.

### ADR-006: Stack detection exports environment variables via `source`, not stdout — Issue #3 (2026-02-26)
- **Context:** Calling scripts need multiple values (language, test command, lint command, etc.). Two options: structured stdout (JSON/key=value) or sourcing the script to populate the shell environment.
- **Decision:** `detect-stack.sh` is designed to be `source`d, not executed. It exports named variables (`STACK_LANGUAGE`, `STACK_TEST_CMD`, `STACK_LINT_CMD`, `STACK_TYPECHECK_CMD`, `STACK_BUILD_CMD`) into the calling shell's environment.
- **Rationale:** The caller needs multiple values simultaneously. Sourcing avoids subprocess overhead and the need to parse structured output. Consistent with how `.claude/config.sh` works in this project.
- **Consequences:** `detect-stack.sh` must not use `exit` for the success path (only for error path). Callers must use `source scripts/pipeline/detect-stack.sh` not `bash scripts/pipeline/detect-stack.sh`.

### ADR-005: `scripts/pipeline/` as the canonical location for pipeline support scripts — Issue #3 (2026-02-26)
- **Context:** The pipeline had no shared executable layer — everything was either a markdown rules file or a gh CLI call. Issue #3 introduces the first actual executable scripts. They need a home that is clearly pipeline infrastructure, not application code.
- **Decision:** Place all pipeline support scripts under `scripts/pipeline/`. The `scripts/` prefix follows common convention; `pipeline/` scopes them away from any future application scripts.
- **Rationale:** Keeps pipeline tooling separate from any future application code; makes discoverability obvious; mirrors the existing `.claude/rules/` namespace convention (pipeline-scoped).
- **Consequences:** All agent rules that reference these scripts use relative paths from the repo root (e.g. `source scripts/pipeline/detect-stack.sh`). Scripts must be committed with executable bit (`chmod +x`).

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
