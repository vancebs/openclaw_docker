# Thin local wrapper on top of the official OpenClaw image.
#
# PURPOSE
#   The official image (ghcr.io/openclaw/openclaw) does not ship Playwright
#   browser binaries, and the Debian base image may be missing some of the
#   OS-level shared libraries that Chromium requires at runtime.
#
#   This Dockerfile does ONE thing: installs those OS libraries (libnss3,
#   libgbm1, xvfb, etc.) via playwright install-deps so they become part of
#   the image layer.  The Chromium *binary* itself is intentionally NOT baked
#   in here — it is downloaded by the playwright-init service into the
#   named volume (openclaw_home) on first container start and persists across
#   container recreations.
#
# BUILD & UPDATE
#   Build once:
#     docker compose build
#
#   Update to a newer official image:
#     docker compose build --pull      # re-pulls ghcr.io/openclaw/openclaw:latest
#     docker compose up -d             # recreate containers with fresh image layer

ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM ${OPENCLAW_BASE_IMAGE}

USER root

# Install Playwright Chromium OS-level system dependencies ONLY.
# The browser binary is intentionally NOT baked here — it is installed into
# the named volume by the playwright-init service on every container start.
# `playwright install chromium` is version-aware and idempotent: it skips if
# the correct version is already present, and installs the new version when
# the image is upgraded (playwright-core version changes).
RUN node /app/node_modules/playwright-core/cli.js install-deps chromium \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

USER node
