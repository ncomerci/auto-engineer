---
name: wait-for-pr
description: After opening a PR or pushing a fix, wait for all CI checks AND review-bot comments to report, then surface a single unified summary. Use immediately after `gh pr create` or any push that re-triggers checks on a PR.
---

# wait-for-pr

{{#if PLAYBOOK_PR_REVIEW}}Read `{{PLAYBOOK_PR_REVIEW}}` first for repo-level CI readiness and review-classification rules.{{/if}}

Manual PR wait loop. When run under `scripts/orchestrate.sh`, end each tick with `AE_NEXT` or `AE_STOP` (same contract as `auto-engineer`). For a single check without looping, run `scripts/sandbox.sh --once /wait-for-pr`.

## When to invoke

- Immediately after `gh pr create` returns a PR URL.
- After pushing a follow-up commit to a PR branch.
- When the user says "wait for CI," "check the PR," or similar.

## Identifying the PR

If the PR number isn't already known:

```sh
gh pr list --head "$(git branch --show-current)" --json number,url --jq '.[0]'
```

## What "done" means

1. Every CI check is terminal (`success`, `failure`, `skipped`, `cancelled`, `neutral`, `timed_out`, `stale`) — nothing `in_progress`, `queued`, or `pending`.
2. No check in `action_required` (stop with `AE_STOP` — user must act).
3. At least one review-bot comment / review exists, **or** 30 minutes since PR opened.

## Poll cadence (`sleep` in `AE_NEXT`)

| Elapsed since PR opened | sleep (seconds) |
|---|---|
| 0–10 min | 120 |
| 10–30 min | 180 |
| 30 min+ (bots only) | 1200 |

## Each poll tick

1. `gh pr checks <PR> --json name,state,bucket,link`
2. Review bots (if configured): `gh api` comments + `gh pr view --json reviews`
3. If not done:
   ```text
   AE_NEXT {"sleep":120,"prompt":"/wait-for-pr"}
   ```
   (Carry PR number in the prompt if needed, e.g. `/wait-for-pr --pr M`.)
4. If done: auto-fix (below) or summarize and `AE_STOP {"reason":"PR wait complete"}`.

## Auto-fix on failure

Same table and sentinel logic as `auto-engineer` step 6c. After push, `AE_NEXT` to re-enter this skill.

## Summarize

One report: PR title, CI by state, review findings grouped, deferred items.

## Never

- Merge the PR.
- Poll in a tight loop inside one tick — use `AE_NEXT`.
- Block forever on bots — 30 min timeout.
