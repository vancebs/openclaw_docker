#! /bin/bash
set -euo pipefail

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

# check for install
if [[ "${1:-}" == "--install" || "${1:-}" == "-i" ]]; then
    if [ ${ENABLE_CADDY:-0} -eq 1 ]; then
        echo "==> Prepare Caddyfile ..."
        CADDY_CONF_DIR="$PWD/caddy_conf"
        CADDY_FILE="$CADDY_CONF_DIR/Caddyfile"
        mkdir -p "${CADDY_CONF_DIR}"
        if [ "${OPENCLAW_GATEWAY_ALLOWED_IP:-}" != "" ]; then
            echo "  --> Generating Caddyfile ..."
            CADDY_URLS="$(printf ", %s" ${OPENCLAW_GATEWAY_ALLOWED_IP})"
            echo "{" > "${CADDY_FILE}"
	    echo "	default_sni 127.0.0.1"  >> "${CADDY_FILE}"
	    echo "}" >> "${CADDY_FILE}"
            echo "127.0.0.1${CADDY_URLS} {" >> "${CADDY_FILE}"
            echo "	tls internal" >> "${CADDY_FILE}"
            echo "	reverse_proxy openclaw-gateway:${OPENCLAW_GATEWAY_PORT}" >> "${CADDY_FILE}"
            echo "}" >> "${CADDY_FILE}"
        else
            echo "  --> Skip Caddyfile due to OPENCLAW_GATEWAY_ALLOWED_IP not set or empty ..."
        fi
    fi

    echo "==> Building images ..."
    docker_compose build --pull

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
fi

echo "==> Starting services ..."
docker_compose up -d

popd > /dev/null 2>&1
