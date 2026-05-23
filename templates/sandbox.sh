#!/usr/bin/env bash
# Launch the project's auto-engineer container.
#
# Usage:
#   scripts/sandbox.sh                      # run default CMD (orchestrate loop)
#   scripts/sandbox.sh --build-only         # build the image without running
#   scripts/sandbox.sh /some-skill          # one orchestrator tick (--once)
#   scripts/sandbox.sh --direct /seed       # single agent -p, no AE_* contract
#   scripts/sandbox.sh -- --once /wait-for-pr
#
# Reads .env from the repo root if present (CURSOR_API_KEY, GITHUB_TOKEN).
set -euo pipefail

IMAGE="${PROJECT_IMAGE:-{{GITHUB_REPO}}-auto-engineer}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

build_only=0
if [ "${1:-}" = "--build-only" ]; then
    build_only=1
    shift
fi
if [ "${1:-}" = "--" ]; then
    shift
fi

if [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_ROOT/.env"
    set +a
fi

docker build -t "$IMAGE" -f "$REPO_ROOT/Dockerfile" "$REPO_ROOT"

if [ "$build_only" -eq 1 ]; then
    exit 0
fi

if [ -z "${CURSOR_API_KEY:-}" ]; then
    echo "error: CURSOR_API_KEY is not set — add it to .env or export it (Cursor Dashboard → Integrations)" >&2
    exit 1
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "error: GITHUB_TOKEN is not set — add it to .env or export it" >&2
    exit 1
fi

docker_sec_opts=()
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" != "Disabled" ]; then
    docker_sec_opts+=(--security-opt label=disable)
fi

cursor_vol_opts=()
if [ -d "$REPO_ROOT/.cursor" ]; then
    cursor_vol_opts+=(-v "$REPO_ROOT/.cursor:/home/agent/work/.cursor:ro")
fi
if [ -f "$HOME/.cursor/mcp.json" ]; then
    cursor_vol_opts+=(-v "$HOME/.cursor/mcp.json:/home/agent/.cursor/mcp.json:ro")
fi

tmux_slug_vol_opts=()
slug_file=""
poller_pid=""
restore_tmux_rename=""
if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
    prev="$(tmux show-window-options -v automatic-rename 2>/dev/null || echo on)"
    tmux set-window-option automatic-rename off >/dev/null 2>&1 || true
    restore_tmux_rename="$prev"

    slug_file="$(mktemp -t auto-engineer-slug.XXXXXX)"
    tmux_slug_vol_opts+=(
        -v "$slug_file:/tmp/auto-engineer-slug"
        -e AUTO_ENGINEER_SLUG_FILE=/tmp/auto-engineer-slug
    )

    (
        last=""
        while [ -e "$slug_file" ]; do
            cur="$(cat "$slug_file" 2>/dev/null || true)"
            if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
                tmux rename-window "AE -> $cur" >/dev/null 2>&1 || true
                last="$cur"
            fi
            sleep 1
        done
    ) &
    poller_pid=$!

    trap '
        [ -n "$poller_pid" ] && kill "$poller_pid" 2>/dev/null || true
        [ -n "$slug_file" ] && rm -f "$slug_file" 2>/dev/null || true
        tmux set-window-option automatic-rename "$restore_tmux_rename" >/dev/null 2>&1 || true
    ' EXIT
fi

# Default: single skill tick unless user passed orchestrate flags
docker_args=("$@")
if [ ${#docker_args[@]} -eq 0 ]; then
    docker_args=(/auto-engineer --iteration 1)
elif [ "${docker_args[0]}" != --once ] && [ "${docker_args[0]}" != --direct ] && [[ "${docker_args[0]}" != /* ]]; then
    docker_args=(--once "${docker_args[@]}")
fi

docker run --rm -it \
    ${docker_sec_opts[@]+"${docker_sec_opts[@]}"} \
    "${cursor_vol_opts[@]}" \
    ${tmux_slug_vol_opts[@]+"${tmux_slug_vol_opts[@]}"} \
    -e GITHUB_TOKEN \
    -e CURSOR_API_KEY \
    -e GIT_AUTHOR_NAME \
    -e GIT_AUTHOR_EMAIL \
    -e PROJECT_REPO \
    "$IMAGE" "${docker_args[@]}"
