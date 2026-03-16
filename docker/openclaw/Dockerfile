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

# setup proxy
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ENV HTTP_PROXY=${HTTP_PROYX:-}
ENV HTTPS_PROXY=${HTTPS_PROYX:-}
ENV NO_PROXY=${NO_PROXY:-}

# setup PLAYWRIGHT_BROWSERS_PATH
ENV PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright

USER root

# 1. Playwright system deps + Homebrew prerequisites (gcc, make, etc.)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        procps \
        file \
        git \
        curl \
        vim \
        netcat-openbsd \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
RUN mkdir -p /home/linuxbrew \
 && chmod 755 /home/linuxbrew \
 && ln -s /home/node/.linuxbrew /home/linuxbrew/.linuxbrew

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
WORKDIR /home/node

ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew
ENV HOMEBREW_CELLAR=${HOMEBREW_PREFIX}/Cellar
ENV HOMEBREW_REPOSITORY=${HOMEBREW_PREFIX}
ENV PATH="${HOMEBREW_PREFIX}/bin:${HOMEBREW_PREFIX}/sbin:${PATH}"

RUN git clone --depth=1 https://github.com/Homebrew/brew.git "/home/node/.linuxbrew" \
 && "${HOMEBREW_PREFIX}/bin/brew" update --force --quiet

# pnpm setup
ENV PNPM_HOME="/home/node/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN corepack enable

# switch to /app to follow original behavior
WORKDIR /app
