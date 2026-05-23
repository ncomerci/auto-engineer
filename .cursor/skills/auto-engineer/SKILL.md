---
name: auto-engineer
description: Autonomously drive project work end-to-end — pick an unblocked issue, plan it, implement, push a PR, resolve CI and review-bot feedback, merge when green, then repeat. Use when the user says "auto-engineer", "auto-pilot", "go run the loop", or invokes `/auto-engineer`.
---

# auto-engineer

Read the tracker playbook first: `{{PLAYBOOK_TRACKER}}`. Every tracker operation in this skill (list, pick, assign, comment, close) goes through one of its recipes — do **not** call `gh issue ...` or other tracker commands directly from this skill, so auto-engineer stays tracker-agnostic (GitHub Issues / local to-do / future backends).

{{#if PLAYBOOK_SDLC}}Then read these shared playbooks:

- `{{PLAYBOOK_SDLC}}`
- `{{PLAYBOOK_BUILD}}`
- `{{PLAYBOOK_TEST}}`
- `{{PLAYBOOK_PR_REVIEW}}`
- `{{PLAYBOOK_PRIORITIZATION}}`
{{/if}}

Closes the full SDLC loop without prompting the user between steps. Each **tick** (one `agent -p` invocation, usually driven by `scripts/orchestrate.sh`) advances the workflow: pick → plan → implement → PR → wait → merge. When more work remains later (CI polling, next cycle), emit **`AE_NEXT`** so the orchestrator sleeps and re-invokes with the next prompt. When finished or blocked, emit **`AE_STOP`**. Stops cleanly when it runs out of work or hits something it can't safely resolve.

## Orchestrator contract (`AE_NEXT` / `AE_STOP`)

`ScheduleWakeup` does not exist in Cursor. The host runs [`scripts/orchestrate.sh`](scripts/orchestrate.sh), which loops: `agent -p` → parse control line → `sleep` → repeat.

End **every tick** with exactly one machine-readable line as the **last line of your final message**:

```text
AE_NEXT {"sleep":120,"prompt":"/auto-engineer --iteration 3 --phase wait --pr 42"}
AE_STOP {"reason":"no unblocked issues"}
```

- **`sleep`**: seconds until the next tick (orchestrator runs `sleep`; you must **not** poll in a tight loop inside one tick).
- **`prompt`**: full next invocation string (include `/auto-engineer` and all flags).
- On any **Stopping** condition: `AE_STOP` only — never `AE_NEXT`.
- Scoping to one issue (`#NN`): after that cycle completes, `AE_STOP` with reason — do not schedule another cycle.

Each tick starts with a **fresh context**; carry state only via prompt flags (`--iteration`, `--phase wait`, `--pr`, `--fix-round`, `--hitl`, etc.).

This skill is a deliberate override of the project's default "don't merge your own PRs" rule — merging is the whole point of closing the loop. It only applies while auto-engineer is driving.

## When to invoke

- User says "run the loop", "auto-engineer", "auto-pilot the next issue", or similar.
- User types `/auto-engineer` (optionally with `#NN` to scope to a single issue for one cycle, no reschedule).
- Under Docker, `scripts/auto-engineer.sh` → `orchestrate.sh` runs this skill in a loop until `AE_STOP`.

## Entry flags and phase state

All persistent state lives in the **orchestrator prompt** — each tick is a new agent session, so nothing important should rely on conversation memory.

Parse these flags on every entry before doing any work:

| Flag | Meaning |
|---|---|
| `--iteration N` | Current cycle number (1-indexed). Absent → treat as 1. |
| `--phase wait` | Re-entry into the PR-wait poll loop (jump to step 6b). Requires `--pr`. |
| `--pr M` | PR number being waited on (only meaningful with `--phase wait`). |
{{#if HITL_MODE}}| `--hitl` | Human-in-the-loop mode. After opening a PR (step 5), pause for human review before entering the CI/merge loop. Sticky — include in every `AE_NEXT` prompt for the rest of the session. |
| `--hitl-approved` | User has reviewed the PR and approved resuming. Skip the HITL pause and proceed directly into the normal CI/merge wait loop (step 6a). Only meaningful alongside `--phase wait`. |
{{/if}}| `#NN` | Scope to a single issue for one cycle, then stop without rescheduling. |

A bare `/auto-engineer` is iteration 1, phase "pick".

## Iteration budget

**Soft cap: 8 iterations per user-initiated run.** After the 8th merged PR, stop and wait for the user to restart. Prevents runaway loops.

The `--iteration N` flag enforces the cap across orchestrator ticks — always carry it in every `AE_NEXT` prompt until you `AE_STOP`.

## Cycle

### 1. Pick an unblocked issue

{{#if PLAYBOOK_PRIORITIZATION}}The picking rules live in `{{PLAYBOOK_PRIORITIZATION}}` — this step is the mechanical implementation of that policy.{{else}}Pick the highest-priority unblocked issue from the backlog.{{/if}}

Enumerate open issues via the `list_open_issues` recipe in `{{PLAYBOOK_TRACKER}}`, then filter in memory:

- **Unassigned only**: drop anything whose `assignees` is non-empty.
- **Not labeled**: drop `blocked`, `needs-discussion`, `question`, `wontfix`.
- **No unresolved dep**: drop issues whose body references an unresolved prerequisite (e.g. "blocked on #NN" where #NN is still open — resolve by calling `get_issue` on the referenced ID and checking its state).

Sort preference (apply in order):

1. `priority:P0` before `priority:P1` before `priority:P2` before `priority:P3`. Issues with no `priority:*` label rank **after** `priority:P3` — they are un-triaged.
2. Within a priority bucket, apply any project-specific area/track ordering from `{{PLAYBOOK_PRIORITIZATION}}` (or lowest-numbered first if no playbook).
3. Within a bucket, lowest-numbered first.

If the top candidate's prerequisites are still open, skip it and try the next one. If a candidate is un-triaged, prefer triaging it via the `file-issue` skill before working it.

If the candidate list is empty → **stop** with message *"no unblocked issues — auto-engineer idle."*

Assign and branch:

- Run the `assign_issue` recipe in `{{PLAYBOOK_TRACKER}}` with assignee `{{GITHUB_USER}}`.
- Then:

```sh
git checkout main && git pull
git checkout -b <branch>   # e.g. m<N>-<slug> or <verb>-<slug>
```

Issue IDs in branch names and slugs follow the tracker's ID format (e.g. GitHub `#18` → `m18-<slug>`; local to-do `#0042` → `m0042-<slug>`).

Then rename the tmux window so a human glancing at the terminal can see which
issue this cycle is on. `<slug>` is the same short slug used in the branch name
(3–4 words, kebab-case).

The mechanism differs by environment because the agent shell has no
controlling terminal, so OSC 2 escapes and `/dev/tty` writes can't reach the
host tmux pane from inside the container:

- **Inside the container**: write the slug to `$AUTO_ENGINEER_SLUG_FILE` (set by
  `scripts/sandbox.sh` to a bind-mounted path). A poller on the host tails that
  file and runs `tmux rename-window "AE -> <slug>"` against the host tmux.
- **On the host (no container)**: call `tmux rename-window` directly.
- **Outside tmux entirely**: no-op.

Unified command:

```sh
if [ -n "${AUTO_ENGINEER_SLUG_FILE:-}" ]; then
    printf '%s' "<slug>" > "$AUTO_ENGINEER_SLUG_FILE"
elif [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    tmux rename-window "AE -> <slug>"
fi
```

### 2. Delegate planning to a sub-agent

Use the **Task** tool with `subagent_type` appropriate for planning (or a dedicated planner subagent under `.cursor/agents/` if the project seeded one). Pass the full issue body, its label list, and any linked issues you fetched. Ask for:

- Files to create / modify (absolute paths).
- Functions or types to add / change, with signatures.
- Tests to add.
- Risks and rollback plan.

Return format: plain markdown, ≤300 words. Read the sub-agent result and proceed — planning is read-only for the sub-agent; implementation happens in this tick (step 3).

### 3. Auto-approve and implement

The parent proceeds directly with `Edit` / `Write` per the returned plan. No user confirmation. If the sub-agent's plan is clearly wrong (wrong file paths, contradicts code you read), re-spawn it once with a corrective prompt; if it's still wrong after that, **stop** and report.

### 4. Build + test

Run in order:

```sh
{{BUILD_CMD}}
{{TEST_CMD}}
```

On failure: diagnose and fix in place. **Maximum 3 fix attempts per cycle.** If the 3rd attempt still fails → **stop** with a summary of the failure and what was tried.

### 5. Commit and open PR

- Coherent commits (not a single mega-commit, not micro-commits). Each with the standard `Co-Authored-By: Cursor <noreply@cursor.com>` trailer.
- `git push -u origin <branch>`.
- Open the PR via `gh pr create` with the standard Summary + Test plan body. **No "generated with" footer.**
- **Always include `Closes #<N>`** on its own line near the top of the PR body. The effect depends on the tracker — see the PR ↔ issue linking section in `{{PLAYBOOK_TRACKER}}`. For GitHub Issues this auto-closes on merge; for local to-do trackers it's a human-readable cross-reference only and step 7 must explicitly close the issue.
- Record the PR number and URL for the rest of the cycle.

{{#if HITL_MODE}}
### 5b. HITL pause (only when `--hitl` flag is set)

After the PR is open and the URL is recorded, check whether `--hitl` is present in the current invocation flags. If it is, and `--hitl-approved` is **not** present, pause here for human review instead of entering the CI/merge loop:

1. Post a comment on the PR summarizing what was built and asking for review:
   ```sh
   gh pr comment <M> --body "auto-engineer paused for human review. Review locally, then resume with:

   /auto-engineer --hitl --iteration N --phase wait --pr M --hitl-approved"
   ```
2. Emit a fallback resume (1 hour) so the loop doesn't hang if the human forgets:
   ```text
   AE_NEXT {"sleep":3600,"prompt":"/auto-engineer --hitl --iteration N --phase wait --pr M --hitl-approved"}
   ```
3. Also print a plain-text status for the human: `"HITL pause: PR #M is open at <URL>."`

When re-entering with `--hitl-approved`, skip this step entirely and proceed to step 6a normally.

**Carry-through rule:** whenever `--hitl` is set, include it in every `AE_NEXT` prompt — it is a session-level sticky flag. Never drop it between iterations or poll ticks.

{{/if}}
### 6. Wait for CI and review

Auto-engineer owns the PR-wait loop directly — do **not** delegate to the `wait-for-pr` skill. Delegating would break the orchestrator prompt chain and there would be no path back into this skill when CI finishes.

The `wait-for-pr` skill is for manual invocations only.

#### 6a. First poll tick (immediately after opening the PR)

Record the PR open time. Run one poll tick (step 6b below), then either proceed or sleep.

#### 6b. Poll tick (re-entry via `--phase wait --pr M`)

1. Check CI state:
   ```sh
   gh pr checks <M> --json name,state,bucket,link
   ```
{{#if REVIEW_BOT_LOGINS}}
2. Count review-bot activity:
   ```sh
   gh api "repos/{{GITHUB_OWNER}}/{{GITHUB_REPO}}/issues/<M>/comments" \
     --jq '[.[] | select(.user.login | test("{{REVIEW_BOT_LOGINS}}"))] | length'
   ```
   Also fetch formal reviews via `gh pr view --json reviews`.
{{/if}}

3. Evaluate "done" criteria:
   - Every check is in a terminal state (`success`, `failure`, `skipped`, `cancelled`, `neutral`, `timed_out`, `stale`) — nothing `in_progress`, `queued`, or `pending`.
{{#if REVIEW_BOT_LOGINS}}   - At least one review-bot comment exists **or** 30 minutes have elapsed since PR opened.
{{/if}}

4. **If done**: proceed to step 6c.

5. **If not done**: emit `AE_NEXT` and stop this tick — do not sleep or poll inside the agent.
   Cadence (`sleep` in JSON):
   | Elapsed since PR opened | sleep (seconds) |
   |---|---|
   | 0–10 min | 120 |
   | 10–30 min | 180 |
   {{#if REVIEW_BOT_LOGINS}}| 30 min+ (bots only) | 1200 |{{/if}}

   Example (adjust flags; include `--hitl` when set; include `--fix-round R` when applicable):
   ```text
   AE_NEXT {"sleep":120,"prompt":"/auto-engineer --iteration N --phase wait --pr M"}
   ```

   If any check is `action_required` → **stop** with `AE_STOP` instead (human must approve).

#### 6c. Review-response

Carry a `--fix-round R` counter (default 0) forward in the wakeup prompt when looping back here. **Max 2 fix rounds** — if `R == 2` and findings remain, stop.

**Auto-fix CI failures** (before classifying review findings):

| Failed check pattern | Fix command | Canonical commit subject |
|---|---|---|
| format / lint check matching `{{FORMAT_FIX_COMMIT}}` sentinel | `{{FORMAT_CMD}}` | `{{FORMAT_FIX_COMMIT}}` |
| lint check matching `{{LINT_FIX_COMMIT}}` sentinel | `{{LINT_FIX_CMD}}` | `{{LINT_FIX_COMMIT}}` |

Before applying: check `git log origin/<base>..HEAD --format='%s'` — if the canonical subject is already there and the check still failed, do not re-apply. Flag as "auto-fix already attempted, did not resolve" and stop.

After applying a fix: commit with the canonical subject + `Co-Authored-By:` trailer, `git push`, then:
```text
AE_NEXT {"sleep":120,"prompt":"/auto-engineer --iteration N --phase wait --pr M --fix-round R"}
```

**Classify review findings**:

- **All green, no actionable findings** → proceed to merge (step 7).
- **Actionable bugs** → apply follow-up commits (never amend), `git push`, then reschedule another poll tick with `--fix-round R+1`.
- **Out-of-scope nits** → reply on the PR via `gh pr comment` ("deferred to future work"), open a follow-up issue via the `file-issue` skill, then proceed to merge.

### 7. Merge

Only merge when **all** are true:
- Every CI check is `success` or `skipped` (none `failure`, `action_required`, `timed_out`, `pending`).
- No unresolved actionable review findings.
{{#if REVIEW_BOT_LOGINS}}- Either ≥1 review bot posted and every actionable finding is addressed, **or** 30 min elapsed since PR open with nothing actionable.{{/if}}

Use the repo's configured merge method (check `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed` and prefer squash if available, otherwise the repo default):

```sh
gh pr merge <N> --squash --delete-branch
```

Post-merge:

```sh
git checkout main && git pull
git branch -d <branch>
```

Then check the PR ↔ issue linking section of `{{PLAYBOOK_TRACKER}}`:

- If the tracker auto-closes via `Closes #<N>` (GitHub Issues): nothing more to do.
- If it does not (local to-do): run the `close_issue` recipe on `<N>` now, passing the merged PR URL for the `closed_by_pr` field. Skipping this leaves the issue open and it'll reappear in next cycle's picker.

### 8. Capture follow-ups

Before reloading the next issue, scan for work that surfaced during this cycle but wasn't in scope. Sources to check:

- The merged diff for new `TODO`, `FIXME`, or `XXX` markers added in this PR (`git log -p -1`).
- Deferred review comments posted in step 6 ("deferred to future work") that didn't already get an issue opened.
- Build/test warnings observed during step 4 that weren't blocking but deserve follow-up.
- Anything the sub-agent's plan (step 2) explicitly listed as "out of scope" or "risks."

For each distinct follow-up, **invoke the `file-issue` skill** — do not call `gh issue create` directly. The `file-issue` skill handles dedupe against existing issues and enforces the label taxonomy. Feed it:

- A specific title.
- A 1–3 sentence motivation, including `discovered while merging #<PR>` so the origin is recoverable later.
- Concrete work items.
- Context (file paths, commit SHAs, related issue numbers).

If nothing worth filing, skip silently. **Do not file speculative or "nice-to-have" issues** — only things with concrete motivation.

### 9. Check session quota (optional)

If the project has a `/usage` skill, run it before starting another cycle. If it reports low quota (`remaining_pct < 10`), do not open a new cycle. Instead:

```text
AE_NEXT {"sleep":<min(secondsUntilReset+60,3300)>,"prompt":"/auto-engineer --iteration N"}
```

If `/usage` is unavailable, skip this gate and proceed to step 10.

### 10. Next cycle

If iteration budget not exhausted and no stop condition tripped:

```text
AE_NEXT {"sleep":60,"prompt":"/auto-engineer --iteration <N+1>"}
```

Never carry `--phase`, `--pr`, or `--fix-round` into a fresh cycle; those are intra-cycle state. Context resets automatically on the next orchestrator tick.

## Stopping

On any stop condition:

1. Leave the current branch and PR in place — do **not** delete or close anything.
2. If a PR exists for the current cycle, post one comment on it via `gh pr comment` summarizing why auto-engineer paused and what it tried.
3. Emit `AE_STOP {"reason":"<short reason>"}` as the last line. Also print a plain-text status for the human.

Stop conditions:

- No unblocked issues remain.
- 3 consecutive build/test fix attempts failed.
- `--fix-round` reached 2 and actionable findings remain.
- Any check in `action_required` state (needs human approval).
- Any security / advisory finding from `github-advanced-security[bot]`.
- Merge conflict against `main` that isn't cleanly resolvable by `git pull --rebase`.
- Iteration budget of 8 reached.
- The issue was reassigned away from `{{GITHUB_USER}}` while auto-engineer held it.

## Never

- Force-push, rebase pushed branches, or rewrite reviewed commits.
- Edit `main` directly.
- Merge without green CI.
- Delegate the PR-wait loop to the `wait-for-pr` skill — it would break the orchestrator prompt chain.
- Poll CI in a tight loop inside one tick — use `AE_NEXT` with `sleep` instead.
- Continue past 8 iterations without a fresh user invocation.
- Auto-fix test or build logic in step 6c (format and lint only; real fixes are follow-up commits).
- Close an issue manually — let the merge do it via the PR body's `Closes #N`.
- Ask the user for input — **never use `AskUserQuestion` or pause for a response**. If information is missing, make the most defensible choice and continue; if a stop condition applies, stop and report but do not ask.{{#if HITL_MODE}} (Exception: `--hitl` mode intentionally pauses at step 5b — that pause is the feature, not a violation of this rule.){{/if}}
