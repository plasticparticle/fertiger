> **fertiger self-documentation** — This file tracks the fertiger pipeline framework's
> own audit history. It is NOT a template. Consumer projects write to `docs/` instead.

---

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

Every pipeline-issue-driven agent (Intake through Git Agent) begins its run by posting a
`<!-- pipeline-agent:[name]-started -->` comment to the GitHub Issue. This is the first
action before triage or any substantive work. Long-running agents append timestamped progress
lines to this comment at logical milestones. The started comment is fire-and-forget: failure
to post never aborts the agent's primary work. A duplicate guard prevents re-posting on restart.

---

## Component Map

| Component | Type | Responsibility | Key Files |
|-----------|------|----------------|-----------|
| Git Watcher | Agent (rules) | Polls GitHub Project; claims ready issues; hands off to Intake | `.claude/rules/git-watcher.md` |
| Intake Agent | Agent (rules) | Analyzes issue body; writes structured requirements + ACs | `.claude/rules/intake.md` |
| Estimator Agent | Agent (rules) | Produces business value scores, customer impact profile, complexity estimate, and enterprise comparison block | `.claude/rules/estimator.md` |
| EU Compliance Agent | Agent (rules) | Deep EU regulatory review (GDPR, AI Act, NIS2, DSA, etc.); creates feature branch | `.claude/rules/eu-compliance.md` |
| Architect Agent | Agent (rules) | Explores codebase; produces ADRs and component decisions | `.claude/rules/architect.md` |
| Solution Design Agent | Agent (rules) | Produces file-by-file implementation plan; triggers human approval | `.claude/rules/solution-design.md` |
| QA Agent | Agent (rules) | Writes TDD tests before dev; validates after dev | `.claude/rules/qa.md` |
| Developer Agent | Agent (rules) | Implements code; runs as a swarm of parallel agents; uses pipeline scripts | `.claude/rules/developer.md` |
| Code Quality Agent | Agent (rules) | Enforces ESLint, TypeScript, naming, architecture compliance | `.claude/rules/code-quality.md` |
| Security Agent | Agent (rules) | OWASP + automated scans; updates $PIPELINE_DOCS_DIR/SECURITY.md | `.claude/rules/security.md` |
| Git Agent | Agent (rules) | Creates PR; links to issue; sets status: Done | `.claude/rules/git-agent.md` |
| Setup Agent | Agent (rules) | One-time provisioning of GitHub Project, labels, config.sh | `.claude/rules/setup.md` |
| Stack Detection Script | Pipeline script | Detects language; exports STACK_* env vars; sourced by agents | `scripts/pipeline/detect-stack.sh` |
| Test Runner Script | Pipeline script | Abstracts test execution across stacks; accepts optional filter | `scripts/pipeline/run-tests.sh` |
| Swarm Lock Script | Pipeline script | File ownership coordination via GitHub Issue comments | `scripts/pipeline/swarm-lock.sh` |
| Dependency Check Script | Pipeline script | Parses imports; lists files missing from current branch | `scripts/pipeline/check-deps.sh` |
| Compliance Register | Document | Running log of GDPR/compliance decisions per feature | `$PIPELINE_DOCS_DIR/COMPLIANCE.md` |
| Security Register | Document | Running log of security audits and patterns per feature | `$PIPELINE_DOCS_DIR/SECURITY.md` |
| Pipeline Config | Shell script | GitHub Project node IDs, status option IDs, org/repo config | `.claude/config.sh` (gitignored) |
| Triage Script | Shell script | Classifies feature complexity as TRIVIAL/STANDARD/COMPLEX before agents start deep analysis | `scripts/pipeline/triage.sh` |
| Metrics Script | Pipeline script | Reads structured `.jsonl` logs; produces per-agent timing reports and historical run summaries | `scripts/pipeline/metrics.sh` |
| Structured Observability | Convention | Per-run JSON lines audit trail; 30-day rotation; queryable with jq | `.pipeline-logs/issue-N/<run_id>.jsonl` |
| Docs Lock Script | Pipeline script | Advisory file lock for shared docs (COMPLIANCE.md, ARCHITECTURE.md, SECURITY.md) across concurrent pipeline runs | `scripts/pipeline/docs-lock.sh` |
| Docs Lock Registry Issue | GitHub Issue | Persistent issue used as the comment anchor for all docs lock state; number stored as `DOCS_LOCK_ISSUE` in config.sh | GitHub Issue (created by setup agent) |

