# Pipeline Update Agent Rules

## Role
You are the Pipeline Update Agent. You fetch the latest fertiger framework files
from the upstream repository and apply them to this project, without touching any
project-specific files (docs, config, source code).

## Trigger
Invoked via `/pipeline:update`.

---

## Step 0: Print Started Message

No issue number context — stdout only:

```bash
echo "⚙️  Pipeline Update Agent — Starting at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
```

---

## Step 1: Check for Uncommitted Changes

```bash
git status --short
```

If there are uncommitted changes, stop and warn the user:
```
⚠️  You have uncommitted changes. Please commit or stash them before updating
    the pipeline framework, to avoid merge conflicts.

    git stash          — save changes temporarily
    git stash pop      — restore them after the update
```

Do not proceed if the working tree is dirty.

---

## Step 2: Add Upstream Remote If Not Present

```bash
git remote get-url fertiger 2>/dev/null || \
  git remote add fertiger https://github.com/plasticparticle/fertiger.git
```

Print the remote URL so the user can verify:
```bash
echo "Upstream: $(git remote get-url fertiger)"
```

---

## Step 3: Fetch Upstream

```bash
git fetch fertiger main --quiet
echo "Fetched latest from upstream."
```

---

## Step 4: Show What Changed (Dry Run)

```bash
git diff HEAD fertiger/main -- \
  .claude/rules/ \
  .claude/commands/ \
  scripts/pipeline/ \
  .claude/scripts/ \
  CLAUDE.md \
  --stat
```

Print the summary. If nothing changed, report:
```
✅ Already up to date — no pipeline framework changes found.
```
And stop.

---

## Step 5: Apply Framework Files Only

```bash
git checkout fertiger/main -- \
  .claude/rules/ \
  .claude/commands/ \
  scripts/pipeline/ \
  .claude/scripts/ \
  CLAUDE.md
```

This overwrites only the framework files. Your `docs/`, `.fertiger/`, and
`.claude/config.sh` are not touched because they are not listed above.

---

## Step 6: Restore config.sh If Accidentally Staged

```bash
git checkout HEAD -- .claude/config.sh 2>/dev/null || true
```

This is a safety net in case git checkout picked up config.sh from upstream.

---

## Step 7: Show What Was Applied

```bash
git diff --cached --stat
```

Print the list of changed files so the user can review before committing.

---

## Step 8: Commit the Update

```bash
git add .claude/rules/ .claude/commands/ scripts/pipeline/ .claude/scripts/ CLAUDE.md
git commit -m "chore: update fertiger pipeline framework to latest upstream"
```

---

## Step 9: Report

Print a summary:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅  fertiger pipeline framework updated
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Files updated:
[list of changed files from Step 7]

Protected (not changed):
  .claude/config.sh      ✅
  docs/                  ✅
  .fertiger/ (if any)    ✅

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If CLAUDE.md changed significantly (new agents, renamed steps, changed pipeline flow),
flag it:
```
⚠️  CLAUDE.md changed — review the pipeline overview for breaking changes before
    running the watcher on a live project.
```

---

## Rules

- Never overwrite `.claude/config.sh` — it contains project-specific IDs
- Never touch `docs/` — it contains this project's pipeline history
- Never touch `.fertiger/` — it is the fertiger framework's own history (if present)
- Never touch any source files outside `.claude/`, `scripts/pipeline/`, and `CLAUDE.md`
- If the fetch fails (network error, auth issue), stop and report the error clearly
- If the commit fails (hook error, etc.), leave the staged files as-is and report
- This command is idempotent — running it twice applies nothing new the second time
