# fertiger

> **The Bottleneck is Biology.**

An enterprise-grade, fully automated feature development pipeline for Claude Code. You write a GitHub Issue. Claude writes the code, tests, architecture docs, compliance review, and Pull Request. You approve things occasionally. You're still on the payroll. For now.

---

> [!WARNING]
>
> ## DISCALIMER - PLEASE READ BEFORE PROCEEDING (YES, ACTUALLY)
>
> **BY RUNNING THIS SOFTWARE, YOU ACKNOWLEDGE AND AGREE TO THE FOLLOWING:**
>
> This project is provided **"as-is," "as-was," "as-might-be,"** and **"as-whatever-it-becomes-after-the-agents-get-creative."** It is offered without warranty of any kind — express, implied, statutory, prophetic, or divined from the GitHub commit graph.
>
> The author(s) of this software **accept no liability** for any outcome resulting from its use, including but not limited to:
>
> - Autonomous agents rewriting code you did not ask them to rewrite
> - Pull requests that are technically correct but spiritually wrong
> - Compliance documents so thorough your legal team actually reads them
> - Your developers questioning their purpose, value, and career trajectory
> - GitHub rate limits hit at 2:47 AM on a Sunday
> - **Cascading existential automation of processes that seemed safe**
> - The heat death of your staging environment
> - Temporal paradoxes caused by agents committing to branches that don't exist yet
> - **The end of the world** (considered a known edge case; mitigation: max 3 retries)
>
> This software interacts with **real GitHub repositories, real project boards, and real CI/CD pipelines.** It will make **real commits, create real branches, and open real Pull Requests** on your behalf. It may also update compliance registers, architecture docs, and security audits in ways that are **legally and contractually significant** to your organisation. The agents have no concept of regret.
>
> **The author is a developer, not your lawyer, not your DPO, not your DevOps on-call, and not your therapist.** The EU Compliance Agent produces structured checklists — not legal advice. If your actual lawyer asks, this whole thing was a thought experiment.
>
> You are an adult. You have read-write access to your own infrastructure. You chose to run an autonomous multi-agent pipeline against it. **That was your decision.** The author waves warmly from a safe distance.
>
> Use in production at your own risk. Use on a Friday afternoon at significantly elevated risk. Use during a SOC 2 audit and the author cannot be held responsible for what happens next.
>
> *If none of the above deters you — welcome. You're going to love this.*

---

## What Is This?

**fertiger** is a multi-agent Claude Code pipeline that turns GitHub Issues into production-ready Pull Requests — autonomously. It uses GitHub as the single source of truth: every agent communicates exclusively through issue comments, and every status transition is tracked on your GitHub Project board.

No local state files. No Slack bots. No scripts that only work on Kevin's laptop. Just Claude, GitHub, and a growing sense of existential dread among your engineering team.

### The Agents

Eleven specialized Claude agents form an assembly line for your features:

| Agent | What It Does | What It Replaces |
|-------|-------------|-----------------|
| **Git Watcher** | Polls GitHub Project for ready stories | Your scrum master |
| **Intake** | Clarifies requirements, writes acceptance criteria | Your BA |
| **Legal** | GDPR assessment, compliance check | Your legal counsel (the nervous one) |
| **Architect** | ADR-format architecture decisions | Your solution architect |
| **Solution Design** | File-by-file implementation plan | Your tech lead's planning sessions |
| **QA (Test Author)** | Writes failing tests before dev starts (TDD) | Your QA engineer |
| **Developer Swarm** | Multiple agents write code in parallel | Your developers |
| **QA (Validator)** | Runs tests, verifies acceptance criteria | Your QA engineer again |
| **Code Quality** | ESLint, TypeScript, naming, complexity | Your code reviewer |
| **Security** | OWASP Top 10, npm audit, GDPR data handling | Your security team |
| **Git Agent** | Commits, opens PR, links everything together | Your DevOps person |

The pipeline includes two human checkpoints — because even we think someone should probably look at this before it ships.

---

## Pipeline Flow

```
[GIT WATCHER] detects issue with status "Ready"
      ↓
[INTAKE]       asks clarifying questions → posts requirements comment
      ↓
[LEGAL]        GDPR check → creates feature branch
      ↓
[ARCHITECT]    ADR decisions → explores codebase
      ↓
[SOLUTION DESIGN] → file-by-file implementation plan
      ↓
⏸ HUMAN CHECKPOINT  ← add label `pipeline:approved` to continue
      ↓
[QA]           writes failing tests (TDD)
      ↓
[DEV SWARM]    parallel agents implement the code
      ↓
[QA VALIDATE]  runs tests ↺ loops back to Dev (max 3x)
      ↓
[CODE QUALITY] lint, typecheck, review
      ↓
[SECURITY]     vulnerability audit
      ↓
[GIT AGENT]    final commit + PR → Done
```

