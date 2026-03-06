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

# 1. Playwright system deps + Homebrew prerequisites (gcc, make, etc.)
RUN apt-get update \
 && node /app/node_modules/playwright-core/cli.js install-deps chromium \
 && apt-get install -y --no-install-recommends \
        build-essential \
        procps \
        file \
        git \
        curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# 2. Install Homebrew into /home/node/homebrew.
#    • Uses the alternative "git clone" method instead of the official install
#      script, because the script refuses to install to a custom prefix for
#      non-root users (it only supports /home/linuxbrew/.linuxbrew by default).
#    • Runs as 'node' — files are owned correctly from the start.
#    • /home/node is backed by the named volume, so brew itself and every
#      package installed afterwards persist across container recreations and
#      image upgrades (upgrade image → keep volume → keep installed tools).
#    • The three ENV vars tell brew where it lives; PATH is updated so that
#      subsequent RUN steps and the running container can call `brew` directly.
USER node
ENV HOMEBREW_PREFIX=/home/node/homebrew \
    HOMEBREW_CELLAR=/home/node/homebrew/Cellar \
    HOMEBREW_REPOSITORY=/home/node/homebrew
ENV PATH="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${PATH}"

RUN git clone --depth=1 https://github.com/Homebrew/brew.git "${HOMEBREW_PREFIX}" \
 && "${HOMEBREW_PREFIX}/bin/brew" update --force --quiet
