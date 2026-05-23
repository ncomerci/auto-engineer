---
name: usage
description: Report session quota hints for auto-engineer's step 9 gate. Use when the user asks about usage or before starting another cycle when quota may be low.
---

# usage

Cursor Agent CLI does not expose the same Anthropic rate-limit headers as Claude Code. This skill provides a **best-effort** gate for `auto-engineer` step 9.

## Primary command

```sh
agent about 2>/dev/null || agent status 2>/dev/null || true
```

Parse any usage or limit hints from the output if present.

## Output format (always emit for auto-engineer)

If you cannot determine quota, assume healthy and emit:

```
remaining_pct: 100.0
reset_ts: 1970-01-01T00:00:00Z
```

Followed by a one-line note: `usage: Cursor quota API not available — gate skipped`.

If you find concrete limit data, set:

```
remaining_pct: <float>
reset_ts: <ISO-8601>
```

## auto-engineer step 9

- `remaining_pct >= 10` → proceed to step 10 (`AE_NEXT` next cycle).
- `remaining_pct < 10` → `AE_NEXT` with `sleep` until reset (cap at 3300s) instead of starting a new issue cycle.

## Caveats

- Do not run legacy `probe.sh` (Anthropic-specific) on Cursor-only projects.
- When in doubt, skip the gate rather than blocking the loop indefinitely.
