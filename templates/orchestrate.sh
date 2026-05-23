#!/usr/bin/env bash
# Drive auto-engineer (or any skill) in a loop: run agent -p per tick, parse
# AE_NEXT / AE_STOP control lines, sleep, repeat. Replaces Claude ScheduleWakeup.
#
# Usage:
#   orchestrate.sh [/auto-engineer --iteration 1]
#   orchestrate.sh --once /wait-for-pr
#   orchestrate.sh --direct /seed          # single agent -p, no AE_* required
set -euo pipefail

: "${CURSOR_API_KEY:?CURSOR_API_KEY is required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

WORKDIR="${PROJECT_WORKDIR:-/home/agent/work}"
ONCE=0
DIRECT=0
LOG_PREFIX="[orchestrate]"

while [ $# -gt 0 ]; do
    case "$1" in
        --once)
            ONCE=1
            shift
            ;;
        --direct)
            DIRECT=1
            shift
            ;;
        -h|--help)
            echo "Usage: orchestrate.sh [--once|--direct] [/skill args...]" >&2
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [ $# -eq 0 ]; then
    set -- /auto-engineer --iteration 1
fi

PROMPT="$*"

log() {
    printf '%s %s\n' "$LOG_PREFIX" "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"
}

cleanup() {
    log "received signal, exiting"
}
trap cleanup TERM INT

run_agent() {
    local prompt="$1"
    local out rc
    set +e
    out="$(agent -p --force --trust --approve-mcps \
        --workspace "$WORKDIR" \
        --output-format text \
        "$prompt" 2>&1)"
    rc=$?
    set -e
    printf '%s\n' "$out"
    return "$rc"
}

parse_control() {
    local out="$1"
    CONTROL_LINE="$(printf '%s\n' "$out" | grep -E '^AE_(NEXT|STOP) ' | tail -1 || true)"
}

handle_control() {
    local agent_rc="${1:-0}"

    if [ "$DIRECT" -eq 1 ]; then
        return 0
    fi

    if [ -z "${CONTROL_LINE:-}" ]; then
        log "agent exit=$agent_rc but no AE_NEXT/AE_STOP in output" >&2
        return 1
    fi

    if [[ "$CONTROL_LINE" == AE_STOP* ]]; then
        local json="${CONTROL_LINE#AE_STOP }"
        local reason
        reason="$(printf '%s' "$json" | jq -r '.reason // "stopped"')"
        log "AE_STOP: $reason"
        return 2
    fi

    if [[ "$CONTROL_LINE" == AE_NEXT* ]]; then
        local json="${CONTROL_LINE#AE_NEXT }"
        NEXT_SLEEP="$(printf '%s' "$json" | jq -r '.sleep')"
        PROMPT="$(printf '%s' "$json" | jq -r '.prompt')"
        if [ -z "$NEXT_SLEEP" ] || [ "$NEXT_SLEEP" = "null" ] || [ -z "$PROMPT" ] || [ "$PROMPT" = "null" ]; then
            log "invalid AE_NEXT JSON: $json" >&2
            return 1
        fi
        log "AE_NEXT sleep=${NEXT_SLEEP}s prompt=${PROMPT}"
        return 0
    fi

    log "unrecognized control line: $CONTROL_LINE" >&2
    return 1
}

NEXT_SLEEP=0
CONTROL_LINE=""

while true; do
    log "tick prompt=${PROMPT}"
    OUT="$(run_agent "$PROMPT")"
    AGENT_RC=$?
    printf '%s\n' "$OUT"

    if [ "$DIRECT" -eq 1 ]; then
        exit "$AGENT_RC"
    fi

    parse_control "$OUT"
    HC_RC=0
    handle_control "$AGENT_RC" || HC_RC=$?

    case "$HC_RC" in
        0)
            if [ "$ONCE" -eq 1 ]; then
                exit "$AGENT_RC"
            fi
            sleep "$NEXT_SLEEP"
            ;;
        2)
            exit 0
            ;;
        *)
            exit 1
            ;;
    esac
done
