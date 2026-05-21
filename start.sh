#! /bin/bash
set -euo pipefail

COLOR_BLACK=30
COLOR_RED=31
COLOR_GREEN=32
COLOR_YELLOW=33
COLOR_BLUE=34
COLOR_PURPLE=35
COLOR_WHITE=37

function print_color() {
    # $1: color number
    # $2: message
    echo -e "\e[$1m$2\e[0m"
}

# get parameters
while [ $# -ge 1 ]; do
    case $1 in
        -p | -ps | --push)
            PARAM_PUSH=1
            ;;
        -pl | --pull)
            PARAM_PULL=1
            ;;
        -i | --install)
            PARAM_INSTALL=1
            ;;
        -u | --update)
            PARAM_UPDATE=1
            ;;
        *)
            # assume it's version
            print_color $COLOR_RED "ERROR!! unknown param"
            exit 1
    esac

    # next
    shift
done

PARAM_PUSH=${PARAM_PUSH:-0}
PARAM_PULL=${PARAM_PULL:-0}
PARAM_INSTALL=${PARAM_INSTALL:-0}
PARAM_UPDATE=${PARAM_UPDATE:-0}

if [ $PARAM_INSTALL -eq 1 ] || [ $PARAM_UPDATE -eq 1 ]; then
    SHOULD_INSTALL_UPDATE=1
else
    SHOULD_INSTALL_UPDATE=0
fi

if [ $SHOULD_INSTALL_UPDATE -eq 1 ] && [ $PARAM_PULL -ne 1 ]; then
    SHOULD_BUILD_IMAGE=1
else
    SHOULD_BUILD_IMAGE=0
fi

if [ $PARAM_INSTALL -eq 1 ] && [ $PARAM_UPDATE -eq 1 ]; then
    print_color $COLOR_RED "ERROR!! --install and --update should not assigned together"
    exit 1
elif [ $PARAM_PUSH -eq 1 ] && [ $PARAM_PULL -eq 1 ]; then
    print_color $COLOR_RED "ERROR!! --push and --pull should not assigend together"
    exit 1
elif [ $PARAM_PUSH -eq 1 ] && [ $SHOULD_BUILD_IMAGE -ne 1 ]; then
    print_color $COLOR_RED "ERROR!! --push should be used together with --install or --update"
    exit 1
fi

# ── .env bootstrap ────────────────────────────────────────────────────────────
source utils.sh
ENV_PATH="${SCRIPT_DIR}/local_env"
ENV_SAMPLE_PATH="${DOCKER_DIR}/local_env_sample"
if [ ! -f "${ENV_PATH}" ]; then
    cp ${ENV_SAMPLE_PATH} ${ENV_PATH}
    echo ""
    echo "============================================================"
    echo "  \"${ENV_PATH}\" 文件已创建。"
    echo "  请编辑 local_env 填写必要配置（Token、Proxy 等），"
    echo "  完成后回到此终端按 Enter 继续。"
    echo "============================================================"
    echo ""
    read -rp "编辑完成后按 Enter 继续..." _
    echo ""
fi

# load env
source utils.sh
pushd ${DOCKER_DIR} > /dev/null 2>&1

# build image
if [ $SHOULD_BUILD_IMAGE -eq 1 ]; then
    echo "==> Building images ..."
    docker_compose build --pull
fi

# push image
if [ $PARAM_PUSH -eq 1 ]; then
    echo "==> Pushing images ..."
    IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw-hf}:${OPENCLAW_IMG_VERSION:-latest}"
    REMOTE_NAME="${DOCKER_REGISTRY}/${OPENCLAW_IMAGE:-openclaw-hf}:${OPENCLAW_IMG_VERSION:-latest}"
    REMOTE_NAME_LATEST="${DOCKER_REGISTRY}/${OPENCLAW_IMAGE:-openclaw-hf}:latest"

    print_color $COLOR_YELLOW "local: ${IMAGE_NAME}"
    print_color $COLOR_YELLOW "remote: ${REMOTE_NAME}"
    print_color $COLOR_YELLOW "remote: ${REMOTE_NAME_LATEST}"

    docker tag "${IMAGE_NAME}" "${REMOTE_NAME}"
    docker tag "${IMAGE_NAME}" "${REMOTE_NAME_LATEST}"

    docker push "${REMOTE_NAME}"
    docker push "${REMOTE_NAME_LATEST}"
