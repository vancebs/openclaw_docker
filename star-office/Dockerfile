FROM python:3.12-slim

# Install git and curl (git for clone, curl for healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone Star-Office-UI at build time (depth=1 for minimal size).
# Each image rebuild picks up the latest commit automatically.
ARG STAR_OFFICE_REPO=https://github.com/ringhyacinth/Star-Office-UI.git
RUN git clone --depth=1 "${STAR_OFFICE_REPO}" .

# Install Python dependencies
RUN pip install --no-cache-dir -r backend/requirements.txt

# Entrypoint handles data-volume init + symlinks
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 18791

ENTRYPOINT ["/entrypoint.sh"]
