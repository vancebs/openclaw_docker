#! /bin/bash

##############################################
# get script path/dir of this file
if [ -n "${BASH_SOURCE-}" ]; then
    _script="${BASH_SOURCE[0]}"
else
    _script="$0"
fi

if command -v realpath >/dev/null 2>&1; then
    SCRIPT_PATH="$(realpath "$_script")"
elif command -v readlink >/dev/null 2>&1 && readlink -f "$_script" >/dev/null 2>&1; then
    SCRIPT_PATH="$(readlink -f "$_script")"
else
    SCRIPT_PATH="$(cd "$(dirname "$_script")" 2>/dev/null && pwd -P)/$(basename "$_script")"
fi
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

DOCKER_DIR="${SCRIPT_DIR}/docker"

function enter_docker() {
    pushd ${DOCKER_DIR} > /dev/null 2>&1
}

function leave_docker() {
    popd > /dev/null 2>&1
}

###############################################
# docker_compose

if [ -f "local_env" ]; then
    enter_docker

    set -a; source ./env; source ../local_env; set +a

    DOCKER_COMPOSE_FILES="-f docker-compose.yml"

    # check caddy
    if [ ${ENABLE_CADDY:-0} -eq 1 ] && [ "${OPENCLAW_GATEWAY_ALLOWED_IP:-}" != "" ]; then
        DOCKER_COMPOSE_FILES="$DOCKER_COMPOSE_FILES -f docker-compose.caddy.yml"
    fi

    # check star-office-UI
    if [ ${ENABLE_STAR_OFFICE:-0} -eq 1 ]; then
        DOCKER_COMPOSE_FILES="$DOCKER_COMPOSE_FILES -f docker-compose.star-office.yml"
    fi

    DOCKER_COMPOSE_ENV="--env-file ./env --env-file ../local_env"

    function docker_compose() {
        CHDIR=0
        if [ "$PWD" != "$DOCKER_DIR" ]; then
            CHDIR=1
            enter_docker
        fi

        docker compose ${DOCKER_COMPOSE_FILES} ${DOCKER_COMPOSE_ENV} $@

        if [ $CHDIR -eq 1 ]; then
            leave_docker
        fi
    }

    leave_docker
fi
