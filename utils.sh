#! /bin/bash

# docker compose auto-reads .env; source it here only to get the vars we
# need for the manual `docker build` call below.
set -a; source .env; set +a

DOCKER_COMPOSE_FILES="-f docker-compose.yml"

# check caddy
if [ ${ENABLE_CADDY:-0} -eq 1 ] && [ "${OPENCLAW_GATEWAY_ALLOWED_IP:-}" != "" ]; then
    DOCKER_COMPOSE_FILES="$DOCKER_COMPOSE_FILES -f docker-compose.caddy.yml"
fi

function docker_compose() {
    docker compose ${DOCKER_COMPOSE_FILES} $@
}
