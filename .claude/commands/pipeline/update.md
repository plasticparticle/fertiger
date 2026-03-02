Fetch the latest fertiger framework files from the upstream repository and apply them
to this project, without touching your project's docs, config, or source code.

What gets updated:
- .claude/rules/*.md       (agent rules)
- .claude/commands/**/*.md (skill definitions)
- scripts/pipeline/*.sh    (utility scripts)
- .claude/scripts/*.sh     (watch/poll scripts)
- CLAUDE.md                (pipeline documentation)

What is protected (never overwritten):
- .claude/config.sh
- docs/
- .fertiger/ (if present)
- All project source files

Before executing, read `.claude/rules/pipeline-update.md` in full, then follow
all steps defined there.
