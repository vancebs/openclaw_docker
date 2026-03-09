#! /bin/bash
set -euo pipefail

# ── .env bootstrap ────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
    cp env_sample .env
    echo ""
    echo "============================================================"
    echo "  .env 文件已从 env_sample 复制。"
    echo "  请编辑 .env 填写必要配置（Token、Secret Key 等），"
    echo "  完成后回到此终端按 Enter 继续。"
    echo "============================================================"
    echo ""
    read -rp "编辑完成后按 Enter 继续..." _
    echo ""
fi

# docker compose auto-reads .env; source it here only to get the vars we
# need for the manual `docker build` call below.
set -a; source .env; set +a

# check for install
if [[ "${1:-}" == "--install" || "${1:-}" == "-i" ]]; then
    echo "==> Building images ..."
    docker compose build --pull

    echo "==> onboard ..."
    docker compose run --rm openclaw-gateway \
        node dist/index.js onboard

    echo "==> Configure mode & bind"
    docker compose run --rm openclaw-gateway \
        node dist/index.js config set gateway.mode local
    docker compose run --rm openclaw-gateway \
        node dist/index.js config set gateway.bind lan

    echo "==> Configure allowedOrigins ..."
    docker compose run --rm openclaw-gateway \
        node dist/index.js config set gateway.controlUi.allowedOrigins \
        "$(printf '["http://127.0.0.1:%s"]' "$OPENCLAW_GATEWAY_PORT")" \
        --strict-json
fi

echo "==> Starting services ..."
docker compose up -d

