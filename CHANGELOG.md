# Changelog

All notable changes to fertiger will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

---

## [Unreleased]

---

## [0.1.0] — 2026-02-25

Initial release.

### Added

**Pipeline agents** — eleven Claude Code agents covering the full feature lifecycle:
- `git-watcher` — polls GitHub Project for ready issues, orchestrates the pipeline
- `intake` — clarifies requirements, produces structured acceptance criteria
- `legal` — GDPR compliance check, creates the feature branch
- `architect` — codebase exploration, architecture decisions in ADR format
- `solution-design` — file-by-file implementation plan, sets awaiting approval
- `qa` — TDD test writing before dev, validation after dev with retry loop (max 3×)
- `developer` — parallel swarm agents, each owning assigned files
- `code-quality` — ESLint, TypeScript, manual review checklist
- `security` — OWASP Top 10, npm audit, semgrep, GDPR data handling checks
- `git-agent` — final commit, PR creation, pipeline summary

**Setup agent** — one-time project provisioning via `/pipeline:setup`:
- Auto-detects repository from `git remote origin` — zero manual config
- Finds or creates a GitHub Project
- Creates all Status field options with colours
- Creates all pipeline labels
- Fetches all internal GitHub node IDs
- Writes a complete `.claude/config.sh` and gitignores it
- Only asks one question: your GitHub username

**Living documentation** — three files in `/docs` updated by agents on every merge:
- `docs/ARCHITECTURE.md` — system overview, component map, ADR log
- `docs/COMPLIANCE.md` — GDPR data inventory, transfer register, compliance log
- `docs/SECURITY.md` — auth patterns, known risk areas, security audit log

**Slash commands** — `/pipeline:watch`, `/pipeline:start`, `/pipeline:resume`,
`/pipeline:status`, `/pipeline:retry-dev`, `/pipeline:report`, `/pipeline:setup`,
`/agent:intake`, `/agent:legal`, `/agent:security`, `/agent:qa-validate`

**Human checkpoints** — two deliberate stops in the pipeline:
1. Intake clarifications — agent tags author with questions, waits for reply
2. Development approval — pipeline halts at `Awaiting Approval` until
   `pipeline:approved` label is added

**Supporting files** — `CLAUDE.md`, `README.md`, `.gitignore`, `settings.json`,
`FEATURE-REQUEST.md` GitHub Issue template

[Unreleased]: https://github.com/plasticparticle/fertiger/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/plasticparticle/fertiger/releases/tag/v0.1.0