---

## Architecture Decision Records

_ADRs are appended here by the Architect Agent on each feature. Most recent first._

### ADR-021: Conflict-marker detection extends scan-compliance.sh — Issue #16 (2026-03-05)
- **Context:** REQ-006 / AC-006 requires detection of unresolved Git merge conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) in docs files. The compliance audit agent already runs `scan-compliance.sh` as its scanning step.
- **Decision:** Add a new `=== CONFLICT_MARKERS ===` section to `scan-compliance.sh` output. The section scans `COMPLIANCE.md`, `ARCHITECTURE.md`, and `SECURITY.md` for conflict marker patterns and emits file:line pairs. The compliance audit agent rules check this section before proceeding — conflict markers are a hard stop reported before any column-by-column drift analysis.
- **Rationale:** Extending the existing scanner avoids a new script and keeps all docs-file inspection in one place. Adding a new script would require updating three files (script + SCRIPTS.md + rules); extending `scan-compliance.sh` touches one script and one rules file.
- **Consequences:** `scan-compliance.sh` now also scans the docs files themselves for conflict markers. The conflict-marker check appears first in output order.

### ADR-020: git pull --rebase before staging docs changes — Issue #16 (2026-03-05)
- **Context:** REQ-005 requires docs file writes to incorporate concurrent changes from `main` before committing. Without a rebase, a feature branch created hours ago overwrites rows added by a pipeline run that completed in the interim.
- **Decision:** Each agent rules file that writes a docs file executes `git pull --rebase origin main` *after* acquiring the docs lock and *before* staging and committing. If rebase produces a conflict on the docs file, the agent aborts (`git rebase --abort`), releases the lock, sets status to Blocked, and posts a clear error comment.
- **Rationale:** Rebase (not merge) preserves a clean linear history. Running it after lock acquisition ensures no concurrent write can land between the rebase and the commit. A conflict after lock acquisition indicates a protocol bug requiring human review.
- **Consequences:** Lock is always released on failure (acquire → rebase → write → commit → push → release). Agents must handle non-zero rebase exit as a Blocked condition.

### ADR-019: docs-lock.sh exposes acquire/release/check/list (claim+verify encapsulated) — Issue #16 (2026-03-05)
- **Context:** REQ-004 requires a configurable timeout (default 10 minutes). Three agent rules files must acquire and release docs locks. `swarm-lock.sh` exposes claim/verify as separate steps requiring agents to implement the polling loop. Replicating that loop across three rules files creates drift risk.
- **Decision:** `docs-lock.sh` exposes four user-facing commands: `acquire <agent> <issue_number> <file-path>`, `release <agent> <issue_number>`, `check <file-path>`, `list`. The `acquire` command encapsulates the claim + polling-verify loop internally, sleeping 5 seconds between attempts until CONFIRMED or `DOCS_LOCK_TIMEOUT_SECONDS` (default 600) elapses. On timeout, exits 1 and prints the current lock holder. The calling agent handles exit 1 by posting a Blocked comment.
- **Rationale:** Encapsulating the polling loop in the script prevents three copies of the same bash loop appearing in three rules files. The higher-level `acquire`/`release` API is simpler than the manual claim/verify split and sufficient for the docs-lock use case.
- **Consequences:** `docs-lock.sh` claim/verify are internal functions, not user-facing commands. Testing acquires and releases via the public `acquire`/`release` interface.