elif [ $PARAM_PULL -eq 1 ]; then
    echo "==> Pulling image ..."
    IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw-hf}:${OPENCLAW_IMG_VERSION:-latest}"
    REMOTE_NAME="${DOCKER_REGISTRY}/${OPENCLAW_IMAGE:-openclaw-hf}:${OPENCLAW_IMG_VERSION:-latest}"

    print_color $COLOR_YELLOW "local: ${IMAGE_NAME}"
    print_color $COLOR_YELLOW "remote: ${REMOTE_NAME}"

    docker pull "$REMOTE_NAME"

    docker tag "$REMOTE_NAME" "$IMAGE_NAME"
fi

# check for install
if [ $PARAM_INSTALL -eq 1 ]; then
    if [ ${ENABLE_CADDY:-0} -eq 1 ]; then
        echo "==> Prepare Caddyfile ..."
        CADDY_CONF_DIR="$PWD/caddy_conf"
        CADDY_FILE="$CADDY_CONF_DIR/Caddyfile"
        mkdir -p "${CADDY_CONF_DIR}"
        if [ "${OPENCLAW_GATEWAY_ALLOWED_IP:-}" != "" ]; then
            echo "  --> Generating Caddyfile ..."
            CADDY_URLS="$(printf ", %s" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
            echo "{" > "${CADDY_FILE}"
	    echo "    default_sni 127.0.0.1"  >> "${CADDY_FILE}"
	    echo "}" >> "${CADDY_FILE}"
            echo "127.0.0.1${CADDY_URLS} {" >> "${CADDY_FILE}"
            echo "    tls internal" >> "${CADDY_FILE}"
            echo "    reverse_proxy openclaw-gateway:${OPENCLAW_GATEWAY_PORT}" >> "${CADDY_FILE}"
            echo "}" >> "${CADDY_FILE}"
        else
            echo "  --> Skip Caddyfile due to OPENCLAW_GATEWAY_ALLOWED_IP not set or empty ..."
        fi
    fi

    echo "==> onboard ..."
    docker_compose run --rm openclaw-gateway \
        node dist/index.js onboard

    echo "==> Configure mode ..."
    docker_compose run --rm openclaw-gateway \
        node dist/index.js config set gateway.mode local

    echo "==> Configure bind ..." # already configured by OPENCLAW_GATEWAY_BIND within .env
    docker_compose run --rm openclaw-gateway \
        node dist/index.js config set gateway.bind ${OPENCLAW_GATEWAY_BIND}

    echo "==> Configure allowedOrigins ..."
    URLS=""
    if [ "${OPENCLAW_GATEWAY_ALLOWED_IP:-}" != "" ]; then
        HTTPS_PORT=${OPENCLAW_GATEWAY_HTTPS_PORT:-443}
	URLS="$(printf ,\"https://%s:${HTTPS_PORT}\" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
        if [ ${HTTPS_PORT} -eq 443 ]; then
            # for 443, also allow urls without port
            URLS="$URLS$(printf ,\"https://%s\" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
        fi
    fi
    URLS="[\"http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}\",\"http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}\"${URLS}]"
    docker_compose run --rm openclaw-gateway \
        node dist/index.js config set gateway.controlUi.allowedOrigins \
        "${URLS}" \
        --strict-json

    echo "==> Configure memorySearch extraPaths ..."
    docker_compose run --rm openclaw-gateway \
        node dist/index.js config set agents.defaults.memorySearch.extraPaths \
        "[\"\${KNOWLEDGE_BASE_DIR}\"]" \
        --strict-json
elif [ $PARAM_UPDATE -eq 1 ]; then
    echo "==> Shuting down ..."
    docker_compose down
fi

echo "==> Starting services ..."
docker_compose up -d

popd > /dev/null 2>&1
