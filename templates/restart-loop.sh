#!/usr/bin/env bash
# Restart the auto-engineer loop in a fresh container, optionally resuming
# at a specific iteration. Use when context is corrupting decisions or you
# need a clean environment.
#
# Usage:
#   scripts/restart-loop.sh
#   scripts/restart-loop.sh --iteration N
#
# Forwards args to orchestrate.sh → /auto-engineer --iteration N
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh" /auto-engineer "$@"