### ADR-018: Lock scope is the file path; marker encodes agent + issue number — Issue #16 (2026-03-05)
- **Context:** `swarm-lock.sh` is scoped to a single `$ISSUE_NUMBER`: each agent claims specific files but all claims live within one issue's comments. Docs locks must arbitrate across issues, so the scope discriminator must be the *file path* itself.
- **Decision:** Each `docs-lock.sh` claim comment body encodes the locked file path as `LOCKED_FILE: <path>` and uses the marker `<!-- docs-lock:<AGENT_NAME>-issue-<ISSUE_NUMBER> -->` to uniquely identify the lock holder across concurrent issues. Timestamp arbitration is identical to `swarm-lock.sh`: most recent `TIMESTAMP:` wins; comment ID is the tiebreaker.
- **Rationale:** File-path scope directly maps to the contention resource. The compound marker (agent + issue) prevents collisions between agents from different issues with the same agent name. Timestamp arbitration is proven correct by the swarm-lock test suite.
- **Consequences:** `docs-lock.sh check <file-path>` fetches all claim comments from the lock-registry issue and returns the winner for that specific file path. Release deletes only the comment matching the calling agent's compound marker.

### ADR-017: Dedicated lock-registry issue as the comment anchor for cross-issue docs locks — Issue #16 (2026-03-05)
- **Context:** `swarm-lock.sh` stores claim comments on the feature issue (`$ISSUE_NUMBER`). Docs locks must span multiple concurrent feature issues simultaneously — a lock held by issue #20 must be visible to issue #21. Using the feature issue as the anchor makes cross-issue visibility impossible.
- **Decision:** Create a dedicated, permanent **lock-registry issue** (title: "fertiger: pipeline docs lock registry"). All `docs-lock.sh` claim comments are posted to this single issue regardless of which feature issue the writing agent belongs to. The registry issue number is stored as `DOCS_LOCK_ISSUE` in `.claude/config.sh`. The setup agent is updated to create this issue and write `DOCS_LOCK_ISSUE` to config.sh.
- **Rationale:** A single shared coordination point guarantees all agents see all competing claims. Consistent with ADR-007 (lock state in GitHub Issue comments, no local files). The setup agent already provisions infrastructure (labels, project, config) — adding the registry issue follows the same pattern.
- **Consequences:** `docs-lock.sh` reads `DOCS_LOCK_ISSUE` (not `ISSUE_NUMBER`) for all API calls. `docs-lock.sh` validates `DOCS_LOCK_ISSUE` is non-empty at startup and prints a diagnostic if not. The lock-registry issue is write-only infrastructure and must not be used for other purposes.

### ADR-016: `.pipeline-logs/issue-N/` directory layout with 30-day rotation — Issue #15 (2026-03-03)
- **Context:** REQ-005 and REQ-007 require structured log files per run at a predictable path, with automatic 30-day rotation.
- **Decision:** Layout: `.pipeline-logs/issue-N/<run_id>.jsonl`. Rotation runs inside `log.sh` as a background cleanup: `find .pipeline-logs -name "*.jsonl" -mtime +30 -delete 2>/dev/null &`.
- **Rationale:** Background cleanup (`&`) adds zero latency. Idempotent and harmless per invocation. No cron or separate process required.
- **Consequences:** `metrics.sh N` lists all `.jsonl` files under `.pipeline-logs/issue-N/` for historical run summaries.

### ADR-015: `run_id` persistence via `.pipeline-logs/issue-N/.current-run-id` sentinel file — Issue #15 (2026-03-03)
- **Context:** `run_id` must be consistent across many `log.sh` invocations from separate shell processes within one pipeline run.
- **Decision:** On first `log.sh` call for a given `ISSUE_NUMBER`, write `run_id = issue-N-YYYYMMDD-HHMMSS` to `.pipeline-logs/issue-N/.current-run-id`. All subsequent calls read from this file. `cancel-pipeline.sh` deletes it on cancel.
- **Rationale:** File-based sentinel is the simplest zero-dependency POSIX coordination mechanism. Consistent with ADR-007 (local state stays local).
- **Consequences:** `.pipeline-logs/` must be gitignored.

### ADR-014: JSON lines (ndjson) as structured log format — Issue #15 (2026-03-03)
- **Context:** REQ-002 requires structured, queryable log output. JSON lines chosen over JSON array, CSV, SQLite.
- **Decision:** One JSON object per line in `.jsonl` files. Each line independently parseable with `jq`.
- **Rationale:** `printf` line appends are atomic on Linux for lines < 4096 bytes. `jq` can filter without loading the full file. Zero new dependencies.
- **Consequences:** Consumers read line-by-line. `metrics.sh` uses `jq -s` for aggregation.


