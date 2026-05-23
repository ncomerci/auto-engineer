---
name: context-reset
description: Guidance on resetting context between auto-engineer iterations — orchestrator ticks, interactive /compress, or container restart via scripts/restart-loop.sh.
---

# context-reset

> Reference only — not an executable action.

## Headless loop (Docker / orchestrate.sh)

Each `orchestrate.sh` tick runs `agent -p` with a **fresh session**. State lives in the prompt flags (`--iteration N`, `--phase wait`, `--pr M`), not in conversation memory. You do **not** need `/compact` between cycles in this mode.

## Interactive Cursor Agent CLI

| Situation | Action |
|---|---|
| Long interactive session, trim cost | `/compress` |
| Context corruption | `/new-chat`, then `/auto-engineer --iteration N` |
| Fresh container / credentials | `scripts/restart-loop.sh --iteration N` |

## Decision guide

1. Running via `scripts/auto-engineer.sh` → context resets automatically each tick.
2. Interactive stale context → `/compress` or `/new-chat` + explicit `--iteration N`.
3. Broken container or full window → `scripts/restart-loop.sh --iteration N`.
