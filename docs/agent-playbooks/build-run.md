# Build & Run Playbook — auto-engineer

## Project type

This is a template/skill-only project. There is no compiled code, no build step, and no test suite. The project consists of:

- Cursor Agent CLI skill definitions (`.cursor/skills/*/SKILL.md`)
- Template files for seeding other projects (`templates/`)
- Shell scripts for Docker-based autonomous execution (`scripts/`)
- A Dockerfile for containerized runs

## "Building"

No build step required. To verify the Docker image builds:

```sh
scripts/sandbox.sh --build-only
```

## Running

- **Sandbox mode**: `scripts/sandbox.sh /some-skill` — builds and runs the container (one tick by default)
- **Auto-engineer loop**: `scripts/auto-engineer.sh` — runs `orchestrate.sh` until `AE_STOP`
- **Local (no container)**: `agent -p --force "/auto-engineer --iteration 1"` from the repo root

## Dependencies

- Docker (for containerized execution)
- `gh` CLI (for GitHub operations)
- Cursor Agent CLI (`agent`, installed in the container or on the host)

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `GITHUB_TOKEN` | Yes (in container) | GitHub personal access token for `gh` |
| `CURSOR_API_KEY` | Yes (in container) | Cursor API key for `agent -p` |
| `GIT_AUTHOR_NAME` | No | Defaults to `auto-engineer` |
| `GIT_AUTHOR_EMAIL` | No | Defaults to `noreply@cursor.com` |
| `PROJECT_REPO` | No | Defaults to `dburkart/auto-engineer` |