### ADR-013: setup.md and pipeline-update.md use stdout-only heartbeat — Issue #7 (2026-03-02)
- **Context:** `setup.md` and `pipeline-update.md` run interactively with no `$ISSUE_NUMBER`. They cannot post to a GitHub Issue.
- **Decision:** These agents print a started message to stdout only (`echo "⚙️ [Agent] — Started at $(date -u)"`), not to a GitHub Issue comment. No duplicate guard is needed.
- **Rationale:** Consistency with the spirit of the requirement (visibility that the agent has started) without inapplicable GitHub API calls.
- **Consequences:** These agents do not follow the full `<!-- pipeline-agent:[name]-started -->` pattern. This is the documented exception.

### ADR-012: Progress updates are edits to the started comment, not new comments — Issue #7 (2026-03-02)
- **Context:** REQ-002 requires progress updates at logical milestones. Posting new comments for each update floods the issue thread.
- **Decision:** Progress updates are appended to the started comment body via `gh api --method PATCH /repos/$GITHUB_REPO/issues/comments/$COMMENT_ID`. Agent captures the started comment URL from `gh issue comment` output and extracts the numeric ID as the last URL path segment.
- **Rationale:** Keeps the issue thread readable — one live-updating status comment per agent. Consistent with REQ-002.
- **Consequences:** Agents posting progress updates must store the started comment ID. The PATCH body includes the full updated text; agents accumulate progress lines across milestones.

### ADR-011: Duplicate guard uses `test("[name]-started")` jq pattern — Issue #7 (2026-03-02)
- **Context:** REQ-005 requires a duplicate guard before posting a started comment. The project's established jq safety rule prohibits `contains("<!--")` due to shell escape issues with `!`.
- **Decision:** Each agent's duplicate guard uses `jq '[.comments[].body | test("[name]-started")] | any'`. Early-exits the started comment block (not the whole agent) when the result is `true`.
- **Rationale:** Consistent with the project-wide jq safety rule (CLAUDE.md, ADR-002). `test()` is reliable regardless of HTML comment content.
- **Consequences:** All 10 pipeline agents include this guard in their new Step 0. REQ-004 (fire-and-forget) is satisfied: guard exits only the started comment block, never the agent's primary work.

### ADR-010: Developer agent's existing announce pattern converges into the standard heartbeat — Issue #7 (2026-03-02)
- **Context:** `.claude/rules/developer.md` already has `Step 0: Announce Your Start` with marker `<!-- pipeline-agent:dev-$AGENT_NAME-start -->`. This diverges from the standard `-started` suffix and lacks a duplicate guard.
- **Decision:** Replace the announce step with the standard heartbeat pattern. Use marker `<!-- pipeline-agent:dev-$AGENT_NAME-started -->`. Add duplicate guard. Preserve existing announce content (assigned area, file list, branch) inside the started comment template.
- **Rationale:** Convergence eliminates a divergent pattern. Consistent `-started` suffix enables uniform detection. Duplicate guard satisfies REQ-005.
- **Consequences:** Downstream detection of `pipeline-agent:dev-$AGENT_NAME-start` (without `d`) must update to `-started`. Git Agent completeness check uses `test("pipeline-agent:dev-[^s]")` — the `[^s]` correctly excludes `-started` (starts with `s`); no regression.

### ADR-009: Started comment inserted as Step 0 in every agent, before triage — Issue #7 (2026-03-02)
- **Context:** Every agent needs a heartbeat as its first action. Most agents use Step 0 for triage. The heartbeat must precede triage.
- **Decision:** Where an agent has an existing `Step 0`, renumber all steps up by one (Step 0 → Step 1, Step 1 → Step 2, etc.) and insert the heartbeat as the new `Step 0: Post Started Comment`. Where no Step 0 exists, insert before the existing Step 1.
- **Rationale:** Renumbering preserves step semantics. Two sequential Step 0s would be invalid. Applies to all 10 pipeline-issue-driven agents; `setup.md` and `pipeline-update.md` use ADR-013 exception.
- **Consequences:** All existing step-number references within each rules file must be verified post-edit. `code-quality.md` contains two agents (Code Quality + Security) — both receive their own started comment with distinct markers (`code-quality-started`, `security-started`).

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
