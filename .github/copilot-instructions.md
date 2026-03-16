# Copilot instructions — openclaw_docker

This file captures repository-specific commands, high-level architecture, and conventions to help future Copilot sessions work effectively in this repository.

---

## Build / run / lint / test commands

- Primary workflow is Docker-based. Recommended quick start:
  - Copy example env and edit: `cp ./env_sample ./.env`
  - Bootstrap (build images, run onboarding, start services): `./start.sh -i` (same as `./start.sh --install`). This runs `docker compose build --pull`, runs onboarding commands in the openclaw image, sets required config values, then `docker compose up -d`.
  - Start services (no bootstrap): `./start.sh` (this calls `docker compose up -d` with the appropriate compose files selected by `.env`).

- Manual compose operations:
  - Build images: `docker compose build` (use `--pull` to refresh base images)
  - Recreate/start containers: `docker compose up -d`
  - When enabling optional services, include the extra compose files: `docker compose -f docker-compose.yml -f docker-compose.caddy.yml -f docker-compose.star-office.yml up -d` (the `start.sh` wrapper picks the right files automatically based on `.env`).

- Useful runtime helpers:
  - Exec into the gateway container: `./exec.sh /bin/bash`
  - Run OpenClaw CLI inside container: `./openclaw.sh devices list` or `./openclaw.sh devices approve <requestId>`
  - Print host mountpoint of the persistent volume: `./openclaw_home_path.sh`
  - Set tools profile as documented in README: `./exec.sh openclaw config set tools.profile 'full' --strict-json`

- Tests & linting
  - No repository-level test or lint configuration was detected (no package.json, pyproject.toml, requirements.txt, Makefile, or tests/ directory). If tests are added, run them inside the running `openclaw-gateway` container or in CI that mirrors the container environment.

---

## High-level architecture (big picture)

- Purpose: This repo provides a Dockerized deployment of OpenClaw with optional Star Office UI and an optional Caddy reverse-proxy to expose the control UI securely.

- Core pieces:
  - `docker-compose.yml` — defines the `openclaw-gateway` service and the named volume `openclaw_home` (persistent `/home/node`), plus healthchecks and ports.
  - `docker-compose.caddy.yml` — optional Caddy reverse proxy (enabled via `ENABLE_CADDY=1` and `OPENCLAW_GATEWAY_ALLOWED_IP` in `.env`).
  - `docker-compose.star-office.yml` — optional Star Office UI service (enabled via `ENABLE_STAR_OFFICE=1`).
  - `openclaw/Dockerfile` — extends the official OpenClaw image to install Playwright system libraries, Homebrew/pnpm setup, and related OS packages. Playwright browser binaries are intentionally not baked into the image; they are downloaded into the `openclaw_home` volume on first start.
  - Named volume `openclaw_home` — central persistent store for user data and downloaded browser runtimes. The Star Office UI mounts this volume read-only for some features.

- Wrappers and scripts:
  - `start.sh` — bootstrap and start wrapper. With `-i/--install` it generates Caddyfile (when appropriate), builds images (`docker compose build --pull`), runs onboarding (`node dist/index.js onboard` inside the image), configures gateway settings, then brings services up.
  - `utils.sh` — defines a `docker_compose()` helper that composes the `-f` arguments based on `.env` flags; all wrappers source this for consistent compose usage.
  - `exec.sh` / `openclaw.sh` — convenience wrappers for `docker compose exec openclaw-gateway ...` (shell or `openclaw` CLI respectively).
  - `openclaw_home_path.sh` — emits the host-side mountpoint of the named `openclaw_home` volume.

---

## Key conventions and repo-specific patterns

- Environment management
  - Copy `env_sample` → `.env` and edit secrets and feature flags. `start.sh` will auto-copy if `.env` is missing.
  - Toggle optional services with env flags: `ENABLE_CADDY`, `ENABLE_STAR_OFFICE`. Caddy also requires `OPENCLAW_GATEWAY_ALLOWED_IP` to generate and enable the Caddyfile.

- Compose file selection
  - The `docker_compose()` helper in `utils.sh` constructs the `docker compose -f ...` arguments; prefer using `start.sh` for consistent behavior, or replicate the same `-f` flags when calling `docker compose` manually.

- Playwright & persistent browsers
  - The Dockerfile installs Playwright *system* deps; Playwright browser downloads are persisted to `openclaw_home` and are not baked into the image. To update the base image safely, run `docker compose build --pull && docker compose up -d` so the download step can cache into the existing volume.

- CLI & pairing operations
  - For control UI pairing and device approval, either shell into the container (`./exec.sh /bin/bash`) and use the `openclaw` CLI, or run `./openclaw.sh devices list` / `./openclaw.sh devices approve <requestId>` from the host.

---

## AI assistant / Copilot-specific notes

- No assistant-specific config files (CLAUDE.md, .cursorrules, AGENTS.md, .windsurfrules, AIDER_CONVENTIONS.md, .clinerules, etc.) were found in the repository root.

---

## Short checklist for Copilot sessions

- Ensure `.env` exists and contains required tokens/passwords: `cp ./env_sample ./.env` then edit.
- Bootstrap: `./start.sh -i` (recommended first run).
- Rebuild base image: `docker compose build --pull && docker compose up -d`.
- Shell into container: `./exec.sh /bin/bash`.
- Run `openclaw` CLI: `./openclaw.sh devices list`.

---

(Generated by Copilot CLI analysis.)
