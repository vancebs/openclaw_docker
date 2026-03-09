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
INSTALL=0
if [[ "${1:-}" == "--install" || "${1:-}" == "-i" ]]; then
    INSTALL=1
fi

if [[ $INSTALL -eq 1 ]]; then
    echo "==> Building images ..."
    docker compose build --pull
fi

echo "==> Starting services ..."
docker compose up -d

echo "==> Wait for openclaw-gateway ready..."
until docker compose ps openclaw-gateway | grep -q "Up"; do
    sleep 1
done

echo "==> Updating playwright"
docker compose exec openclaw-gateway node /app/node_modules/playwright-core/cli.js install chromium

if [[ $INSTALL -eq 1 ]]; then
    echo "==> Running onboarding wizard ..."
    docker compose exec openclaw-gateway openclaw onboard
fi
