#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required for autonomous operation}"
: "${CURSOR_API_KEY:?CURSOR_API_KEY is required for autonomous operation}"

GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-auto-engineer}"
GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-noreply@cursor.com}"
REPO_SLUG="${PROJECT_REPO:-dburkart/auto-engineer}"
WORKDIR="${PROJECT_WORKDIR:-/home/agent/work}"

git config --global user.name  "$GIT_AUTHOR_NAME"
git config --global user.email "$GIT_AUTHOR_EMAIL"
git config --global init.defaultBranch main

gh auth setup-git >/dev/null

cd "$WORKDIR"
if [ ! -d .git ]; then
    gh repo clone "$REPO_SLUG" .
fi

if [ "$#" -eq 0 ]; then
    set -- /auto-engineer --iteration 1
fi

exec /usr/local/bin/orchestrate.sh "$@"
