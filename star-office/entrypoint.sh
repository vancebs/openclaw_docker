#!/usr/bin/env bash
# Star Office UI container entrypoint.
# 1. Initializes /data from bundled sample files (first run only).
# 2. Symlinks /data/* files into /app so app.py writes to the volume.
# 3. Wires up /memory -> openclaw workspace memory (if available).
set -euo pipefail

DATA_DIR="${STAR_OFFICE_DATA_DIR:-/data}"
mkdir -p "${DATA_DIR}"

# ── 1. Seed sample files on first run ────────────────────────────────────────
declare -A SAMPLES=(
    ["state.json"]="state.sample.json"
    ["join-keys.json"]="join-keys.sample.json"
    ["runtime-config.json"]="runtime-config.sample.json"
    ["asset-positions.json"]="asset-positions.json"   # ships as real file
    ["asset-defaults.json"]="asset-defaults.json"     # ships as real file
)

for target_name in "${!SAMPLES[@]}"; do
    dest="${DATA_DIR}/${target_name}"
    if [ ! -f "${dest}" ]; then
        src="/app/${SAMPLES[$target_name]}"
        if [ -f "${src}" ]; then
            cp "${src}" "${dest}"
            echo "[star-office] Initialised ${dest} from ${src}"
        else
            echo "[star-office] Warning: sample ${src} not found, skipping ${dest}"
        fi
    fi
done

# ── 2. Symlink data files from /data into /app ────────────────────────────────
# These are the files app.py reads/writes at ROOT_DIR (= /app).
DATA_FILES=(
    state.json
    agents-state.json
    join-keys.json
    runtime-config.json
    asset-positions.json
    asset-defaults.json
)

for f in "${DATA_FILES[@]}"; do
    app_path="/app/${f}"
    data_path="${DATA_DIR}/${f}"

    # Touch the data-side file so the symlink target always exists
    [ -f "${data_path}" ] || touch "${data_path}"

    # Remove the plain file from the image copy (if not already a symlink)
    if [ -f "${app_path}" ] && [ ! -L "${app_path}" ]; then
        rm -f "${app_path}"
    fi
    # Create/update symlink
    ln -sf "${data_path}" "${app_path}"
done

# ── 3. Wire /memory -> openclaw workspace memory ──────────────────────────────
# app.py: MEMORY_DIR = os.path.dirname(ROOT_DIR) + "/memory"
#         = os.path.dirname("/app") + "/memory" = "/memory"
# If the openclaw_home volume is mounted at /home/node (read-only), we can
# expose its workspace memory here.
OPENCLAW_MEMORY="/home/node/.openclaw/workspace/memory"
if [ -d "${OPENCLAW_MEMORY}" ]; then
    ln -sfn "${OPENCLAW_MEMORY}" /memory
    echo "[star-office] Linked /memory -> ${OPENCLAW_MEMORY}"
else
    mkdir -p /memory
    echo "[star-office] openclaw memory not found, /memory will be empty (昨日小记 feature disabled)"
fi

echo "[star-office] Starting Flask backend..."
exec python /app/backend/app.py