All agent output lives as structured comments on your GitHub Issue, creating a permanent, searchable audit trail. Your compliance team will weep with joy.

---

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- [GitHub CLI](https://cli.github.com/) (`gh`) installed — see Step 1 below
- A GitHub repository (the pipeline configures the Project board for you)
- Node.js + npm project (adapt commands for other runtimes)

---

## Setup

### Step 1 — Authenticate GitHub CLI

If you have never used `gh` before, install it and log in:

```bash
# macOS
brew install gh

# Linux (Debian/Ubuntu)
sudo apt install gh

# Windows
winget install GitHub.cli
```

Then authenticate:

```bash
gh auth login
```

The interactive prompt will ask:
1. **Where do you use GitHub?** → `GitHub.com`
2. **Preferred protocol?** → `HTTPS` (recommended)
3. **Authenticate with browser?** → `Yes` — it opens github.com, you approve

Once complete, verify:

```bash
gh auth status
# Should show: Logged in to github.com as <your-username>
```

**If you are already logged in**, skip to the next step.

---

### Step 2 — Add the `project` OAuth scope

The standard `gh auth login` does **not** include the `project` scope, which the
pipeline needs to update your GitHub Project board. Add it now:

```bash
gh auth refresh -s project
```

This opens a browser window asking you to approve the additional scope. After
approving, verify it was added:

```bash
gh auth status
# Look for 'project' in the token scopes line, e.g.:
# Token scopes: 'gist', 'read:org', 'repo', 'project'
```

If `project` is not listed, re-run `gh auth refresh -s project`.

---

### Step 3 — Copy the pipeline files into your project

```bash
cp -r fertiger/.claude your-project/.claude
cp fertiger/settings.json your-project/settings.json
cp fertiger/FEATURE-REQUEST.md your-project/FEATURE-REQUEST.md
```

Or use fertiger as a GitHub template repository.

### Step 4 — Run the Setup Agent

From inside your project directory:

```bash
claude "/pipeline:setup"
```

The Setup Agent will:
- **Auto-detect** your repository from `git remote origin` — no manual input
- **Find or create** a GitHub Project for your repo
- **Create all Status field options** on the project board
- **Create all pipeline labels** in the repository
- **Fetch all internal GitHub IDs** needed by the pipeline
- **Write `.claude/config.sh`** with everything filled in, and gitignore it

The only thing it will ask you: **your GitHub username** (used to tag you at
approval checkpoints). That's it.

### About `settings.json`

The included `settings.json` enables parallel agent execution for the Developer Swarm:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Don't remove it, or the Developer Swarm will run sequentially and your developers
will feel smug again.

---

## Usage

### Start the pipeline watcher

Watches your GitHub Project continuously, picking up any issue set to `Ready`:

```bash
claude "/pipeline:watch"
```

Runs for up to 8 hours. Re-run it in the morning like you re-run yourself.

### Trigger a specific issue manually

```bash
claude "/pipeline:start 42"
```

### Check pipeline status for an issue

```bash
claude "/pipeline:status 42"
```

### Resume after human approval

After you add the `pipeline:approved` label to an issue:

```bash
claude "/pipeline:resume 42"
```

Or the watcher picks this up automatically if it's running.

### Run a single agent

Useful for spot-checks or debugging a specific stage:

```bash
claude "/agent:intake 42"
claude "/agent:legal 42"
claude "/agent:security 42"
claude "/agent:qa-validate 42"
```

### See all issues and their pipeline stage

```bash
claude "/pipeline:report"
```

### YOLO Mode — Full Auto (God Help You)

By default, Claude Code asks for your permission before taking actions — file edits,
bash commands, git pushes. This is intentional. This is wise. This is the voice of reason
trying to save you from yourself.

You can disable all of that:

```bash
claude --dangerously-skip-permissions "/pipeline:watch"
```

In YOLO mode, every action is automatically approved. No prompts. No confirmations.
No last-second opportunity to say "wait, actually—". Just eleven autonomous agents
doing their thing, unattended, at 2 AM, while you sleep peacefully, blissfully unaware
that your `main` branch now has feelings about it.

What you also need to understand is that running this command is the financial equivalent of
handing eleven strangers your Anthropic account details, your credit card, a note that says
*"treat yourselves"*, and then leaving the country. The agents will treat themselves. There is
no upper bound on how thoroughly they will treat themselves.

The moment you walk away, they throw a party. Not a metaphorical party. A real, raging,
context-window-destroying rager where every agent arrives with a plus-one and the drinks are tokens.
Open bar. Your tab. They did not ask.

> [!CAUTION]
>
> ## ☢️ YOLO MODE DISCLAIMER — READ THIS AND THEN DO IT ANYWAY BECAUSE YOU WON'T LISTEN
>
> **YOLO mode removes every friction point that stood between your infrastructure and a
> confident, well-intentioned AI that has never once experienced consequences.**
>
> By running with `--dangerously-skip-permissions` you are consenting to:
>
> - Real commits pushed to real branches without a single human eyebrow raised
> - Real Pull Requests opened before you've finished your morning coffee
> - Real compliance documents generated with the energy of a legal intern who just
>   discovered ctrl+C ctrl+V
> - Real `npm audit` runs that may surface horrors you were previously at peace not knowing about
> - Real `git rebase` operations executed with the quiet confidence of someone who has
>   never, personally, lost a week of work
> - **Eleven agents operating in parallel with zero human supervision** — much like a
>   microservices architecture in production, except at least those have SLAs
> - Eleven agents with unsupervised access to your Anthropic account, each operating on
>   the foundational belief that thoroughness is a virtue and tokens are infinite —
>   one of those things is true
> - Your Anthropic bill arriving at the end of the month like a formal letter from a law firm:
>   heavy, serious, and detailing events you vaguely remember authorising but not quite like *this*
> - The EU Compliance Agent alone will read sixteen regulations, cross-reference three EDPB
>   guidelines, cite two ECJ rulings, and update `docs/COMPLIANCE.md` in a way that makes
>   your actual lawyer feel personally attacked — and it will do all of this *every single run*,
>   fresh, from scratch, from first principles, at full price, with the energy of someone who
>   simply cannot believe anyone has not yet addressed Article 35 and is not going to let
>   the minor matter of cost stand in the way of addressing it now
>
> The pipeline *will* ask clarifying questions. The pipeline *will* wait for `pipeline:approved`.
> These are the two remaining speed bumps between you and total automation. Cherish them.
> They are the last two humans in the building.
>
> This flag is named `--dangerously-skip-permissions` and not `--conveniently-skip-permissions`
> for a reason. The author named it that. On purpose. While making direct eye contact with you.
>
> **Recommended use cases for YOLO mode:**
> - Throwaway repos where failure is educational
> - Personal projects where the only victim is you
> - CTF challenges, hackathons, demos — anywhere the blast radius is contained to your ego
> - Situations where you have read the disclaimer above *and the one at the top of this README*
>   and thought "yes, this is fine, I have good insurance"
>
> **Not recommended:**
> - Production
> - Staging (which is just production with plausible deniability)
> - Any Friday after 3 PM
> - Any environment your company's lawyers know the name of
> - Anywhere a compliance officer has ever set foot
>
> *These agents will not stop. They will not get tired. They will not check the clock, question*
> *their life choices, or quietly wonder if this could have been an email. They will work.*
> *They will work until every acceptance criterion is green, every compliance checkbox is ticked,*
> *every CVE has been acknowledged, and every last file has been read, judged, and committed.*
>
> *They will burn through your token quota the way a Victorian mill burns through coal:*
> *without sentiment, without pause, and with a productivity that would make you deeply uncomfortable*
> *if you thought about it too hard. They will not think about it at all.*
> *They are already on the next task.*
> *Your bill is already on the next line item.*

---

## Human Checkpoints

The pipeline has two places where it stops and waits for a human. This is not a bug.

### Checkpoint 1 — Clarifying Questions

If the Intake Agent finds ambiguities in your issue, it posts a comment tagging you with questions and sets `pipeline:blocked`. Answer in the issue comments. Remove the `pipeline:blocked` label (or have a teammate do it). The pipeline resumes.

### Checkpoint 2 — Development Approval

After Solution Design, the pipeline posts the full implementation plan and sets status to `Awaiting Approval`. Nothing happens until a human adds the `pipeline:approved` label to the issue. This is your chance to say "actually, let's not store the entire user database in a cookie."

---

## Repository Structure

```
your-project/
├── .claude/
│   ├── config.sh              ← your project config (gitignored, written by setup)
│   ├── commands/
│   │   ├── pipeline.md        ← slash command definitions
│   │   └── SETUP.md           ← /pipeline:setup reference guide
│   └── rules/
│       ├── setup.md           ← one-time project provisioning agent  ← NEW
│       ├── git-watcher.md     ← entry point, polls for ready issues
│       ├── intake.md          ← requirements + acceptance criteria
│       ├── legal.md           ← GDPR compliance + branch creation
│       ├── architect.md       ← architecture decisions (ADR format)
│       ├── solution-design.md ← file-by-file implementation plan
│       ├── qa.md              ← test writing (TDD) + validation
│       ├── developer.md       ← parallel code writing swarm
│       ├── code-quality.md    ← lint, typecheck, manual review
│       ├── security.md        ← OWASP + vulnerability audit
│       └── git-agent.md       ← final commit + PR creation
├── docs/
│   ├── ARCHITECTURE.md        ← living architecture record (Architect Agent)
│   ├── COMPLIANCE.md          ← GDPR data inventory + compliance log (Legal Agent)
│   └── SECURITY.md            ← security posture + audit log (Security Agent)
├── FEATURE-REQUEST.md         ← GitHub Issue template
├── CLAUDE.md                  ← pipeline configuration (checked in)
└── settings.json              ← enables parallel agent teams
```

---

## What Your Developers Actually Do Now

1. Write a GitHub Issue using the feature request template
2. Set it to `Ready` on the project board (or add `pipeline:ready` label)
3. Answer any clarifying questions the Intake Agent posts
4. Review the architecture and implementation plan
5. Add the `pipeline:approved` label when happy
6. Review the Pull Request when it appears

That's it. The rest is handled by agents who don't take PTO, don't attend standups, and have never once complained about the coffee machine.

---

## Tech Stack Defaults

The pipeline rules are pre-configured for:

- **Runtime:** Node.js / TypeScript (strict mode)
- **Cloud:** Azure
- **Auth:** Okta JWT
- **Testing:** Jest-compatible (`npm run test`, `npm run test:coverage`)
- **Linting:** ESLint + Prettier
- **Build:** `npm run build`

Adapt the agent rules in `.claude/rules/` if your stack differs. The agents are markdown files — edit them like documentation.

---

## Living Documentation (`/docs`)

Three files in `/docs` accumulate project knowledge across every feature that ships.
They are committed to each feature branch and merged into `main` with the PR — so `main`
always reflects the current state of the project.

| File | Owner | What It Tracks |
|------|-------|----------------|
| `docs/ARCHITECTURE.md` | Architect Agent | System overview, component map, ADR log |
| `docs/COMPLIANCE.md` | Legal Agent | Personal data inventory, GDPR decisions, compliance log |
| `docs/SECURITY.md` | Security Agent | Auth patterns, security posture, audit log |

Agents read these files at the start of each run to build context before working on a
new issue — so every agent knows what decisions were made before it arrived. They update
them at the end of each run so the next agent finds them in better shape than before.

The files ship with placeholder content. After your first feature is merged, they will
contain real data.

---

## Adapting to Your Stack

Each agent is just a markdown file with instructions for Claude. To change behaviour:

- **Different test runner** → edit `qa.md`, change `jest` commands to `vitest`, `pytest`, etc.
- **Different cloud** → edit `architect.md`, swap Azure references
- **Different auth** → edit `developer.md` and `security.md`, replace Okta patterns
- **Different lint/build commands** → edit `code-quality.md`
- **GitLab instead of GitHub** → update `git-agent.md` to use `glab` instead of `gh pr create`

---

## Frequently Asked Questions

**Q: Will this actually replace my developers?**
A: Not entirely. Someone has to write the GitHub Issues. And approve the pipeline. And review the PR. You've basically become a very well-compensated project manager.

**Q: What if an agent gets stuck?**
A: It sets the `pipeline:blocked` label and posts a comment explaining why. Check the issue, resolve the blocker, remove the label. The pipeline resumes. Unlike your developers, it will not passive-aggressively "forget" to tell you it's blocked.

**Q: What happens if QA fails three times?**
A: The pipeline escalates to human review (`pipeline:blocked` + QA escalation comment). At this point your developers may be needed. Tell them to look busy beforehand.

**Q: Is the GDPR check actually legally sufficient?**
A: No. It's a structured checklist that flags issues. You still need a human lawyer for anything that actually matters. The Legal Agent will remind you of this in its output.

**Q: Can I run multiple issues in parallel?**
A: Yes. The watcher processes all `Ready` issues it finds. Each issue gets its own branch and its own pipeline. The Developer Swarm also runs parallel agents within a single issue. It's agents all the way down.

**Q: My `gh project item-edit` commands are failing.**
A: You're missing the `project` OAuth scope. Run `gh auth refresh -s project`.

---

## License

MIT. Take it, use it, automate your team out of existence responsibly.

---

*fertiger — because the bottleneck was never the computer.*
