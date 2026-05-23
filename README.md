# auto-engineer

A general-purpose **Cursor Agent CLI** toolkit for autonomous, closed-loop software delivery. Run it from this repo to seed any project with the skills and Docker infrastructure needed to pick issues, implement changes, push PRs, respond to CI and review feedback, and merge — without human intervention between steps.

Inspired by auto-researcher by @karpathy.

This toolkit is a starting off point; in order for it to be effective in your project, you will have to think critically about the autonomous software development lifecycle. Different projects require different things!

## Demo

Perhaps you want to see a demo first, before deciding if this is for you.
Check out [vibix](https://github.com/dburkart/vibix), an autonomously developed operating system.

## What's included

| Skill | Description |
|---|---|
| `/seed` | One-time setup: asks for a target project path, detects its stack, writes customized skills and Docker files into it |
| `/auto-engineer` | The main loop: pick → plan → implement → PR → wait → merge → repeat *(written into target by `/seed`)* |
| `/auto-manager` | Epic orchestrator: scope a fuzzy topic, file sub-issues, spawn parallel workstreams *(written into target)* |
| `/sdlc` | Branch, commit, and PR conventions *(written into target)* |
| `/file-issue` | File issues with correct labels *(written into target)* |
| `/wait-for-pr` | Manual PR-wait loop with CI polling and auto-fix *(written into target)* |
| `/usage` | Best-effort quota gate for auto-engineer *(written into target)* |

Plus Docker infrastructure (`scripts/sandbox.sh`, `scripts/orchestrate.sh`, `Dockerfile`) so the loop runs headless with `agent -p --force` in an isolated container.

### How the loop runs

`ScheduleWakeup` (Claude Code) is replaced by **[`scripts/orchestrate.sh`](scripts/orchestrate.sh)**:

1. Run `agent -p` with `/auto-engineer …`
2. The skill ends with `AE_NEXT {"sleep":…,"prompt":…}` or `AE_STOP {"reason":…}`
3. The script sleeps and repeats (or exits)

## Seeding a project

Open Cursor Agent CLI in this repo and run:

```
/seed
```

The agent will ask for the path to your target project, then:

1. Auto-detect the tech stack and GitHub configuration
2. Ask a few questions about labels and playbooks
3. Write customized skills under `.cursor/skills/`, `.cursor/cli.json`, and Docker scripts

The seed skill never overwrites existing `.cursor/skills/<name>/` directories.

## After seeding

In the target project, review and commit the generated files, then:

```sh
# Start the autonomous loop in a container
scripts/auto-engineer.sh

# One orchestrator tick (e.g. a single skill)
scripts/sandbox.sh /wait-for-pr

# Single agent invocation (no AE_NEXT contract)
scripts/sandbox.sh --direct /seed
```

### Docker prerequisites

- Docker installed and running
- `CURSOR_API_KEY` ([Cursor Dashboard → Integrations](https://cursor.com/dashboard/integrations))
- `GITHUB_TOKEN` in your environment or in `.env` at the project root

The container clones the target repo into `/home/agent/work` and mounts the project's `.cursor/` directory when present.

## Migrating from Claude Code

Projects seeded with the older Claude-based toolkit have skills under `.claude/skills/`. Re-run `/seed` from this repo (it writes to `.cursor/skills/` only for missing names), or copy skills manually and add `scripts/orchestrate.sh` plus `.cursor/cli.json` from the templates.

## Playbooks

The seeded skills optionally reference playbook files that hold project-specific policy:

| Playbook | Contents |
|---|---|
| `sdlc.md` | Branch naming, commit format, PR process |
| `build-run.md` | How to build and run the project locally |
| `testing.md` | Test strategy, CI matrix, how to run tests |
| `pr-review.md` | CI readiness criteria, review classification rules |
| `prioritization.md` | Issue label taxonomy, priority definitions, triage rules |

`/seed` can create stub versions of these for you to fill in. If you skip playbooks, policy is inlined into the skills directly.

## Re-seeding

Run `/seed` from this repo again at any time to add skills that were missing or update Docker files. Existing skills and playbooks are never overwritten.
